import Foundation
import Combine
import UIKit

final class InputManager: ObservableObject {
    enum ExternalAction {
        case triggerScan
        case repeatLastSpeech
        case toggleAutoRead
        case pauseOrResumeSpeech
    }

    @Published var keyboardRemoteDetected = false
    @Published var bleRemoteDetected = false
    @Published var mfiAccessoryDetected = false

    var onAction: ((ExternalAction) -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private let bluetoothManager: BluetoothManager

    init(bluetoothManager: BluetoothManager = BluetoothManager()) {
        self.bluetoothManager = bluetoothManager

        bluetoothManager.$bleRemoteDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detected in
                self?.bleRemoteDetected = detected
            }
            .store(in: &cancellables)

        bluetoothManager.$mfiAccessoryDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detected in
                self?.mfiAccessoryDetected = detected
            }
            .store(in: &cancellables)
    }

    func start() {
        bluetoothManager.start()
    }

    func handleKeyInput(_ input: String) {
        keyboardRemoteDetected = true

        switch input {
        case " ", "\r":
            onAction?(.triggerScan)

        case "r", UIKeyCommand.inputUpArrow:
            onAction?(.repeatLastSpeech)

        case "a":
            onAction?(.toggleAutoRead)

        case "p", UIKeyCommand.inputDownArrow:
            onAction?(.pauseOrResumeSpeech)

        default:
            break
        }
    }

    func triggerAction(_ action: ExternalAction) {
        onAction?(action)
    }
}
