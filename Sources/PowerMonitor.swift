// PowerMonitor.swift – bateria i podłączenie zasilacza (IOKit)

import Foundation
import IOKit.ps

final class PowerMonitor {

    enum Alert: Equatable {
        case low(Int)        // 20%
        case critical(Int)   // 10%
        case charged         // 100% przy podłączonym zasilaczu
    }

    /// (poziom %, ładuje się, zasilacz podłączony) – tylko przy podłączeniu/odłączeniu zasilacza
    var onChange: ((Int, Bool, Bool) -> Void)?
    /// Ostrzeżenia o baterii i komunikat o pełnym naładowaniu
    var onAlert: ((Alert) -> Void)?
    /// Każda zmiana poziomu (do panelu)
    var onLevel: ((Int, Bool, Bool) -> Void)?

    private(set) var level = 100
    private(set) var charging = false
    private(set) var onAC = false

    private var source: CFRunLoopSource?
    // Każde ostrzeżenie raz na cykl rozładowania / ładowania
    private var warnedLow = false
    private var warnedCritical = false
    private var announcedCharged = false

    init() {
        read()
        // Bez ostrzeżeń o stanie zastanym przy starcie
        warnedLow = !onAC && level <= 20
        warnedCritical = !onAC && level <= 10
        announcedCharged = onAC && level >= 100

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let me = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            me.changed()
        }
        if let loop = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            source = loop
            CFRunLoopAddSource(CFRunLoopGetMain(), loop, .defaultMode)
        }
    }

    private func changed() {
        let wasOnAC = onAC
        let previous = level
        read()
        onLevel?(level, charging, onAC)

        if wasOnAC != onAC {
            Log.write("Zasilanie: \(onAC ? "podłączono zasilacz" : "praca na baterii"), \(level)%")
            onChange?(level, charging, onAC)
            if onAC {
                warnedLow = false
                warnedCritical = false
            } else {
                announcedCharged = false
            }
        }

        if !onAC {
            if level <= 10 && previous > 10 && !warnedCritical {
                warnedCritical = true
                warnedLow = true
                onAlert?(.critical(level))
            } else if level <= 20 && previous > 20 && !warnedLow {
                warnedLow = true
                onAlert?(.low(level))
            }
        } else if level >= 100 && !announcedCharged {
            announcedCharged = true
            onAlert?(.charged)
        }
    }

    private func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            if let current = desc[kIOPSCurrentCapacityKey] as? Int { level = current }
            if let isCharging = desc[kIOPSIsChargingKey] as? Bool { charging = isCharging }
            if let state = desc[kIOPSPowerSourceStateKey] as? String { onAC = state == kIOPSACPowerValue }
        }
    }
}
