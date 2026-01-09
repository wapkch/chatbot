import UIKit
import SwiftUI

/// Utility class for providing haptic feedback throughout the app
class HapticFeedback {

    // MARK: - Impact Feedback
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func lightImpact() {
        impact(.light)
    }

    static func mediumImpact() {
        impact(.medium)
    }

    static func heavyImpact() {
        impact(.heavy)
    }

    // MARK: - Notification Feedback
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    static func success() {
        notification(.success)
    }

    static func warning() {
        notification(.warning)
    }

    static func error() {
        notification(.error)
    }

    // MARK: - Selection Feedback
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: - Context-specific feedback methods
    static func messageSent() {
        success()
    }

    static func messageReceived() {
        lightImpact()
    }

    static func buttonTap() {
        lightImpact()
    }

    static func swipeAction() {
        mediumImpact()
    }

    static func errorOccurred() {
        error()
    }

    static func textCopied() {
        success()
    }

    static func settingsChanged() {
        lightImpact()
    }

    static func longPress() {
        mediumImpact()
    }
}