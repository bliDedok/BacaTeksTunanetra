import UIKit

enum AccessibilityHelper {
    static func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    static func screenChanged(_ text: String? = nil) {
        UIAccessibility.post(notification: .screenChanged, argument: text)
    }

    static func hapticSuccess() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func hapticWarning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    static func hapticLight() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
