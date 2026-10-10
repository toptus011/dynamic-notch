// AppDelegate.swift – start programu: źródła danych → model → okno wcięcia

import Cocoa
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let controller = NotchController()
    private let settings = SettingsWindowController()
    private var audio: AudioMonitor?
    private var brightness: BrightnessMonitor?
    private var music: MusicMonitor?
    private var devices: DeviceMonitor?
    private var power: PowerMonitor?
    private var calendar: CalendarMonitor?
    private var privacy: PrivacyMonitor?
    private var hotKey: HotKey?
    private var clockTimer: Timer?
    private let startedAt = Date()

    /// Nazwa pliku z opisem agenta w pakiecie (Contents/Library/LaunchAgents)
    static let agentPlist = "pl.bulka.dynamicnotch.agent.plist"
    static let openSettingsNote = Notification.Name("pl.bulka.dynamicnotch.openSettings")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tylko jedna kopia programu (np. agent w tle + ręczne uruchomienie z Aplikacji)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            Log.write("Dynamic Notch już działa – otwieram jego Ustawienia i kończę tę kopię")
            DistributedNotificationCenter.default().postNotificationName(
                Self.openSettingsNote, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        // Druga kopia (np. kliknięcie w Launchpadzie) prosi działającą o pokazanie Ustawień.
        DistributedNotificationCenter.default().addObserver(forName: Self.openSettingsNote, object: nil,
                                                            queue: .main) { [weak self] _ in
            self?.openSettings()
        }

        Prefs.registerDefaults()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Log.write("Start Dynamic Notch \(version) z \(Bundle.main.bundlePath); Dostępność(AX)=\(AXIsProcessTrusted())")
        buildMainMenu()

        let model = controller.model

        // Okno i czynności
        controller.start(actions: NotchActions(
            toggle: {}, collapse: {}, hover: { _ in },
            playPause: { [weak self] in self?.music?.playPause() },
            next: { [weak self] in self?.music?.next() },
            previous: { [weak self] in self?.music?.previous() },
            setVolume: { [weak self] value in
                self?.audio?.setVolume(value)
                model.volume = value
            },
            setBrightness: { [weak self] value in
                self?.brightness?.setBrightness(value)
                model.brightness = value
            },
            settings: { [weak self] in self?.openSettings() },
            log: { AppDelegate.openLog() },
            quit: { NSApp.terminate(nil) },
            openPlayer: { [weak self] in
                self?.controller.setExpanded(false)
                self?.music?.openPlayer()
            },
            seek: { [weak self] seconds in self?.music?.seek(to: seconds) },
            openURL: { [weak self] url in
                self?.controller.setExpanded(false)
                model.alert = nil
                NSWorkspace.shared.open(url)
                Log.write("Otwieram link spotkania: \(url.host ?? "")")
            },
            completeReminder: { [weak self] id in self?.calendar?.complete(id) },
            openCalendar: { [weak self] in
                self?.controller.setExpanded(false)
                AppDelegate.openApp("com.apple.iCal")
            },
            openReminders: { [weak self] in
                self?.controller.setExpanded(false)
                AppDelegate.openApp("com.apple.reminders")
            }))
        controller.onExpand = { [weak self] on in
            self?.music?.trackPosition(on)
            // Jasność potrzebna tylko dla suwaka w panelu – odczyt tylko, gdy panel jest otwarty.
            if on {
                self?.calendar?.refresh()
                self?.brightness?.resume()
                model.brightness = self?.brightness?.brightness
            } else {
                self?.brightness?.pause()
            }
        }
        controller.onScreenAwake = { [weak self] awake in
            if awake {
                self?.privacy?.resume()
                self?.calendar?.refresh()
                model.clock = Date()
            } else {
                self?.brightness?.pause()
                self?.privacy?.pause()
            }
        }

        // Dźwięk
        let audio = AudioMonitor()
        model.volume = audio.volume
        model.muted = audio.muted
        // Głośność i jasność pokazuje sam macOS – wcięcie trzyma je tylko dla suwaków w panelu.
        audio.onChange = { value, muted in
            model.volume = value
            model.muted = muted
        }
        self.audio = audio

        // Jasność
        if let display = Placement.builtInScreen()?.1 {
            let monitor = BrightnessMonitor(display: display)
            model.brightness = monitor.brightness
            monitor.onChange = { value in model.brightness = value }
            monitor.pause()   // odczyt tylko przy otwartym panelu
            brightness = monitor
        }

        // Muzyka
        let music = MusicMonitor()
        music.onChange = { value in model.nowPlaying = value }
        self.music = music

        // Bluetooth – powiększona karta (4,5 s)
        let devices = DeviceMonitor()
        model.devices = devices.connected
        devices.onChange = { [weak devices] info, connected in
            model.devices = devices?.connected ?? []
            guard Prefs.on(Prefs.devices) else { return }
            model.showAlert(NotchAlert(symbol: info.symbol,
                                       tint: connected ? .systemBlue : .systemGray,
                                       title: info.name,
                                       subtitle: connected ? "Połączono z MacBookiem" : "Rozłączono",
                                       badge: connected ? "połączono" : "",
                                       badgeColor: .systemGreen),
                            duration: 4.5)
        }
        self.devices = devices

        // Zasilanie i bateria
        let power = PowerMonitor()
        model.batteryLevel = power.level
        model.charging = power.charging
        model.onAC = power.onAC
        power.onLevel = { level, charging, onAC in
            model.batteryLevel = level
            model.charging = charging
            model.onAC = onAC
        }
        power.onChange = { level, charging, onAC in
            guard Prefs.on(Prefs.power) else { return }
            model.show(.power(level: level, charging: charging, onAC: onAC))
        }
        power.onAlert = { alert in
            guard Prefs.on(Prefs.battery) else { return }
            switch alert {
            case .low(let level):
                model.showAlert(NotchAlert(symbol: "battery.25", tint: .systemOrange,
                                           title: "Niski poziom baterii",
                                           subtitle: "Zostało \(level)% · podłącz zasilacz"), duration: 6)
            case .critical(let level):
                model.showAlert(NotchAlert(symbol: "battery.0", tint: .systemRed,
                                           title: "Bateria prawie rozładowana",
                                           subtitle: "Zostało \(level)% · podłącz zasilacz teraz"), duration: 8)
            case .charged:
                model.showAlert(NotchAlert(symbol: "battery.100.bolt", tint: .systemGreen,
                                           title: "Naładowano",
                                           subtitle: "Bateria 100% · można odłączyć zasilacz"), duration: 5)
            }
        }
        self.power = power

        // Mikrofon i kamera
        let privacy = PrivacyMonitor()
        model.micInUse = privacy.micInUse
        model.cameraInUse = privacy.cameraInUse
        privacy.onChange = { mic, camera in
            let cameraStarted = camera && !model.cameraInUse
            let micStarted = mic && !model.micInUse
            model.micInUse = mic
            model.cameraInUse = camera
            // Tylko krótka informacja w chwili włączenia – stale pokazujemy to, co gra w tle.
            guard Prefs.on(Prefs.privacy) else { return }
            if cameraStarted {
                model.showAlert(NotchAlert(symbol: "video.fill", tint: .systemGreen,
                                           title: "Kamera włączona",
                                           subtitle: mic ? "Kamera i mikrofon w użyciu" : "Program korzysta z kamery"),
                                duration: 3.5)
            } else if micStarted {
                model.showAlert(NotchAlert(symbol: "mic.fill", tint: .systemOrange,
                                           title: "Mikrofon włączony",
                                           subtitle: "Program korzysta z mikrofonu"),
                                duration: 3.5)
            }
        }
        self.privacy = privacy

        // Kalendarz i Przypomnienia
        let calendar = CalendarMonitor()
        calendar.onEvents = { items in model.todayEvents = items }
        calendar.onReminders = { items in model.reminders = items }
        self.calendar = calendar
        calendar.refresh()
        let clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            model.clock = Date()
            self?.calendar?.refresh()
        }
        clock.tolerance = 5
        clockTimer = clock

        hotKey = HotKey { [weak self] in self?.controller.toggle() }

        enableBackgroundAgentOnce()

        if !AXIsProcessTrusted() {
            askForAccessibility()
        }
    }

    /// Przez pierwsze 2 s po starcie nie pokazujemy zdarzeń (system zgłasza wtedy stan początkowy).
    private var settled: Bool { Date().timeIntervalSince(startedAt) > 2 }

    /// Otwiera aplikację systemową (Kalendarz, Przypomnienia) po identyfikatorze.
    static func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        Log.write("Otwieram: \(bundleID)")
    }

    // MARK: - Praca w tle

    /// Przy pierwszym uruchomieniu rejestruje program jako agenta w tle: startuje przy logowaniu,
    /// a gdyby się zawiesił lub uległ awarii – macOS sam uruchomi go ponownie.
    private func enableBackgroundAgentOnce() {
        let key = "agentSkonfigurowany"
        let agent = SMAppService.agent(plistName: Self.agentPlist)
        guard !UserDefaults.standard.bool(forKey: key) else {
            Log.write("Praca w tle: \(Self.describe(agent.status))")
            return
        }
        UserDefaults.standard.set(true, forKey: key)
        // Zastępujemy wcześniejszy zwykły wpis „otwieraj przy logowaniu” (wersje 1.2.x)
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
        do {
            if agent.status != .enabled { try agent.register() }
            Log.write("Praca w tle włączona: \(Self.describe(agent.status))")
        } catch {
            Log.write("Praca w tle – błąd: \(error.localizedDescription)")
        }
        if agent.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "włączona"
        case .requiresApproval: return "czeka na zgodę w Ustawieniach systemowych"
        case .notRegistered: return "wyłączona"
        case .notFound: return "nie znaleziono (uruchom program z folderu Aplikacje)"
        @unknown default: return "nieznany stan"
        }
    }

    // MARK: - Okna i menu

    /// Ponowne uruchomienie programu (np. z Launchpada) otwiera Ustawienia.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    private func openSettings() {
        settings.show(openLog: { AppDelegate.openLog() },
                      placement: { [weak self] in self?.controller.placementDescription ?? "?" })
    }

    /// Menu programu (widoczne, gdy otwarte są Ustawienia): ⌘W zamyka okno, ⌘Q kończy program.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ustawienia…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Zakończ Dynamic Notch", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Okno")
        windowMenu.addItem(withTitle: "Zamknij", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc private func menuSettings() { openSettings() }

    static func openLog() {
        Log.write("Otwarto dziennik")
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([Log.fileURL], withApplicationAt: textEdit,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    private func askForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Dynamic Notch prosi o uprawnienie Dostępności"
        alert.informativeText = """
        Dzięki niemu wcięcie widzi, gdzie kończą się menu programu (np. Pages), i nigdy ich nie zasłania, \
        a panel otwiera się bez przełączania programów.

        W oknie „Dostępność” włącz przełącznik przy „Dynamic Notch”.
        """
        alert.addButton(withTitle: "Otwórz Ustawienia")
        alert.addButton(withTitle: "Później")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
