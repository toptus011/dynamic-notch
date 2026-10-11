// Lang.swift – język interfejsu: polski (domyślnie) albo angielski, gdy system nie jest po polsku
// Dziennik zdarzeń zostaje po polsku.

import Foundation

enum Lang {
    /// true – interfejs po polsku (system po polsku); w innym wypadku po angielsku.
    static let polish: Bool = (Locale.preferredLanguages.first ?? "pl").lowercased().hasPrefix("pl")
    static var locale: Locale { Locale(identifier: polish ? "pl_PL" : "en_US") }
}

/// Tekst w języku interfejsu: tr("Zakończ", "Quit")
func tr(_ pl: String, _ en: String) -> String {
    Lang.polish ? pl : en
}
