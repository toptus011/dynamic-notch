// SettingsWindow.swift – okno Ustawienia (ponowne uruchomienie programu lub prawy przycisk na wcięciu)
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

    @Published var music: Bool { didSet { defaults.set(music, forKey: Prefs.music) } }
    @Published var volume: Bool { didSet { defaults.set(volume, forKey: Prefs.volume) } }
    @Published var brightness: Bool { didSet { defaults.set(brightness, forKey: Prefs.brightness) } }
    @Published var devices: Bool { didSet { defaults.set(devices, forKey: Prefs.devices) } }
    @Published var power: Bool { didSet { defaults.set(power, forKey: Prefs.power) } }
    @Published var calendar: Bool { didSet { defaults.set(calendar, forKey: Prefs.calendar) } }
    @Published var battery: Bool { didSet { defaults.set(battery, forKey: Prefs.battery) } }
    @Published var privacy: Bool { didSet { defaults.set(privacy, forKey: Prefs.privacy) } }
    @Published var reminders: Bool { didSet { defaults.set(reminders, forKey: Prefs.reminders) } }
    @Published var mediaKeys: Bool { didSet { defaults.set(mediaKeys, forKey: Prefs.mediaKeys) } }
    @Published var openMode: String { didSet { defaults.set(openMode, forKey: Prefs.openMode) } }
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }
    @Published var axTrusted: Bool
    private var suppressApply = false

    init() {
        music = Prefs.on(Prefs.music)
        volume = Prefs.on(Prefs.volume)
        brightness = Prefs.on(Prefs.brightness)
        devices = Prefs.on(Prefs.devices)
        power = Prefs.on(Prefs.power)
        calendar = Prefs.on(Prefs.calendar)
        battery = Prefs.on(Prefs.battery)
        privacy = Prefs.on(Prefs.privacy)
        reminders = Prefs.on(Prefs.reminders)
        mediaKeys = Prefs.on(Prefs.mediaKeys)
        openMode = UserDefaults.standard.string(forKey: Prefs.openMode) ?? "klik"
        launchAtLogin = SettingsModel.agent.status == .enabled
        axTrusted = AXIsProcessTrusted()
    }

    func refresh() {
        axTrusted = AXIsProcessTrusted()
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
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    var openLog: () -> Void
    var placement: () -> String

    var body: some View {
        Form {
            Section("Co pokazywać we wcięciu") {
                Toggle("Grana muzyka (Muzyka, Spotify)", isOn: $settings.music)
                Toggle("Podłączanie urządzeń Bluetooth", isOn: $settings.devices)
                Toggle("Podłączanie zasilacza", isOn: $settings.power)
                Toggle("Wydarzenia z Kalendarza (najbliższe 7 dni)", isOn: $settings.calendar)
                Toggle("Przypomnienia na dziś (w panelu)", isOn: $settings.reminders)
                Toggle("Ostrzeżenia o baterii (20%, 10%, naładowano)", isOn: $settings.battery)
                Toggle("Informacja o włączeniu kamery i mikrofonu", isOn: $settings.privacy)
            }
            Text("Głośność i jasność pokazuje sam macOS – Dynamic Notch pokazuje to, czego system nie pokazuje: muzykę, urządzenia, wydarzenia i to, co działa w tle.")
                .font(.footnote).foregroundColor(.secondary)
            Section("Rozwijanie panelu") {
                Picker("Otwieraj", selection: $settings.openMode) {
                    Text("Kliknięciem").tag("klik")
                    Text("Po zatrzymaniu kursora (0,5 s)").tag("najechanie")
                }
                Text("Skrót klawiszowy: ⌃⌥Spacja. Prawy przycisk na wcięciu otwiera menu.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section("Ogólne") {
                Toggle("Uruchamiaj przy starcie Maca", isOn: $settings.launchAtLogin)
                HStack {
                    Text(settings.axTrusted
                         ? "✅ Dostępność: nadana"
                         : "❌ Dostępność: brak – Dynamic Notch nie widzi, gdzie kończą się menu")
                    Spacer()
                    if !settings.axTrusted {
                        Button("Nadaj…") { settings.requestAccessibility() }
                    }
                }
                Text("Pasek menu: \(placement())").font(.footnote).foregroundColor(.secondary)
                Button("Pokaż dziennik zdarzeń", action: openLog)
            }
            Text("Dynamic Notch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · Opracował ks. Piotr Bułka")
                .font(.footnote).foregroundColor(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 660)
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
            if #available(macOS 13.0, *) { host.sizingOptions = [] }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.contentViewController = host
            w.setContentSize(NSSize(width: 480, height: 660))
            w.title = "Dynamic Notch – Ustawienia"
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
