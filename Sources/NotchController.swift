// NotchController.swift – okno wcięcia: położenie przy pasku menu, rozwijanie, zwijanie

import Cocoa
import SwiftUI
import Combine

/// Okno bez ramki nad paskiem menu. Nie aktywuje programu (Pages zostaje na wierzchu).
final class NotchPanel: NSPanel {
    init(initialFrame: NSRect) {
        super.init(contentRect: initialFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        // Bez .fullScreenAuxiliary: w trybie pełnoekranowym (i podczas pokazu Keynote) wcięcia nie ma,
        // chyba że wysunie się pasek menu.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// Wcięcie może na chwilę wyjechać nad ekran (wsuwanie razem z paskiem menu) – nie poprawiamy położenia.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Widok, który reaguje na pierwsze kliknięcie, mimo że okno nie jest aktywne.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchController {

    let model = NotchModel()
    let panel = NotchPanel(initialFrame: NSRect(x: 0, y: 0, width: 72, height: 24))

    var onExpand: ((Bool) -> Void)?
    /// Wywoływane przy uśpieniu (false) i wybudzeniu (true) ekranu.
    var onScreenAwake: ((Bool) -> Void)?

    /// Margines wokół kształtu, w którym kursor już „jest nad wcięciem”.
    static let hoverMargin: CGFloat = 6

    private var info: MenuBarInfo?
    private var cancellables: Set<AnyCancellable> = []
    private var placementTimer: Timer?
    private var placementInterval: TimeInterval = 0
    private var hoverWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var lastLoggedPlacement = ""
    private var screenAsleep = false
    /// Kursor nad wcięciem – w trybie pełnoekranowym macOS chowa wtedy pasek menu,
    /// ale wcięcie (i rozwinięty panel) musi zostać, żeby dało się w nim klikać.
    private var mouseInside = false

    // Pasek menu chowany (tryb pełnoekranowy lub „Automatycznie ukrywaj pasek menu”):
    // co klatkę (60 razy na s) sprawdzamy, czy pasek się wysuwa, i przesuwamy wcięcie razem z nim.
    private var autoHideBar = false
    private var slideTimer: Timer?
    private var barShown = false
    /// O ile punktów pasek menu jest jeszcze schowany nad ekranem (0 – w pełni wysunięty).
    private var slideOffset: CGFloat = 0
    private var followedMotion = false
    /// Schowaliśmy wcięcie od razu, gdy kursor zjechał z paska (system zaraz schowa pasek).
    private var predictedHide = false
    /// Pasek był naprawdę schowany (potwierdzone) – dopiero wtedy chowamy wcięcie „z wyprzedzeniem”.
    private var predictedHideAt = Date.distantPast
    /// Chwila, gdy kursor zjechał z paska menu (od niej liczymy czas do schowania paska).
    private var leftBarAt: Date?
    private var visibleFarSince: Date?
    private var predictionFailed = false
    private var menuOpenCheckedAt = Date.distantPast
    private var menuOpenCached = false
    /// Kolejne sprawdzenia: pasek niewidoczny / widoczny mimo kursora daleko od góry.
    private var hiddenChecks = 0
    private var shownChecks = 0
    private var menuBarWindowIDs: [CGWindowID] = []
    private var lastScan = Date.distantPast

    var actions = NotchActions(toggle: {}, collapse: {}, hover: { _ in }, playPause: {}, next: {}, previous: {},
                               setVolume: { _ in }, setBrightness: { _ in }, settings: {}, log: {}, quit: {},
                               openPlayer: {}, seek: { _ in }, openURL: { _ in }, completeReminder: { _ in },
                               openCalendar: {}, openReminders: {}, openEvent: { _ in }, openReminder: { _ in })

    func start(actions custom: NotchActions) {
        actions = custom
        actions.toggle = { [weak self] in self?.setExpanded(!(self?.model.expanded ?? false)) }
        actions.collapse = { [weak self] in self?.setExpanded(false) }
        actions.hover = { [weak self] inside in self?.hover(inside) }

        let root = NotchRootView(model: model, actions: actions)
        let hosting = FirstClickHostingView(rootView: root)
        // Rozmiar okna ustala kontroler – widok nie może go narzucać.
        hosting.sizingOptions = []
        panel.contentView = hosting
        startMouseTracking()

        // Każda zmiana stanu → nowy rozmiar i położenie okna
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
            [weak self] _ in self?.refreshPlacement(systemChange: true)
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) {
            [weak self] _ in self?.refreshPlacement(systemChange: true)
        }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) {
            [weak self] _ in self?.setScreenAsleep(true)
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) {
            [weak self] _ in self?.setScreenAsleep(false)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.refreshPlacement() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.updateAppearance()
        }

        updateAppearance()
        refreshPlacement()
    }

