// BrightnessMonitor.swift – jasność wbudowanego ekranu (prywatny moduł DisplayServices,
// z którego korzystają też inne programy do sterowania jasnością na Macach z Apple Silicon)

import Foundation
import CoreGraphics

final class BrightnessMonitor {

    var onChange: ((Float) -> Void)?

    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private let getFn: GetFn?
    private let setFn: SetFn?
    private var display: CGDirectDisplayID
    private var last: Float?
    private var timer: Timer?

    init(display: CGDirectDisplayID) {
        self.display = display
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        if let handle, let g = dlsym(handle, "DisplayServicesGetBrightness") {
            getFn = unsafeBitCast(g, to: GetFn.self)
        } else {
            getFn = nil
        }
        if let handle, let s = dlsym(handle, "DisplayServicesSetBrightness") {
            setFn = unsafeBitCast(s, to: SetFn.self)
        } else {
            setFn = nil
        }
        Log.write("Jasność: odczyt \(getFn != nil ? "dostępny" : "NIEDOSTĘPNY")")
        last = brightness
        resume()
    }

    /// Jasność nie wysyła powiadomień – sprawdzamy dwa razy na sekundę (bardzo tani odczyt).
    /// Przy uśpionym ekranie sprawdzanie jest wstrzymane.
    func resume() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.15
        timer = t
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    var isAvailable: Bool { getFn != nil }

    var brightness: Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    func setBrightness(_ value: Float) {
        guard let setFn else { return }
        _ = setFn(display, max(0.02, min(1, value)))
        last = brightness
    }

    private func poll() {
        guard let value = brightness else { return }
        defer { last = value }
        guard let previous = last else { return }
        // Klawisz jasności zmienia ją skokowo (ok. 6%); automatyczna jasność – drobnymi krokami.
        // Dzięki progowi wcięcie nie reaguje na samoczynne dopasowanie do światła.
        if abs(value - previous) >= 0.03 {
            onChange?(value)
        }
    }
}
