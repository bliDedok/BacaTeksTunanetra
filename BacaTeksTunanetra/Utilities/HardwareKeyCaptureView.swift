import SwiftUI
import UIKit

struct HardwareKeyCaptureView: UIViewRepresentable {
    let onKeyInput: (String) -> Void

    func makeUIView(context: Context) -> KeyCaptureUIView {
        let view = KeyCaptureUIView()
        view.onKeyInput = onKeyInput
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: KeyCaptureUIView, context: Context) {
        DispatchQueue.main.async {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        }
    }
}

final class KeyCaptureUIView: UIView {
    var onKeyInput: ((String) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: " ", modifierFlags: [], action: #selector(handleCommand(_:))),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleCommand(_:))),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleCommand(_:))),
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(handleCommand(_:))),
            UIKeyCommand(input: "r", modifierFlags: [], action: #selector(handleCommand(_:))),
            UIKeyCommand(input: "a", modifierFlags: [], action: #selector(handleCommand(_:))),
            UIKeyCommand(input: "p", modifierFlags: [], action: #selector(handleCommand(_:)))
        ]
    }

    @objc private func handleCommand(_ sender: UIKeyCommand) {
        guard let input = sender.input else { return }
        onKeyInput?(input)
    }
}
