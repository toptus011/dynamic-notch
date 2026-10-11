// SettingsWindow.swift – okno Ustawienia w stylu programów Apple (zakładki u góry)
// Otwierane: prawy przycisk na wcięciu → Ustawienia…, ⌘, albo ponowne uruchomienie programu.
//
// Uwaga: w macOS Tahoe @State i @AppStorage są makrami, które wymagają pełnego Xcode.
// Dlatego stan ustawień trzymamy w zwykłym obiekcie z @Published (Combine).

import Cocoa
import SwiftUI
import Combine
import ApplicationServices
import ServiceManagement

final class SettingsModel: ObservableObject {
    private let defaults = UserDefaults.standard
    /// Agent w tle: start przy logowaniu i automatyczny restart po awarii.
    static var agent: SMAppService { SMAppService.agent(plistName: AppDelegate.agentPlist) }

    // Wcięcie
    @Published var music: Bool { didSet { defaults.set(music, forKey: Prefs.music) } }
    @Published var devices: Bool { didSet { defaults.set(devices, forKey: Prefs.devices) } }
    @Published var power: Bool { didSet { defaults.set(power, forKey: Prefs.power) } }
    @Published var calendar: Bool { didSet { defaults.set(calendar, forKey: Prefs.calendar) } }
    @Published var reminders: Bool { didSet { defaults.set(reminders, forKey: Prefs.reminders) } }
    @Published var battery: Bool { didSet { defaults.set(battery, forKey: Prefs.battery) } }
    @Published var privacy: Bool { didSet { defaults.set(privacy, forKey: Prefs.privacy) } }
    // Narzędzia
    @Published var screenshots: Bool { didSet { defaults.set(screenshots, forKey: Prefs.screenshots) } }
    @Published var clipboard: Bool { didSet { defaults.set(clipboard, forKey: Prefs.clipboard) } }
    @Published var clipboardHistory: Bool { didSet { defaults.set(clipboardHistory, forKey: Prefs.clipboardHistory) } }
    @Published var focus: Bool { didSet { defaults.set(focus, forKey: Prefs.focus) } }
    @Published var screens: Bool { didSet { defaults.set(screens, forKey: Prefs.screens) } }
    // Ogólne
    @Published var systemNotifications: Bool {
        didSet {
            defaults.set(systemNotifications, forKey: Prefs.systemNotifications)
            if systemNotifications { SystemNotifier.requestAuthorization() }
        }
    }
    @Published var updates: Bool { didSet { defaults.set(updates, forKey: Prefs.updates) } }
    @Published var openMode: String { didSet { defaults.set(openMode, forKey: Prefs.openMode) } }
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }
    @Published var axTrusted: Bool
    @Published var hotKeyText = HotKey.currentText
    @Published var recordingHotKey = false

    private var suppressApply = false
    private var keyMonitor: Any?

    init() {
        music = Prefs.on(Prefs.music)
        devices = Prefs.on(Prefs.devices)
        power = Prefs.on(Prefs.power)
        calendar = Prefs.on(Prefs.calendar)
        reminders = Prefs.on(Prefs.reminders)
        battery = Prefs.on(Prefs.battery)
        privacy = Prefs.on(Prefs.privacy)
        screenshots = Prefs.on(Prefs.screenshots)
        clipboard = Prefs.on(Prefs.clipboard)
        clipboardHistory = Prefs.on(Prefs.clipboardHistory)
        focus = Prefs.on(Prefs.focus)
        screens = Prefs.on(Prefs.screens)
        systemNotifications = Prefs.on(Prefs.systemNotifications)
        updates = Prefs.on(Prefs.updates)
        openMode = UserDefaults.standard.string(forKey: Prefs.openMode) ?? "klik"
        launchAtLogin = SettingsModel.agent.status == .enabled
        axTrusted = AXIsProcessTrusted()
    }

    func refresh() {
        axTrusted = AXIsProcessTrusted()
        hotKeyText = HotKey.currentText
        let enabled = SettingsModel.agent.status == .enabled
        // Stan mógł się zmienić w Ustawieniach systemowych – synchronizujemy bez ponownej rejestracji.
        if launchAtLogin != enabled { suppressApply = true; launchAtLogin = enabled; suppressApply = false }
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        axTrusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func applyLaunchAtLogin() {
        guard !suppressApply else { return }
        do {
            if launchAtLogin {
                try SettingsModel.agent.register()
            } else {
                try SettingsModel.agent.unregister()
            }
            Log.write("Uruchamianie przy logowaniu: \(launchAtLogin)")
        } catch {
            Log.write("Uruchamianie przy logowaniu – błąd: \(error.localizedDescription)")
        }
    }

    // MARK: - Nagrywanie skrótu klawiszowego

    func startRecordingHotKey() {
        stopRecordingHotKey()
        recordingHotKey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {            // Esc – rezygnacja
                self.stopRecordingHotKey()
            } else if HotKey.save(from: event) {
                self.hotKeyText = HotKey.currentText
                self.stopRecordingHotKey()
            } else {
                NSSound.beep()                  // skrót musi mieć ⌘, ⌥ lub ⌃
            }
            return nil
        }
    }

    func stopRecordingHotKey() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recordingHotKey = false
    }

    func resetHotKey() {
        defaults.removeObject(forKey: Prefs.hotKeyCode)
        defaults.removeObject(forKey: Prefs.hotKeyMods)
        defaults.removeObject(forKey: "skrotNazwa")
        NotificationCenter.default.post(name: HotKey.changedNote, object: nil)
        hotKeyText = HotKey.currentText
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    var openLog: () -> Void
    var placement: () -> String

    var body: some View {
        TabView {
            general
                .tabItem { Label(tr("Ogólne", "General"), systemImage: "gearshape") }
            notch
                .tabItem { Label(tr("Wcięcie", "Notch"), systemImage: "rectangle.topthird.inset.filled") }
            tools
                .tabItem { Label(tr("Narzędzia", "Tools"), systemImage: "wrench.and.screwdriver") }
        }
        .padding(.top, 6)
        .frame(width: 500, height: 500)
    }

    // MARK: Ogólne

    private var general: some View {
        Form {
            Section {
                Toggle(tr("Uruchamiaj przy starcie Maca", "Open at login"), isOn: $settings.launchAtLogin)
                Picker(tr("Rozwijanie panelu", "Open the panel"), selection: $settings.openMode) {
                    Text(tr("Kliknięciem", "On click")).tag("klik")
                    Text(tr("Po zatrzymaniu kursora (0,5 s)", "On hover (0.5 s)")).tag("najechanie")
                }
                HStack {
                    Text(tr("Skrót klawiszowy", "Keyboard shortcut"))
                    Spacer()
                    Button(action: {
                        settings.recordingHotKey ? settings.stopRecordingHotKey() : settings.startRecordingHotKey()
                    }) {
                        Text(settings.recordingHotKey ? tr("Naciśnij skrót… (Esc – anuluj)", "Press shortcut… (Esc to cancel)")
                                                      : settings.hotKeyText)
                            .monospacedDigit()
                            .frame(minWidth: 90)
                    }
                    Button(tr("Domyślny", "Default")) { settings.resetHotKey() }
                }
            }
            Section {
                Toggle(tr("Ważne powiadomienia także w Centrum powiadomień", "Important alerts also in Notification Center"),
                       isOn: $settings.systemNotifications)
                Text(tr("Koniec minutnika i początek spotkania – gdy od minuty nie używasz Maca lub ekran śpi.",
                        "Timer end and meeting start – when the Mac has been idle for a minute or the display is asleep."))
                    .font(.footnote).foregroundColor(.secondary)
                Toggle(tr("Sprawdzaj aktualizacje na GitHubie (raz dziennie)", "Check GitHub for updates (once a day)"),
                       isOn: $settings.updates)
            }
            Section {
                HStack {
                    Text(settings.axTrusted
                         ? tr("✅ Dostępność: nadana", "✅ Accessibility: granted")
                         : tr("❌ Dostępność: brak – wcięcie nie widzi, gdzie kończą się menu",
                              "❌ Accessibility: missing – the notch can’t see where menus end"))
                    Spacer()
                    if !settings.axTrusted {
                        Button(tr("Nadaj…", "Grant…")) { settings.requestAccessibility() }
                    }
                }
                Text(tr("Pasek menu: ", "Menu bar: ") + placement())
                    .font(.footnote).foregroundColor(.secondary)
                Button(tr("Pokaż dziennik zdarzeń", "Show event log"), action: openLog)
            }
            Text("Dynamic Notch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · "
                 + tr("Opracował ks. Piotr Bułka", "Made by Fr. Piotr Bułka"))
                .font(.footnote).foregroundColor(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: Wcięcie

    private var notch: some View {
        Form {
            Section(tr("Co pokazywać", "What to show")) {
                Toggle(tr("Grana muzyka (Muzyka, Spotify)", "Now playing (Music, Spotify)"), isOn: $settings.music)
                Toggle(tr("Wydarzenia z Kalendarza (karta 15 min przed i na początku)",
                          "Calendar events (card 15 min before and at start)"), isOn: $settings.calendar)
                Toggle(tr("Przypomnienia na dziś (w panelu)", "Today’s reminders (in the panel)"), isOn: $settings.reminders)
                Toggle(tr("Podłączanie urządzeń Bluetooth", "Bluetooth devices connecting"), isOn: $settings.devices)
                Toggle(tr("Podłączanie zasilacza", "Power adapter"), isOn: $settings.power)
                Toggle(tr("Ostrzeżenia o baterii (20%, 10%, naładowano)", "Battery warnings (20%, 10%, charged)"),
                       isOn: $settings.battery)
                Toggle(tr("Włączenie kamery i mikrofonu", "Camera and microphone turning on"), isOn: $settings.privacy)
            }
            Text(tr("Głośność i jasność pokazuje sam macOS. Przy włączonym Skupieniu wcięcie pokazuje tylko ważne powiadomienia: spotkania, minutnik, baterię, kamerę i mikrofon.",
                    "Volume and brightness are shown by macOS itself. While a Focus is on, the notch shows only important alerts: meetings, timer, battery, camera and microphone."))
                .font(.footnote).foregroundColor(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: Narzędzia i prywatność

    private var tools: some View {
        Form {
            Section(tr("Na co dzień i praca", "Everyday and work")) {
                Toggle(tr("Miniatura zrzutu ekranu", "Screenshot thumbnail"), isOn: $settings.screenshots)
                Toggle(tr("„Skopiowano” przy ⌘C", "“Copied” on ⌘C"), isOn: $settings.clipboard)
                Toggle(tr("Włączenie i wyłączenie Skupienia", "Focus turning on and off"), isOn: $settings.focus)
                Toggle(tr("Nagrywanie ekranu, rzutnik i AirPlay", "Screen recording, projector and AirPlay"),
                       isOn: $settings.screens)
            }
            Section(tr("Prywatność", "Privacy")) {
                Toggle(tr("Historia schowka (ostatnie 8 tekstów)", "Clipboard history (last 8 texts)"),
                       isOn: $settings.clipboardHistory)
                Text(tr("Wyłączona: wcięcie wie tylko, że coś skopiowano, ale nie czyta treści. Włączona: teksty są pamiętane do zamknięcia programu (nie trafiają na dysk), hasła są pomijane. Historię schowka ma też Spotlight w macOS 26.",
                        "Off: the notch only knows that something was copied, without reading it. On: texts are kept in memory until quit (never saved to disk); passwords are skipped. Spotlight in macOS 26 also has clipboard history."))
                    .font(.footnote).foregroundColor(.secondary)
            }
            Text(tr("Minutnik, stoper, lista zadań i półka są w panelu (kliknij wcięcie). Pliki przeciągnij na wcięcie. Skróty: Esc – zwiń, ⌘1–⌘4 – zakładki.",
                    "Timer, stopwatch, to-do list and shelf live in the panel (click the notch). Drag files onto the notch. Keys: Esc – close, ⌘1–⌘4 – tabs."))
                .font(.footnote).foregroundColor(.secondary)
        }
        .formStyle(.grouped)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?
    private let settings = SettingsModel()

    func show(openLog: @escaping () -> Void, placement: @escaping () -> String) {
        settings.refresh()
        Log.write("Otwieram Ustawienia")
        if window == nil {
            let view = SettingsView(settings: settings, openLog: openLog, placement: placement)
            let host = NSHostingController(rootView: view)
            // Stały rozmiar okna – bez tego okno mogło mieć zerową wysokość i nie było go widać.
            host.sizingOptions = []
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.contentViewController = host
            w.setContentSize(NSSize(width: 500, height: 500))
            w.title = tr("Dynamic Notch – Ustawienia", "Dynamic Notch – Settings")
            w.isReleasedWhenClosed = false
            // Okno pojawia się na bieżącym biurku (także obok programu na pełnym ekranie).
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            w.center()
            window = w
        }
        guard let window else { return }
        // Po zamknięciu menu podręcznego – inaczej macOS potrafi zignorować okno.
        DispatchQueue.main.async {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            // Na chwilę na wierzchu, potem zwykłe okno.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { window.level = .normal }
        }
    }
}
