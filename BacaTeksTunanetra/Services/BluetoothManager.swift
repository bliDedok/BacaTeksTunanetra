import Foundation
import Combine
import CoreBluetooth
import ExternalAccessory

final class BluetoothManager: NSObject, ObservableObject {
    @Published var bleRemoteDetected = false
    @Published var mfiAccessoryDetected = false
    @Published var bluetoothAvailable = false

    private var centralManager: CBCentralManager?

    func start() {
        centralManager = CBCentralManager(delegate: self, queue: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDidConnect),
            name: Notification.Name.EAAccessoryDidConnect,
            object: nil
        )

        EAAccessoryManager.shared().registerForLocalNotifications()
        refreshMFiAccessories()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func refreshMFiAccessories() {
        let connected = EAAccessoryManager.shared().connectedAccessories
        DispatchQueue.main.async {
            self.mfiAccessoryDetected = !connected.isEmpty
        }
    }

    @objc private func accessoryDidConnect() {
        refreshMFiAccessories()
    }

    func startBLEScanIfPossible() {
        guard let centralManager, centralManager.state == .poweredOn else { return }

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothAvailable = (central.state == .poweredOn)
        }

        if central.state == .poweredOn {
            startBLEScanIfPossible()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        DispatchQueue.main.async {
            self.bleRemoteDetected = true
        }
    }
}
