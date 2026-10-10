// PrivacyMonitor.swift – czy mikrofon lub kamera są w użyciu (np. podczas spotkania online)
//
// Mikrofon: CoreAudio, właściwość „urządzenie pracuje gdziekolwiek” domyślnego wejścia.
// Kamera: CoreMediaIO, ta sama właściwość dla każdej kamery.
// Sprawdzanie co 2 s (wstrzymywane przy uśpionym ekranie).

import Foundation
import CoreAudio
import CoreMediaIO

final class PrivacyMonitor {

    /// (mikrofon w użyciu, kamera w użyciu)
    var onChange: ((Bool, Bool) -> Void)?
    private(set) var micInUse = false
    private(set) var cameraInUse = false
    private var timer: Timer?

    init() {
        resume()
    }

    func resume() {
        guard timer == nil else { return }
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.5
        timer = t
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let mic = Self.microphoneRunning()
        let camera = Self.cameraRunning()
        guard mic != micInUse || camera != cameraInUse else { return }
        micInUse = mic
        cameraInUse = camera
        Log.write("Prywatność: mikrofon=\(mic), kamera=\(camera)")
        onChange?(mic, camera)
    }

    private static func microphoneRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0
        else { return false }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running = UInt32(0)
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &runningSize, &running) == noErr
        else { return false }
        return running != 0
    }

    private static func cameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var dataSize: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr, dataSize > 0
        else { return false }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, dataSize, &used, &devices) == noErr
        else { return false }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, size, &got, &running) == noErr,
               running != 0 {
                return true
            }
            size = 0
        }
        return false
    }
}
