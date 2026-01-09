import SwiftUI
import UIKit

extension View {
    /// Hide keyboard when tapping outside
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Dismiss keyboard on tap
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            hideKeyboard()
        }
    }

    /// Handle keyboard toolbar
    func keyboardToolbar() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    hideKeyboard()
                }
            }
        }
    }

    /// Smooth animation for loading states
    func loadingAnimation(_ isLoading: Bool) -> some View {
        self
            .opacity(isLoading ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isLoading)
    }

    /// Custom context menu
    func customContextMenu<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        self.contextMenu {
            content()
        }
    }

    /// Haptic feedback on tap
    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.onTapGesture {
            HapticFeedback.impact(style)
        }
    }
}

// MARK: - Keyboard handling utilities
extension View {
    /// Monitor keyboard height changes
    func keyboardAware() -> some View {
        self.modifier(KeyboardAwareModifier())
    }
}

struct KeyboardAwareModifier: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight)
            .animation(.easeInOut(duration: 0.3), value: keyboardHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    keyboardHeight = frame.height
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
    }
}

// MARK: - Color extensions for better theming
extension Color {
    static let chatBackground = Color(.systemBackground)
    static let messageBubbleUser = Color(.systemBlue)
    static let messageBubbleAssistant = Color(.systemGray6)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let inputBackground = Color(.systemGray6)
}

// MARK: - Font extensions
extension Font {
    static let messageFont = Font.system(size: 16, weight: .regular, design: .default)
    static let timestampFont = Font.system(size: 12, weight: .regular, design: .default)
    static let inputFont = Font.system(size: 16, weight: .regular, design: .default)
}