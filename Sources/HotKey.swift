// HotKey.swift – skrót klawiszowy rozwijający wcięcie (domyślnie ⌃⌥Spacja, do zmiany w Ustawieniach)
// Działa bez dodatkowych uprawnień (Carbon RegisterEventHotKey).

import Cocoa
import Carbon

final class HotKey {

    static let changedNote = Notification.Name("pl.bulka.dynamicnotch.hotKeyChanged")

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        _ = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, context, &handlerRef)
        register()
        NotificationCenter.default.addObserver(forName: Self.changedNote, object: nil, queue: .main) { [weak self] _ in
            self?.register()
        }
    }

    /// (Ponowna) rejestracja skrótu zapisanego w ustawieniach.
    func register() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let code = UInt32(UserDefaults.standard.integer(forKey: Prefs.hotKeyCode))
        let mods = UInt32(UserDefaults.standard.integer(forKey: Prefs.hotKeyMods))
        let id = EventHotKeyID(signature: OSType(0x5743_4E54), id: 1)   // „WCNT”
        let status = RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        Log.write("Skrót \(Self.currentText): \(status == noErr ? "aktywny" : "niedostępny (zajęty przez inny program?)")")
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    // MARK: - Opis i zapis skrótu

    /// np. „⌃⌥Spacja”
    static var currentText: String {
        let mods = UserDefaults.standard.integer(forKey: Prefs.hotKeyMods)
        let name = UserDefaults.standard.string(forKey: "skrotNazwa") ?? tr("Spacja", "Space")
        return symbols(mods) + name
    }

    static func symbols(_ mods: Int) -> String {
        var s = ""
        if mods & controlKey != 0 { s += "⌃" }
        if mods & optionKey != 0 { s += "⌥" }
        if mods & shiftKey != 0 { s += "⇧" }
        if mods & cmdKey != 0 { s += "⌘" }
        return s
    }

    /// Zapisuje skrót z naciśniętego klawisza. Zwraca false, gdy brak ⌘, ⌥ lub ⌃ (taki skrót kolidowałby z pisaniem).
    static func save(from event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods = 0
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.command) { mods |= cmdKey }
        guard mods & (controlKey | optionKey | cmdKey) != 0 else { return false }
        let name: String
        switch Int(event.keyCode) {
        case kVK_Space: name = tr("Spacja", "Space")
        case kVK_Return: name = "↩"
        case kVK_Tab: name = "⇥"
        case kVK_UpArrow: name = "↑"
        case kVK_DownArrow: name = "↓"
        case kVK_LeftArrow: name = "←"
        case kVK_RightArrow: name = "→"
        default: name = (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
        UserDefaults.standard.set(Int(event.keyCode), forKey: Prefs.hotKeyCode)
        UserDefaults.standard.set(mods, forKey: Prefs.hotKeyMods)
        UserDefaults.standard.set(name, forKey: "skrotNazwa")
        NotificationCenter.default.post(name: changedNote, object: nil)
        return true
    }
}
