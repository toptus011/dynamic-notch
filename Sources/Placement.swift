// Placement.swift – gdzie na pasku menu jest wolne miejsce na wcięcie
//
// - ekran: tylko wbudowany ekran MacBooka (nie rzutnik ani monitor),
// - pasek menu widoczny? (w trybie pełnoekranowym i podczas pokazu Keynote – nie),
// - gdzie kończą się menu aktywnego programu (Dostępność, AXMenuBar),
// - gdzie zaczynają się ikony po prawej (okna pozycji paska menu).

import Cocoa
import ApplicationServices

struct MenuBarInfo {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let height: CGFloat
    let visible: Bool
    let menusRight: CGFloat?    // współrzędna x (globalna) końca menu programu
    let statusLeft: CGFloat?    // współrzędna x początku ikon po prawej

    enum Slot {
        case inBar(x: CGFloat)          // lewa krawędź wcięcia w pasku menu
        case noRoom                     // brak miejsca – pokazujemy pod paskiem
    }

    /// Miejsce dla wcięcia o szerokości `width`: na środku, a gdy menu sięga środka – najbliżej środka.
    func slot(width: CGFloat) -> Slot {
        let margin: CGFloat = 8
        let center = screen.frame.midX
        let left = (menusRight ?? -.greatestFiniteMagnitude) + margin
        let right = (statusLeft ?? .greatestFiniteMagnitude) - margin
        let centered = center - width / 2
        if centered >= left && centered + width <= right { return .inBar(x: centered) }
        guard right - left >= width else { return .noRoom }
        return .inBar(x: max(left, min(centered, right - width)))
    }
}

enum Placement {

    static func builtInScreen() -> (NSScreen, CGDirectDisplayID)? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            if CGDisplayIsBuiltin(id) != 0 { return (screen, id) }
        }
        return nil
    }

    static func current() -> MenuBarInfo? {
        guard let found = builtInScreen() else { return nil }
        let screen = found.0
        let id = found.1
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        // Wstępnie: obszar zarezerwowany na pasek. Niżej zastępujemy go rzeczywistą wysokością
        // okna paska menu – w trybie pełnoekranowym pasek jest niższy.
        var height = reserved > 10 ? reserved : NSStatusBar.system.thickness

        // Współrzędne CoreGraphics/Dostępności mają początek w lewym górnym rogu ekranu głównego.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let topCG = primaryHeight - screen.frame.maxY
        let barRange = (topCG - 2)...(topCG + height + 2)

        // Najpierw tylko okna widoczne (szybko); pełną listę bierzemy tylko, gdy paska nie widać.
        var windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)

        var menuBarKnown = false
        var menuBarOnScreen = false
        var statusLeft: CGFloat?

        for w in windows {
            guard let layer = w[kCGWindowLayer as String] as? Int,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let onScreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
            let pid = (w[kCGWindowOwnerPID as String] as? Int) ?? 0
            let onThisScreen = bounds.midX >= screen.frame.minX && bounds.midX <= screen.frame.maxX
                && barRange.contains(bounds.minY)

            if layer == mainMenuLevel, bounds.width > 200 {
                menuBarKnown = true
                if onScreen && onThisScreen {
                    menuBarOnScreen = true
                    if bounds.height >= 16 && bounds.height <= 40 { height = bounds.height }
                }
            }
            if layer == statusLevel, onScreen, onThisScreen, pid != ownPID,
               bounds.height <= height + 4, bounds.width < 300 {
                statusLeft = min(statusLeft ?? bounds.minX, bounds.minX)
            }
        }

        if !menuBarOnScreen {
            // Pasek schowany (np. tryb pełnoekranowy)? Sprawdzamy, czy w ogóle istnieje okno paska.
            windows = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
            menuBarKnown = windows.contains { w in
                (w[kCGWindowLayer as String] as? Int) == mainMenuLevel
                    && ((w[kCGWindowBounds as String] as? NSDictionary)
                        .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }?.width ?? 0) > 200
            }
        }

        return MenuBarInfo(screen: screen, displayID: id, height: height,
                           visible: menuBarKnown ? menuBarOnScreen : true,
                           menusRight: appMenusRight(screen: screen, topCG: topCG, height: height),
                           statusLeft: statusLeft)
    }

    /// Prawa krawędź ostatniego menu aktywnego programu (np. „Pomoc” w Pages).
    private static func appMenusRight(screen: NSScreen, topCG: CGFloat, height: CGFloat) -> CGFloat? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &barRef) == .success,
              let barRef, CFGetTypeID(barRef) == AXUIElementGetTypeID()
        else { return nil }
        let bar = barRef as! AXUIElement

        var kidsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &kidsRef) == .success,
              let items = kidsRef as? [AXUIElement]
        else { return nil }

        var right: CGFloat?
        for item in items {
            guard let frame = frame(of: item), frame.width > 0,
                  frame.minY >= topCG - 2, frame.minY <= topCG + height,
                  frame.midX >= screen.frame.minX, frame.midX <= screen.frame.maxX
            else { continue }
            right = max(right ?? frame.maxX, frame.maxX)
        }
        return right
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func describe(_ info: MenuBarInfo?) -> String {
        guard let info else { return "brak wbudowanego ekranu" }
        return "ekran \(Int(info.screen.frame.width))×\(Int(info.screen.frame.height)), pasek \(Int(info.height)) pkt, "
            + "widoczny=\(info.visible), koniec menu=\(info.menusRight.map { String(Int($0)) } ?? "?"), "
            + "początek ikon=\(info.statusLeft.map { String(Int($0)) } ?? "?")"
    }
}
