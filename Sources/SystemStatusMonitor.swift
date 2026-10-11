// SystemStatusMonitor.swift – tryb Skupienia, nagrywanie ekranu, podłączane ekrany (rzutnik, AirPlay)
//
// macOS nie udostępnia publicznie nazwy włączonego Skupienia. Odczytujemy ją (dzięki uprawnieniu
// Dostępności) z ikon Centrum sterowania na pasku menu – tak jak robi to VoiceOver.

import Cocoa
import ApplicationServices

final class SystemStatusMonitor {

    /// Zmiana Skupienia: nazwa włączonego trybu albo nil, gdy wyłączone.
    var onFocus: ((String?) -> Void)?
    /// Stan Skupienia (także początkowy, bez powiadomienia) – do wyciszania mniej ważnych kart.
    var onFocusState: ((Bool) -> Void)?
    var onRecording: ((Bool) -> Void)?
    /// Ekran podłączony (true) lub odłączony (false) – nazwa ekranu.
    var onDisplay: ((String, Bool) -> Void)?

    private var timer: Timer?
    private var focusKnown = false
    private var focus: String?
    private var recording = false
    private var loggedExtras = false
    private var displays: Set<String> = []

    init() {
        displays = Self.externalDisplays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.checkDisplays()
        }
    }

    /// Sprawdza co 3 s (w trybie niskiego zużycia energii co 8 s).
    func start() {
        pause()
        check()
        let interval: TimeInterval = Prefs.lowPower ? 8 : 3
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = interval * 0.3
        timer = t
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Ekrany

    private static func externalDisplays() -> Set<String> {
        var names: Set<String> = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) == 0 else { continue }
            names.insert(screen.localizedName)
        }
        return names
    }

    private func checkDisplays() {
        let now = Self.externalDisplays()
        for name in now.subtracting(displays) { onDisplay?(name, true) }
        for name in displays.subtracting(now) { onDisplay?(name, false) }
        displays = now
    }

    // MARK: - Skupienie i nagrywanie

    private func check() {
        let rec = screenCaptureActive() || extrasState().recording
        let f = extrasState().focus
        if rec != recording {
            recording = rec
            onRecording?(rec)
        }
        if !focusKnown {
            focusKnown = true
            focus = f
            onFocusState?(f != nil)
        } else if f != focus {
            focus = f
            onFocusState?(f != nil)
            onFocus?(f)
        }
    }

    /// Nagrywanie narzędziem Zrzut ekranu (⌘⇧5): na pasku menu pojawia się przycisk „Zatrzymaj”.
    private func screenCaptureActive() -> Bool {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        return list.contains { w in
            (w[kCGWindowOwnerName as String] as? String) == "screencaptureui"
                && (w[kCGWindowLayer as String] as? Int) == statusLevel
        }
    }

    private var cachedExtras: (focus: String?, recording: Bool, at: Date) = (nil, false, .distantPast)

    private func extrasState() -> (focus: String?, recording: Bool) {
        if Date().timeIntervalSince(cachedExtras.at) < 1 { return (cachedExtras.focus, cachedExtras.recording) }
        var focusName: String?
        var rec = false
        defer { cachedExtras = (focusName, rec, Date()) }

        guard AXIsProcessTrusted(),
              let cc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first
        else { return (nil, false) }
        let app = AXUIElementCreateApplication(cc.processIdentifier)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &barRef) == .success,
              let barRef, CFGetTypeID(barRef) == AXUIElementGetTypeID()
        else { return (nil, false) }
        let bar = barRef as! AXUIElement
        var kidsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &kidsRef) == .success,
              let items = kidsRef as? [AXUIElement]
        else { return (nil, false) }

        var described: [String] = []
        for item in items {
            let id = Self.string(item, "AXIdentifier") ?? ""
            let desc = Self.string(item, kAXDescriptionAttribute) ?? ""
            let title = Self.string(item, kAXTitleAttribute) ?? ""
            described.append("\(id) „\(desc)”")
            let lowID = id.lowercased()
            let lowDesc = desc.lowercased()
            if lowID.contains("focus") || lowID.contains("donotdisturb") {
                let name = title.isEmpty ? desc : title
                focusName = Self.cleanFocusName(name)
            }
            if lowID.contains("screenrecording") || lowID.contains("screencapture")
                || lowDesc.contains("nagrywanie ekranu") || lowDesc.contains("screen recording") {
                rec = true
            }
        }
        if !loggedExtras {
            loggedExtras = true
            Log.write("Centrum sterowania – ikony: \(described.joined(separator: ", "))")
        }
        return (focusName, rec)
    }

    /// „Skupienie: Praca” → „Praca”; ogólne nazwy → „Skupienie”.
    private static func cleanFocusName(_ raw: String) -> String {
        var name = raw
        for prefix in ["Skupienie:", "Focus:", "Tryb skupienia:"] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        name = name.trimmingCharacters(in: .whitespaces)
        let generic = ["", "skupienie", "focus", "tryb skupienia", "focus mode"]
        return generic.contains(name.lowercased()) ? "" : name
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