    // MARK: - Uśpienie ekranu – wstrzymujemy wszystko, co działa cyklicznie

    private func setScreenAsleep(_ asleep: Bool) {
        screenAsleep = asleep
        Log.write(asleep ? "Ekran uśpiony – wstrzymuję odświeżanie" : "Ekran wybudzony – wznawiam")
        if asleep {
            placementTimer?.invalidate()
            placementTimer = nil
            placementInterval = 0
            stopSlideTracking()
            setExpanded(false)
        } else {
            refreshPlacement()
        }
        onScreenAwake?(!asleep)
    }

    /// Co 0,4 s, gdy pasek menu jest schowany lub wysuwany (tryb pełnoekranowy),
    /// w pozostałych sytuacjach co 1,5 s – zmiany programu wychwytujemy od razu z powiadomień.
    private func schedulePlacement(fast: Bool) {
        guard !screenAsleep else { return }
        let interval: TimeInterval = fast ? 0.4 : 1.5
        guard interval != placementInterval else { return }
        placementTimer?.invalidate()
        placementInterval = interval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshPlacement()
        }
        timer.tolerance = interval * 0.2
        placementTimer = timer
    }

    // MARK: - Rozwijanie i zwijanie

    func setExpanded(_ on: Bool) {
        hoverWork?.cancel()
        collapseWork?.cancel()
        guard model.expanded != on else { return }
        if on {
            model.activity = nil
            model.alert = nil
        }
        model.expanded = on
        onExpand?(on)
        Log.write(on ? "Panel rozwinięty" : "Panel zwinięty")

        if on {
            // Delikatne „kliknięcie” gładzika Force Touch – jak w elementach systemu
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            panel.makeKey()
            // Kliknięcie gdziekolwiek poza wcięciem (np. w menu programu) zwija panel.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] _ in self?.setExpanded(false)
            }
            // Klawiatura w panelu: Esc – zwiń, ⌘1…⌘4 – zakładki
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKey(event) == true ? nil : event
            }
        } else {
            panel.makeFirstResponder(nil)
            if let monitor = outsideClickMonitor {
                NSEvent.removeMonitor(monitor)
                outsideClickMonitor = nil
            }
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    func toggle() { setExpanded(!model.expanded) }

    /// Skróty w rozwiniętym panelu. Zwraca true, gdy klawisz został obsłużony.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard model.expanded, event.window === panel else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 {                                   // Esc
            if panel.firstResponder is NSText, !model.newTodoText.isEmpty {
                model.newTodoText = ""                             // najpierw czyści pole zadania
            } else {
                setExpanded(false)
            }
            return true
        }
        if flags == .command, let chars = event.charactersIgnoringModifiers,
           let digit = Int(chars), (1...4).contains(digit) {
            model.panelTab = digit - 1
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            setExpanded(false)
            return true
        }
        return false
    }

    private func hover(_ inside: Bool) {
        mouseInside = inside
        if model.hovering != inside { model.hovering = inside }
        hoverWork?.cancel()
        collapseWork?.cancel()
        if inside {
            // Otwieranie najechaniem tylko, gdy wybrano je w Ustawieniach – i z opóźnieniem 0,5 s,
            // żeby przypadkowy ruch do menu nie rozwijał panelu.
            guard Prefs.opensOnHover, !model.expanded else { return }
            let work = DispatchWorkItem { [weak self] in self?.setExpanded(true) }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        } else if model.expanded && !(panel.firstResponder is NSText) {
            // Gdy wpisujesz zadanie (pole tekstowe aktywne), panel nie zwija się po odsunięciu kursora.
            let work = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    // MARK: - Położenie

    private func updateAppearance() {
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        if model.darkMenuBar != dark { model.darkMenuBar = dark }
    }

    func refreshPlacement(systemChange: Bool = false) {
        guard !screenAsleep else { return }
        info = Placement.current()
        if let info, model.barHeight != info.height { model.barHeight = info.height }
        let text = Placement.describe(info)
        if text != lastLoggedPlacement {
            lastLoggedPlacement = text
            Log.write("Pasek menu: \(text)")
        }
        // Tryb „pasek chowany” włączamy dopiero, gdy pasek dwa razy z rzędu jest schowany,
        // a wyłączamy, gdy dwa razy z rzędu jest widoczny, choć kursor jest daleko od góry.
        // Dzięki temu na zwykłym biurku wcięcie nigdy samo się nie chowa.
        let visible = info?.visible ?? true
        if !visible {
            hiddenChecks += 1
            shownChecks = 0
        } else if !mouseNearTop() && !menuOpen() {
            shownChecks += 1
            hiddenChecks = 0
        }
        if !autoHideBar && hiddenChecks >= 2 {
            startSlideTracking()
        } else if autoHideBar && shownChecks >= 3 {
            stopSlideTracking()
            Log.write("Pasek menu jest stale widoczny – wcięcie zawsze na miejscu")
        }
        if systemChange {
            // Przejście między pełnym ekranem a zwykłym oknem trwa ok. 0,7 s – sprawdzamy jeszcze raz po nim.
            for delay in [0.35, 0.9] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshPlacement() }
            }
        }
        // Szybsze sprawdzanie, dopóki nie wiadomo, czy pasek jest chowany.
        schedulePlacement(fast: !visible && !autoHideBar)
        layout()
    }

    // MARK: - Wysuwanie razem z paskiem menu (tryb pełnoekranowy)

    private func startSlideTracking() {
        autoHideBar = true
        hiddenChecks = 0
        shownChecks = 0
        barShown = false
        predictedHide = false
        leftBarAt = nil
        visibleFarSince = nil
        predictionFailed = false
        slideOffset = 0
        menuBarWindowIDs = []
        Log.write("Pasek menu chowany – wcięcie wysuwa się razem z nim")
        slideTimer?.invalidate()
        // 60 razy na sekundę (w trybie niskiego zużycia energii – 30)
        let timer = Timer(timeInterval: Prefs.lowPower ? 1.0 / 30.0 : 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.slideTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        slideTimer = timer
    }

    private func stopSlideTracking() {
        slideTimer?.invalidate()
        slideTimer = nil
        guard autoHideBar else { return }
        autoHideBar = false
        hiddenChecks = 0
        shownChecks = 0
        barShown = false
        slideOffset = 0
        Log.write("Pasek menu stały")
    }

    /// Kursor przy górnej krawędzi wbudowanego ekranu (tam, gdzie macOS wysuwa pasek menu).
    private func mouseNearTop() -> Bool {
        guard let info else { return false }
        let mouse = NSEvent.mouseLocation
        let frame = info.screen.frame
        return mouse.x >= frame.minX && mouse.x <= frame.maxX
            && mouse.y >= frame.maxY - info.height - 50 && mouse.y <= frame.maxY + 1
    }

    private var pinned: Bool { model.expanded || mouseInside }

    /// Kursor w samym pasku menu (tam, gdzie macOS go wysuwa i trzyma).
    private func mouseInBar(_ info: MenuBarInfo) -> Bool {
        let mouse = NSEvent.mouseLocation
        let frame = info.screen.frame
        return mouse.x >= frame.minX && mouse.x <= frame.maxX && mouse.y >= frame.maxY - info.height - 1
    }

    /// Czy jest otwarte jakieś menu (wtedy macOS nie chowa paska, choć kursor jest niżej).
    private func menuOpen() -> Bool {
        let popUp = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        return list.contains { ($0[kCGWindowLayer as String] as? Int) == popUp }
    }

    private func slideTick() {
        guard let info, autoHideBar else { return }
        let now = Date()
        // Pasek schowany, kursor daleko od góry – nic do roboty.
        guard barShown || predictedHide || mouseNearTop() else { return }

        var state = menuBarState(info)
        let inBar = mouseInBar(info)

        // Odliczanie od chwili, gdy kursor zjechał z paska (macOS chowa pasek z opóźnieniem).
        if barShown {
            if inBar || pinned || cachedMenuOpen(now) {
                leftBarAt = nil
                visibleFarSince = nil
            } else {
                if leftBarAt == nil { leftBarAt = now }
                // Pasek wciąż widoczny długo po zjechaniu kursora – to już zwykły, stały pasek
                // (np. program wyszedł z pełnego ekranu).
                if state != nil && !mouseNearTop() {
                    if visibleFarSince == nil { visibleFarSince = now }
                    if now.timeIntervalSince(visibleFarSince!) > 2.5 { barBecamePermanent(); return }
                } else {
                    visibleFarSince = nil
                }
            }
        }

        // Chowamy wcięcie z wyprzedzeniem, tak aby skończyło się chować razem z paskiem.
        // Czas chowania paska program sam mierzy (zapisany w ustawieniach) – dopasowuje się do systemu.
        if barShown, let t0 = leftBarAt, let delay = learnedHideDelay, !predictionFailed,
           now.timeIntervalSince(t0) >= max(0, delay - Self.slideDuration) {
            barShown = false
            predictedHide = true
            predictedHideAt = now
            slideOffset = 0
            animateSlide(in: false)
            return
        }

        if predictedHide {
            if state == nil {
                predictedHide = false
                learnHideDelay(now)
            } else if inBar {
                predictedHide = false
                leftBarAt = nil
            } else if now.timeIntervalSince(predictedHideAt) > 1.0 {
                // Przewidywanie się nie sprawdziło – pasek dalej widać. Wcięcie wraca;
                // do czasu prawdziwego schowania paska nie zgadujemy.
                predictedHide = false
                predictionFailed = true
            } else {
                state = nil   // pasek właśnie się chowa – nie pokazujemy wcięcia ponownie
            }
            if predictedHide { return }
        }

        if let offset = state {
            let newOffset = pinned ? 0 : offset
            if !barShown {
                barShown = true
                leftBarAt = nil
                visibleFarSince = nil
                slideOffset = newOffset
                followedMotion = offset > 1
                layout()
                // Jeśli system nie przesuwa okna paska (tylko je pokazuje), wsuwamy wcięcie sami – tak samo szybko.
                if !followedMotion && !pinned { animateSlide(in: true) }
            } else if abs(newOffset - slideOffset) >= 0.5 {
                if newOffset > 1 { followedMotion = true }
                slideOffset = newOffset
                layout()
            }
        } else if barShown {
            // Pasek schował się (zanim zdążyliśmy przewidzieć) – mierzymy, ile to trwało.
            learnHideDelay(now)
            predictionFailed = false
            barShown = false
            slideOffset = 0
            if !pinned { animateSlide(in: false) }
        }
    }

    static let slideDuration: TimeInterval = 0.2

    /// Zmierzony czas od zjechania kursora z paska do schowania paska (średnia krocząca).
    private var learnedHideDelay: TimeInterval? {
        get {
            let v = UserDefaults.standard.double(forKey: "czasChowaniaPaska")
            return v > 0 ? v : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: "czasChowaniaPaska") }
    }

    private func learnHideDelay(_ now: Date) {
        guard let t0 = leftBarAt else { return }
        leftBarAt = nil
        let sample = now.timeIntervalSince(t0)
        guard sample > 0.05 && sample < 4 else { return }
        let value = learnedHideDelay.map { $0 * 0.6 + sample * 0.4 } ?? sample
        learnedHideDelay = value
        Log.write(String(format: "Pasek menu chowa się po %.2f s – wcięcie dopasowane (%.2f s)", sample, value))
    }

    private func cachedMenuOpen(_ now: Date) -> Bool {
        if now.timeIntervalSince(menuOpenCheckedAt) > 0.1 {
            menuOpenCheckedAt = now
            menuOpenCached = menuOpen()
        }
        return menuOpenCached
    }

    /// Pasek menu okazał się stale widoczny – kończymy śledzenie i od razu pokazujemy wcięcie.
    private func barBecamePermanent() {
        stopSlideTracking()
        predictedHide = false
        Log.write("Pasek menu znów stały (wyjście z pełnego ekranu) – wcięcie wraca")
        panel.alphaValue = 1
        refreshPlacement()
    }

    /// Ile punktów pasek menu jest nad ekranem; nil – pasek schowany.
    private func menuBarState(_ info: MenuBarInfo) -> CGFloat? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? info.screen.frame.height
        let topCG = primaryHeight - info.screen.frame.maxY
        let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let frame = info.screen.frame

        func check(_ list: [[String: Any]], collect: Bool) -> CGFloat? {
            var best: CGFloat?
            var ids: [CGWindowID] = []
            for w in list {
                guard (w[kCGWindowLayer as String] as? Int) == mainMenuLevel,
                      let dict = w[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                      bounds.width > 200, bounds.midX >= frame.minX, bounds.midX <= frame.maxX
                else { continue }
                if collect, let number = w[kCGWindowNumber as String] as? Int { ids.append(CGWindowID(number)) }
                guard (w[kCGWindowIsOnscreen as String] as? Bool) ?? false,
                      bounds.maxY > topCG + 1, bounds.minY < topCG + 60
                else { continue }
                let offset = min(max(topCG - bounds.minY, 0), bounds.height)
                best = min(best ?? offset, offset)
            }
            if collect { menuBarWindowIDs = ids; lastScan = Date() }
            return best
        }

        // Szybko: tylko znane okna paska menu.
        if !menuBarWindowIDs.isEmpty {
            var list: [[String: Any]] = []
            for id in menuBarWindowIDs {
                if let one = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] {
                    list.append(contentsOf: one)
                }
            }
            if let offset = check(list, collect: false) { return offset }
        }
        // Okno paska mogło powstać od nowa – przeglądamy okna na ekranie (najwyżej 20 razy na sekundę).
        guard Date().timeIntervalSince(lastScan) > 0.05 || menuBarWindowIDs.isEmpty else { return nil }
        let all = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        return check(all, collect: true)
    }

    private var slideAnimating = false

    /// Wsunięcie / wysunięcie wcięcia w tym samym tempie co pasek menu (ok. 0,2 s).
    /// Okno przesuwa się o wysokość samego kształtu (nie całego okna), więc ruch ma właściwe tempo.
    private func animateSlide(in show: Bool) {
        let target = panel.frame
        let distance = model.size(for: model.mode).height + model.shapeOffset.height + 6
        let hidden = target.offsetBy(dx: 0, dy: distance)
        slideAnimating = true
        if show {
            panel.setFrame(hidden, display: false)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }, completionHandler: { [weak self] in
                self?.slideAnimating = false
                self?.layout()
            })
        } else {
            guard panel.isVisible else { slideAnimating = false; return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Self.slideDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(hidden, display: true)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.slideAnimating = false
                guard !self.barShown, !self.pinned else { self.layout(); return }
                self.hidePanel()
                self.layout()
            })
        }
    }

    var placementDescription: String { Placement.describe(info) }

    /// Wysokość okna: mieści największy stan (panel z rozwiniętą listą urządzeń), kapsułkę pod paskiem i cień.
    static let windowHeight: CGFloat = 520

    /// Okno ma stały rozmiar (szerokość ekranu × 520 pkt) i nie zmienia go przy rozwijaniu –
    /// całą animację (od góry do dołu) wykonuje SwiftUI wewnątrz, płynnie i bez przeskoków.
    /// Poza kształtem wcięcia okno przepuszcza kliknięcia do paska menu i programów.
    private func layout() {
        // Na zwykłym biurku wcięcie jest zawsze; chowa się tylko razem z chowanym paskiem menu.
        let barVisible = autoHideBar ? barShown : ((info?.visible ?? false) || hiddenChecks < 2)
        guard let info, barVisible || model.expanded || mouseInside else {
            if model.expanded { setExpanded(false) }
            hidePanel()
            return
        }
        let mode = model.mode
        let size = model.size(for: mode)
        let notchWidth = size.width + 2 * model.ear
        let screen = info.screen.frame
        let margin = Self.hoverMargin

        let centerX: CGFloat
        var offsetY: CGFloat = 0
        var dropped = false
        switch info.slot(width: notchWidth) {
        case .inBar(let left):
            centerX = left + notchWidth / 2
        case .noRoom:
            // Brak miejsca w pasku: spoczynek – nic nie pokazujemy; zdarzenia – kapsułka pod paskiem.
            if mode == .idle {
                hidePanel()
                return
            }
            dropped = true
            centerX = screen.midX
            offsetY = info.height + 6
        }
        if model.dropped != dropped { model.dropped = dropped }
        // Położenie kształtu w oknie – zmiana przesuwa wcięcie płynnie (animacja SwiftUI).
        let offset = CGSize(width: (centerX - screen.midX).rounded(), height: offsetY)
        if model.shapeOffset != offset { model.shapeOffset = offset }

        let slide = (autoHideBar && !pinned) ? slideOffset : 0
        let frame = NSRect(x: screen.minX, y: screen.maxY - Self.windowHeight + slide,
                           width: screen.width, height: Self.windowHeight)
        if !slideAnimating && panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        // Obszar, w którym okno reaguje na kursor: kształt wcięcia + mały margines.
        hitRect = NSRect(x: centerX - notchWidth / 2 - margin,
                         y: screen.maxY - offsetY - size.height - margin + slide,
                         width: notchWidth + 2 * margin,
                         height: size.height + margin + 2)   // +2: kursor na samej górnej krawędzi ekranu
        if !panel.isVisible { panel.orderFrontRegardless() }
        updateMouse()
    }

    private func hidePanel() {
        if panel.isVisible { panel.orderOut(nil) }
        hitRect = .zero
        updateMouse()
    }

    // MARK: - Kursor: przepuszczanie kliknięć poza wcięciem i najechanie

    private var hitRect: NSRect = .zero
    private var mouseMonitors: [Any] = []

    private func startMouseTracking() {
        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { [weak self] _ in
            self?.updateMouse()
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { [weak self] event in
            self?.updateMouse()
            return event
        }) {
            mouseMonitors.append(local)
        }
        panel.ignoresMouseEvents = true
    }

    /// Kursor nad wcięciem → okno przyjmuje kliknięcia; poza nim → kliknięcia trafiają do paska menu.
    private func updateMouse() {
        let inside = panel.isVisible && hitRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside != mouseInside { hover(inside) }
    }
}
