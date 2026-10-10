// DeviceMonitor.swift – podłączanie i odłączanie urządzeń Bluetooth (AirPods, klawiatura, mysz…)

import Foundation
import IOBluetooth

struct DeviceInfo: Equatable, Identifiable {
    let id: String
    let name: String
    let symbol: String
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
        let name = device.name ?? "Urządzenie Bluetooth"
        return DeviceInfo(id: device.addressString ?? name, name: name, symbol: symbol(for: device, name: name))
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
