// Prefs.swift – ustawienia programu (zapisywane w UserDefaults)

import Foundation
import Carbon

enum Prefs {
    // Co pokazywać we wcięciu
    static let music = "pokazMuzyke"
    static let devices = "pokazUrzadzenia"
    static let power = "pokazZasilanie"
    static let calendar = "pokazKalendarz"
    static let battery = "ostrzezeniaBaterii"
    static let privacy = "pokazMikrofonKamere"
    static let reminders = "pokazPrzypomnienia"
    // Na co dzień i praca
    static let screenshots = "pokazZrzuty"
    static let clipboard = "pokazSchowek"
    /// Historia schowka – odczyt treści schowka; domyślnie wyłączona (prywatność, macOS 26)
    static let clipboardHistory = "historiaSchowka"
    static let focus = "pokazSkupienie"
    static let screens = "pokazEkrany"
    // Ogólne
    static let systemNotifications = "powiadomieniaSystemowe"
    static let updates = "sprawdzajAktualizacje"
    /// "klik" – rozwijanie kliknięciem, "najechanie" – po zatrzymaniu kursora na 0,5 s
    static let openMode = "otwieranie"
    /// Skrót klawiszowy (kod klawisza i modyfikatory w zapisie Carbon)
    static let hotKeyCode = "skrotKlawisz"
    static let hotKeyMods = "skrotModyfikatory"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            music: true,
            devices: true,
            power: true,
            calendar: true,
            battery: true,
            privacy: true,
            reminders: true,
            screenshots: true,
            clipboard: true,
            clipboardHistory: false,
            focus: true,
            screens: true,
            systemNotifications: true,
            updates: true,
            openMode: "klik",
            hotKeyCode: kVK_Space,
            hotKeyMods: controlKey | optionKey,
        ])
        // Porządki po starszych wersjach (wskaźniki głośności i jasności, przejmowanie klawiszy)
        for old in ["pokazGlosnosc", "pokazJasnosc", "przejmujKlawisze"] {
            UserDefaults.standard.removeObject(forKey: old)
        }
    }

    static func on(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static var opensOnHover: Bool {
        UserDefaults.standard.string(forKey: openMode) == "najechanie"
    }

    /// Tryb niskiego zużycia energii – wtedy wszystko sprawdzamy rzadziej.
    static var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
}
