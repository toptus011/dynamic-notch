// Prefs.swift – ustawienia programu (zapisywane w UserDefaults)

import Foundation

enum Prefs {
    static let music = "pokazMuzyke"
    static let volume = "pokazGlosnosc"
    static let brightness = "pokazJasnosc"
    static let devices = "pokazUrzadzenia"
    static let power = "pokazZasilanie"
    static let calendar = "pokazKalendarz"
    static let battery = "ostrzezeniaBaterii"
    static let privacy = "pokazMikrofonKamere"
    static let reminders = "pokazPrzypomnienia"
    /// Przejmowanie klawiszy głośności i jasności – wtedy nie pojawia się okienko systemowe.
    static let mediaKeys = "przejmujKlawisze"
    /// "klik" – rozwijanie kliknięciem, "najechanie" – po zatrzymaniu kursora na 0,5 s
    static let openMode = "otwieranie"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            music: true,
            volume: true,
            brightness: true,
            devices: true,
            power: true,
            calendar: true,
            battery: true,
            privacy: true,
            reminders: true,
            mediaKeys: true,
            openMode: "klik",
        ])
    }

    static func on(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static var opensOnHover: Bool {
        UserDefaults.standard.string(forKey: openMode) == "najechanie"
    }
}
