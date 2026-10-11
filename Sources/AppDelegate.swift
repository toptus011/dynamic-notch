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
    private var screenshots: ScreenshotMonitor?
    private var systemStatus: SystemStatusMonitor?
    private var hotKey: HotKey?
    private var clockTimer: Timer?

    /// Nazwa pliku z opisem agenta w pakiecie (Contents/Library/LaunchAgents)
    static let agentPlist = "pl.bulka.dynamicnotch.agent.plist"
    static let openSettingsNote = Notification.Name("pl.bulka.dynamicnotch.openSettings")

    private var model: NotchModel { controller.model }

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
        Log.write("Start Dynamic Notch \(version) z \(Bundle.main.bundlePath); Dostępność(AX)=\(AXIsProcessTrusted()); "
                  + "język: \(Lang.polish ? "polski" : "angielski")")
        buildMainMenu()

        startWindow()
        startSystemMonitors()
        startCalendar()
        setUpEverydayTools()

        hotKey = HotKey { [weak self] in self?.controller.toggle() }
        enableBackgroundAgentOnce()
        SystemNotifier.requestAuthorization()

        // Tryb niskiego zużycia energii – monitory przechodzą na rzadsze sprawdzanie.
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil,
                                               queue: .main) { [weak self] _ in
            Log.write("Tryb niskiego zużycia energii: \(Prefs.lowPower ? "włączony" : "wyłączony")")
            ClipboardMonitor.shared.start()
            self?.systemStatus?.start()
        }

        // Aktualizacje: pierwsze sprawdzenie po minucie od startu, potem raz dziennie.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self else { return }
            UpdateChecker.checkIfDue(self.model)
        }

        if !AXIsProcessTrusted() {
            askForAccessibility()
        }
    }

    // MARK: - Okno wcięcia i czynności

    private func startWindow() {
        let model = self.model
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
                Log.write("Otwieram link: \(url.host ?? "")")
            },
            completeReminder: { [weak self] id in self?.calendar?.complete(id) },
            openCalendar: { [weak self] in
                self?.controller.setExpanded(false)
                AppDelegate.openApp("com.apple.iCal")
            },
            openReminders: { [weak self] in
                self?.controller.setExpanded(false)
                AppDelegate.openApp("com.apple.reminders")
            },
            openEvent: { [weak self] event in
                self?.controller.setExpanded(false)
                // Konkretne wydarzenie; gdyby się nie dało – sam Kalendarz.
                let id = event.itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.itemID
                AppDelegate.open("ical://ekevent/\(id)?method=show&options=more", orApp: "com.apple.iCal")
            },
            openReminder: { [weak self] id in
                self?.controller.setExpanded(false)
                let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
                AppDelegate.open("x-apple-reminderkit://REMCDReminder/\(encoded)", orApp: "com.apple.reminders")
            }))

        controller.onExpand = { [weak self] on in
            self?.music?.trackPosition(on)
            if on {
                model.wiredDevices = DeviceMonitor.wiredDevices()
                self?.calendar?.refresh()
                // Jasność potrzebna tylko dla suwaka w panelu – odczyt tylko, gdy panel jest otwarty.
                self?.brightness?.resume()
                model.brightness = self?.brightness?.brightness
            } else {
                self?.brightness?.pause()
            }
        }
        controller.onScreenAwake = { [weak self] awake in
            if awake {
                self?.privacy?.resume()
                self?.systemStatus?.start()
                ClipboardMonitor.shared.start()
                self?.calendar?.refresh()
                model.clock = Date()
            } else {
                self?.brightness?.pause()
                self?.privacy?.pause()
                self?.systemStatus?.pause()
                ClipboardMonitor.shared.stop()
            }
        }
    }

    // MARK: - Dźwięk, jasność, muzyka, Bluetooth, zasilanie, kamera i mikrofon

    private func startSystemMonitors() {
        let model = self.model

        // Głośność i jasność pokazuje sam macOS – wcięcie trzyma je tylko dla suwaków w panelu.
        let audio = AudioMonitor()
        model.volume = audio.volume
        model.muted = audio.muted
        audio.onChange = { value, muted in
            model.volume = value
            model.muted = muted
        }
        self.audio = audio

        if let display = Placement.builtInScreen()?.1 {
            let monitor = BrightnessMonitor(display: display)
            model.brightness = monitor.brightness
            monitor.onChange = { value in model.brightness = value }
            monitor.pause()   // odczyt tylko przy otwartym panelu
            brightness = monitor
        }

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
                                       tint: connected ? .controlAccentColor : .systemGray,
                                       title: info.name,
                                       subtitle: connected ? tr("Połączono z Makiem", "Connected to your Mac")
                                                           : tr("Rozłączono", "Disconnected"),
                                       badge: connected ? tr("połączono", "connected") : "",
                                       badgeColor: .systemGreen),
                            duration: 4.5)
        }
        self.devices = devices

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
                                           title: tr("Niski poziom baterii", "Low battery"),
                                           subtitle: tr("Zostało \(level)% · podłącz zasilacz",
                                                        "\(level)% left · connect power")),
                                duration: 6, priority: .important)
            case .critical(let level):
                model.showAlert(NotchAlert(symbol: "battery.0", tint: .systemRed,
                                           title: tr("Bateria prawie rozładowana", "Battery almost empty"),
                                           subtitle: tr("Zostało \(level)% · podłącz zasilacz teraz",
                                                        "\(level)% left · connect power now")),
                                duration: 8, priority: .important)
            case .charged:
                model.showAlert(NotchAlert(symbol: "battery.100.bolt", tint: .systemGreen,
                                           title: tr("Naładowano", "Fully charged"),
                                           subtitle: tr("Bateria 100% · można odłączyć zasilacz",
                                                        "Battery 100% · you can unplug")),
                                duration: 5)
            }
        }
        self.power = power

        // Kamera i mikrofon – tylko krótka informacja w chwili włączenia (ważna – także przy Skupieniu)
        let privacy = PrivacyMonitor()
        model.micInUse = privacy.micInUse
        model.cameraInUse = privacy.cameraInUse
        privacy.onChange = { mic, camera in
            let cameraStarted = camera && !model.cameraInUse
            let micStarted = mic && !model.micInUse
            model.micInUse = mic
            model.cameraInUse = camera
            guard Prefs.on(Prefs.privacy) else { return }
            if cameraStarted {
                model.showAlert(NotchAlert(symbol: "video.fill", tint: .systemGreen,
                                           title: tr("Kamera włączona", "Camera on"),
                                           subtitle: mic ? tr("Kamera i mikrofon w użyciu", "Camera and microphone in use")
                                                         : tr("Program korzysta z kamery", "An app is using the camera")),
                                duration: 3.5, priority: .important)
            } else if micStarted {
                model.showAlert(NotchAlert(symbol: "mic.fill", tint: .systemOrange,
                                           title: tr("Mikrofon włączony", "Microphone on"),
                                           subtitle: tr("Program korzysta z mikrofonu", "An app is using the microphone")),
                                duration: 3.5, priority: .important)
            }
        }
        self.privacy = privacy
    }

    // MARK: - Kalendarz i Przypomnienia

    private func startCalendar() {
        let model = self.model
        let calendar = CalendarMonitor()
        calendar.onEvents = { items in model.todayEvents = items }
        calendar.onReminders = { items in model.reminders = items }
        self.calendar = calendar
        calendar.refresh()
        let clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            model.clock = Date()
            self?.calendar?.refresh()
            UpdateChecker.checkIfDue(model)
        }
        clock.tolerance = 5
        clockTimer = clock
    }

    // MARK: - Na co dzień i praca: schowek, zrzuty ekranu, Skupienie, nagrywanie, ekrany

    private func setUpEverydayTools() {
        let model = self.model

        // „Skopiowano” (+ historia schowka, jeśli włączona)
        let clipboard = ClipboardMonitor.shared
        clipboard.onCopy = { copied in
            guard Prefs.on(Prefs.clipboard) else { return }
            switch copied {
            case .text(let text):
                var preview = tr("tekst", "text")
                if let text {
                    model.rememberClip(text)
                    preview = String(text.replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces).prefix(40))
                }
                model.show(.copied(symbol: "doc.on.doc.fill", preview: preview), duration: 1.6)
            case .image:
                model.show(.copied(symbol: "photo", preview: tr("obraz", "image")), duration: 1.6)
            case .files(let n):
                model.show(.copied(symbol: "doc.fill", preview: ShelfTools.filesText(n)), duration: 1.6)
            }
        }
        clipboard.start()

        // Zrzuty ekranu – miniatura do przeciągnięcia
        let shots = ScreenshotMonitor()
        shots.onScreenshot = { url in
            guard Prefs.on(Prefs.screenshots) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let thumb = ShelfTools.thumbnail(url)
                model.showAlert(NotchAlert(symbol: "camera.viewfinder", tint: .controlAccentColor,
                                           title: tr("Zrzut ekranu", "Screenshot"),
                                           subtitle: tr("Przeciągnij miniaturę do dokumentu", "Drag the thumbnail into a document"),
                                           actionTitle: tr("Na półkę", "To shelf"), actionURL: url,
                                           image: thumb, fileURL: url, shelfAction: true),
                                duration: 6)
            }
        }
        shots.start()
        screenshots = shots

        // Skupienie, nagrywanie ekranu, rzutnik / AirPlay
        let status = SystemStatusMonitor()
        status.onFocusState = { active in
            model.focusActive = active
            Log.write("Skupienie: \(active ? "włączone – tylko ważne powiadomienia" : "wyłączone")")
        }
        status.onFocus = { name in
            guard Prefs.on(Prefs.focus) else { return }
            if let name {
                let title = name.isEmpty ? tr("Skupienie włączone", "Focus on") : tr("Skupienie", "Focus") + ": \(name)"
                model.showAlert(NotchAlert(symbol: "moon.fill", tint: .systemIndigo, title: title,
                                           subtitle: tr("Wcięcie pokaże tylko ważne powiadomienia",
                                                        "The notch will show only important alerts")),
                                duration: 3, priority: .important)
            } else {
                model.showAlert(NotchAlert(symbol: "moon", tint: .systemGray,
                                           title: tr("Skupienie wyłączone", "Focus off"),
                                           subtitle: tr("Powiadomienia znów docierają", "Alerts are back")),
                                duration: 3, priority: .important)
            }
        }
        status.onRecording = { on in
            let show = Prefs.on(Prefs.screens)
            model.screenRecording = on && show
            guard show else { return }
            if on {
                model.showAlert(NotchAlert(symbol: "record.circle", tint: .systemRed,
                                           title: tr("Nagrywanie ekranu", "Screen recording"),
                                           subtitle: tr("Ekran jest nagrywany", "Your screen is being recorded")),
                                duration: 3.5, priority: .important)
            } else {
                model.showAlert(NotchAlert(symbol: "stop.circle", tint: .systemGray,
                                           title: tr("Nagrywanie zakończone", "Recording stopped"),
                                           subtitle: tr("Plik zapisze się w folderze zrzutów", "The file goes to your screenshots folder")),
                                duration: 3)
            }
        }
        status.onDisplay = { name, connected in
            model.wiredDevices = DeviceMonitor.wiredDevices()
            Log.write("Ekran \(connected ? "podłączony" : "odłączony"): \(name)")
            guard Prefs.on(Prefs.screens) else { return }
            let lower = name.lowercased()
            let airPlay = lower.contains("airplay") || lower.contains("apple tv") || lower.contains(" tv")
            model.showAlert(NotchAlert(symbol: airPlay ? "airplayvideo" : "display", tint: .systemTeal,
                                       title: connected ? tr("Podłączono ekran", "Display connected")
                                                        : tr("Odłączono ekran", "Display disconnected"),
                                       subtitle: name), duration: 4)
        }
        status.start()
        systemStatus = status
    }

    // MARK: - Adresy dynamicnotch:// (aplikacja Skróty, Siri, Touch Bar, Terminal)
    //
    //   dynamicnotch://minutnik?min=10      (także: timer?min=10)
    //   dynamicnotch://stoper               (start / pauza; także: stopwatch)
    //   dynamicnotch://zadanie?tekst=Kupić%20chleb   (także: todo?text=…)
    //   dynamicnotch://panel                (rozwiń / zwiń)
    //   dynamicnotch://ustawienia           (także: settings)

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "dynamicnotch" {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        let command = (url.host ?? "").lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ names: String...) -> String? {
            items.first { names.contains($0.name.lowercased()) }?.value
        }
        Log.write("Adres: \(command)")
        switch command {
        case "minutnik", "timer":
            let minutes = Double(value("min", "minuty", "minutes") ?? "") ?? 5
            model.startTimer(minutes: min(max(minutes, 0.5), 600))
        case "stoper", "stopwatch":
            model.toggleStopwatch()
        case "zadanie", "todo":
            if let text = value("tekst", "text") { model.addTodo(text) }
        case "panel":
            controller.toggle()
        case "ustawienia", "settings":
            openSettings()
        default:
            Log.write("Nieznane polecenie adresu: \(command)")
        }
    }

    // MARK: - Pomocnicze

    /// Otwiera aplikację systemową (Kalendarz, Przypomnienia) po identyfikatorze.
    static func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        Log.write("Otwieram: \(bundleID)")
    }

    /// Otwiera adres (np. konkretne wydarzenie); gdy się nie da – samą aplikację.
    static func open(_ address: String, orApp bundleID: String) {
        if let url = URL(string: address), NSWorkspace.shared.open(url) {
            Log.write("Otwieram: \(url.scheme ?? "")")
        } else {
            openApp(bundleID)
        }
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

    /// Menu programu (widoczne, gdy otwarte są Ustawienia): ⌘, ⌘Q, ⌘W oraz Edycja (⌘C ⌘V ⌘Z),
    /// bez której nie działałoby kopiowanie i wklejanie w polach tekstowych.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Ustawienia…", "Settings…"), action: #selector(menuSettings),
                        keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Zakończ Dynamic Notch", "Quit Dynamic Notch"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: tr("Edycja", "Edit"))
        editMenu.addItem(withTitle: tr("Cofnij", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: tr("Przywróć", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: tr("Wytnij", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: tr("Kopiuj", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: tr("Wklej", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: tr("Zaznacz wszystko", "Select All"), action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: tr("Okno", "Window"))
        windowMenu.addItem(withTitle: tr("Zamknij", "Close"), action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
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
        alert.messageText = tr("Dynamic Notch prosi o uprawnienie Dostępności",
                               "Dynamic Notch needs Accessibility permission")
        alert.informativeText = tr("""
        Dzięki niemu wcięcie widzi, gdzie kończą się menu programu (np. Pages), i nigdy ich nie zasłania, \
        a panel otwiera się bez przełączania programów.

        W oknie „Dostępność” włącz przełącznik przy „Dynamic Notch”.
        """, """
        It lets the notch see where the current app’s menus end, so it never covers them, \
        and lets the panel open without switching apps.

        In the Accessibility window, turn on the switch next to “Dynamic Notch”.
        """)
        alert.addButton(withTitle: tr("Otwórz Ustawienia", "Open Settings"))
        alert.addButton(withTitle: tr("Później", "Later"))
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
