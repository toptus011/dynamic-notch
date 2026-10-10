// AudioMonitor.swift – głośność i wyciszenie domyślnego wyjścia dźwięku (CoreAudio)

import Foundation
import CoreAudio

final class AudioMonitor {

    /// (głośność 0…1, wyciszenie)
    var onChange: ((Float, Bool) -> Void)?

    private var device = AudioDeviceID(0)
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init() {
        device = Self.defaultOutputDevice()
        attachListeners()
        watchDefaultDevice()
    }

    // MARK: - Odczyt

    var volume: Float {
        if let v = readFloat(kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return v
        }
        let channels = [UInt32(1), UInt32(2)].compactMap { readFloat(kAudioDevicePropertyVolumeScalar, element: $0) }
        return channels.isEmpty ? 0 : channels.reduce(0, +) / Float(channels.count)
    }

    var muted: Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    /// Nazwa urządzenia wyjściowego (np. „Głośniki MacBooka Pro”, „AirPods”).
    var deviceName: String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue()
        else { return "" }
        return value as String
    }

    private func readFloat(_ selector: AudioObjectPropertySelector, element: UInt32) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    // MARK: - Ustawianie (suwak w panelu)

    func setVolume(_ value: Float) {
        let v = max(0, min(1, value))
        if setFloat(kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain, v) { return }
        _ = setFloat(kAudioDevicePropertyVolumeScalar, element: 1, v)
        _ = setFloat(kAudioDevicePropertyVolumeScalar, element: 2, v)
    }

    func setMuted(_ on: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return }
        var value: UInt32 = on ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func setFloat(_ selector: AudioObjectPropertySelector, element: UInt32, _ value: Float) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var v = Float32(value)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    // MARK: - Nasłuch zmian

    private static func defaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private func attachListeners() {
        let targets: [(AudioObjectPropertySelector, UInt32)] = [
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
            (kAudioDevicePropertyVolumeScalar, 2),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        ]
        for (selector, element) in targets {
            var address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.fire() }
            if AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block) == noErr {
                listeners.append((address, block))
            }
        }
    }

    private func detachListeners() {
        for (address, block) in listeners {
            var a = address
            AudioObjectRemovePropertyListenerBlock(device, &a, DispatchQueue.main, block)
        }
        listeners.removeAll()
    }

    private func watchDefaultDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) {
            [weak self] _, _ in
            guard let self else { return }
            self.detachListeners()
            self.device = Self.defaultOutputDevice()
            self.attachListeners()
            Log.write("Zmiana wyjścia dźwięku: \(self.deviceName)")
        }
    }

    private func fire() {
        onChange?(volume, muted)
    }
}
