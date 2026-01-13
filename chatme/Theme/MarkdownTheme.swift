import SwiftUI

// MARK: - Markdown Theme Design Tokens
enum MarkdownTheme {

    // MARK: - Colors
    enum Colors {
        // Background colors
        static let messageBackground = Color("MessageBackground", bundle: nil)
        static let codeBlockBackground = Color(light: Color(hex: "F6F8FA"), dark: Color(hex: "282C34"))
        static let codeBlockHeader = Color(light: Color(hex: "E5E7EB"), dark: Color(hex: "343541"))
        static let inlineCodeBackground = Color(light: Color(hex: "E8E8E8"), dark: Color(hex: "3A3A3A"))

        // Text colors
        static let primaryText = Color(light: Color(hex: "1A1A1A"), dark: Color(hex: "E5E5E5"))
        static let secondaryText = Color(light: Color(hex: "6B6B6B"), dark: Color(hex: "9A9A9A"))
        static let codeBlockHeaderText = Color(light: Color(hex: "6B6B6B"), dark: Color(hex: "8B8B8B"))
        static let codeText = Color(light: Color(hex: "1A1A1A"), dark: Color(hex: "ABB2BF"))

        // Accent colors
        static let link = Color(hex: "2563EB")
        static let blockquoteBorder = Color(light: Color(hex: "D1D5DB"), dark: Color(hex: "4B5563"))
        static let divider = Color(light: Color(hex: "E5E7EB"), dark: Color(hex: "374151"))

        // Interactive colors
        static let copyButtonHover = Color(light: Color(hex: "D1D5DB"), dark: Color(hex: "4B5563"))
        static let copyButtonSuccess = Color(hex: "22C55E")
    }

    // MARK: - Spacing (4px multiples)
    enum Spacing {
        static let paragraphGap: CGFloat = 16
        static let headingTopH1: CGFloat = 24
        static let headingTopH2: CGFloat = 20
        static let headingTopH3: CGFloat = 16
        static let headingBottom: CGFloat = 8
        static let codeBlockPadding: CGFloat = 16
        static let codeBlockHeaderPaddingH: CGFloat = 12
        static let codeBlockHeaderPaddingV: CGFloat = 8
        static let listItemGap: CGFloat = 8
        static let listIndent: CGFloat = 16
        static let inlineCodePaddingH: CGFloat = 6
        static let inlineCodePaddingV: CGFloat = 2
        static let blockquoteIndent: CGFloat = 16
        static let blockquoteBorderWidth: CGFloat = 3
        static let dividerVerticalPadding: CGFloat = 16
    }

    // MARK: - Typography
    enum Typography {
        // Body text
        static let bodyFont: Font = .system(size: 16)
        static let bodyLineSpacing: CGFloat = 6 // ~1.6 line height

        // Code
        static let codeFont: Font = .system(size: 14, design: .monospaced)
        static let codeLineSpacing: CGFloat = 4 // ~1.5 line height

        // Headings
        static let h1Font: Font = .system(size: 24, weight: .bold)
        static let h2Font: Font = .system(size: 20, weight: .bold)
        static let h3Font: Font = .system(size: 17, weight: .bold)
        static let headingLineSpacing: CGFloat = 2 // ~1.3 line height

        // Code block header
        static let codeHeaderFont: Font = .system(size: 12, weight: .medium)

        // Inline code
        static let inlineCodeFont: Font = .system(size: 14, design: .monospaced)
    }

    // MARK: - Corner Radius
    enum CornerRadius {
        static let codeBlock: CGFloat = 8
        static let inlineCode: CGFloat = 4
    }

    // MARK: - Highlightr Themes
    enum HighlightrTheme {
        static let light = "github"
        static let dark = "atom-one-dark"
    }
}

// MARK: - Color Helpers
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
    }
}
