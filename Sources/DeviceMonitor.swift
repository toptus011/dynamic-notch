// DeviceMonitor.swift – podłączanie i odłączanie urządzeń Bluetooth (AirPods, klawiatura, mysz…)

import Cocoa
import IOKit
import IOBluetooth

struct DeviceInfo: Equatable, Identifiable {
    let id: String
    let name: String
    let symbol: String
    /// „Bluetooth”, „USB”, „Ekran”
    var kind = "Bluetooth"
}

final class DeviceMonitor: NSObject {

    /// (urządzenie, true = podłączono / false = odłączono)
    var onChange: ((DeviceInfo, Bool) -> Void)?
    private(set) var connected: [DeviceInfo] = []

    private var connectNote: IOBluetoothUserNotification?
    private let startedAt = Date()

    override init() {
        super.init()
        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in paired where device.isConnected() {
                connected.append(Self.info(device))
                device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
            }
        }
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(deviceConnected(_:device:)))
        Log.write("Bluetooth: połączone urządzenia: \(connected.map { $0.name }.joined(separator: ", "))")
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let info = Self.info(device)
        let isNew = !connected.contains(info)
        if isNew {
            connected.append(info)
            device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        }
        // Przy starcie system zgłasza wszystkie już połączone urządzenia – tego nie pokazujemy.
        guard isNew, Date().timeIntervalSince(startedAt) > 3 else { return }
        Log.write("Bluetooth: podłączono \(info.name)")
        onChange?(info, true)
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let info = Self.info(device)
        connected.removeAll { $0.id == info.id }
        Log.write("Bluetooth: odłączono \(info.name)")
        onChange?(info, false)
    }

    private static func info(_ device: IOBluetoothDevice) -> DeviceInfo {
        let name = device.name ?? tr("Urządzenie Bluetooth", "Bluetooth device")
        return DeviceInfo(id: device.addressString ?? name, name: name, symbol: symbol(for: device, name: name))
    }

    /// Urządzenia podłączone przewodem (USB) i ekrany zewnętrzne – odczyt w chwili otwarcia panelu.
    static func wiredDevices() -> [DeviceInfo] {
        var result: [DeviceInfo] = []

        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) == 0 else { continue }
            let lower = screen.localizedName.lowercased()
            let airPlay = lower.contains("airplay") || lower.contains("apple tv")
            result.append(DeviceInfo(id: "ekran-\(number)", name: screen.localizedName,
                                     symbol: airPlay ? "airplayvideo" : "display",
                                     kind: airPlay ? "AirPlay" : tr("Ekran", "Display")))
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"),
                                           &iterator) == KERN_SUCCESS else { return result }
        var seen: Set<String> = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            let name = (IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString,
                                                        kCFAllocatorDefault, 0)?.takeRetainedValue() as? String) ?? ""
            let location = (IORegistryEntryCreateCFProperty(service, "locationID" as CFString,
                                                            kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?
                .stringValue ?? name
            IOObjectRelease(service)
            let lower = name.lowercased()
            // Koncentratory (huby) i elementy wewnętrzne pomijamy – to nie są „urządzenia” dla użytkownika.
            guard !name.isEmpty, !lower.contains("hub"), !lower.contains("internal"),
                  !seen.contains(location) else { continue }
            seen.insert(location)
            result.append(DeviceInfo(id: "usb-\(location)", name: name, symbol: usbSymbol(lower), kind: "USB"))
        }
        IOObjectRelease(iterator)
        return result
    }

    private static func usbSymbol(_ lower: String) -> String {
        if lower.contains("keyboard") || lower.contains("klawiatura") { return "keyboard" }
        if lower.contains("mouse") || lower.contains("mysz") { return "computermouse" }
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("camera") || lower.contains("webcam") || lower.contains("kamera") { return "web.camera" }
        if lower.contains("audio") || lower.contains("headset") || lower.contains("mic") { return "headphones" }
        if lower.contains("disk") || lower.contains("ssd") || lower.contains("flash") || lower.contains("drive")
            || lower.contains("storage") || lower.contains("usb3") || lower.contains("card") { return "externaldrive" }
        if lower.contains("printer") || lower.contains("drukarka") { return "printer" }
        return "cable.connector"
    }

    /// Symbol SF Symbols dopasowany do rodzaju urządzenia.
    private static func symbol(for device: IOBluetoothDevice, name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("keyboard") || lower.contains("klawiatura") { return "keyboard" }
        if lower.contains("mouse") || lower.contains("mysz") { return "magicmouse" }
        if lower.contains("trackpad") { return "hand.point.up.left" }
        switch device.deviceClassMajor {
        case 0x04: return "headphones"                       // audio
        case 0x05:                                          // urządzenia wejściowe
            let minor = device.deviceClassMinor
            if minor & 0x10 != 0 { return "keyboard" }
            if minor & 0x20 != 0 { return "computermouse" }
            return "keyboard"
        case 0x02: return "iphone"                          // telefon
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
