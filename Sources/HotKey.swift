// HotKey.swift – skrót klawiszowy ⌃⌥Spacja (rozwiń / zwiń wcięcie), bez dodatkowych uprawnień

import Foundation
import Carbon

final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, context, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x5743_4E54), id: 1)   // „WCNT”
        let registered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id,
                                             GetApplicationEventTarget(), 0, &hotKeyRef)
        Log.write("Skrót ⌃⌥Spacja: \(status == noErr && registered == noErr ? "aktywny" : "niedostępny (zajęty?)")")
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
