import SwiftUI
import Foundation

/// A simple, efficient markdown renderer optimized for streaming content
struct SmartMarkdownRenderer: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(parseContent().enumerated()), id: \.offset) { _, element in
                element
            }
        }
    }

    private func parseContent() -> [AnyView] {
        let lines = content.components(separatedBy: "\n")
        var views: [AnyView] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for table
            if isTableRow(trimmed) {
                let (tableView, nextIndex) = parseTable(lines, startIndex: i)
                if let tableView = tableView {
                    views.append(tableView)
                    i = nextIndex
                    continue
                }
            }

            if trimmed.isEmpty {
                views.append(AnyView(Spacer().frame(height: 8)))
            } else if let view = parseHeading(trimmed) {
                views.append(view)
            } else if let view = parseBulletPoint(trimmed) {
                views.append(view)
            } else if let view = parseNumberedList(trimmed) {
                views.append(view)
            } else {
                views.append(AnyView(
                    Text(processInlineFormatting(trimmed))
                        .font(MarkdownTheme.Typography.bodyFont)
                        .foregroundColor(MarkdownTheme.Colors.primaryText)
                ))
            }

            i += 1
        }

        return views
    }

    // MARK: - Table Detection
    private func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|")
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Match patterns like |---|---|---| or |:---:|:---:|
        // The line should contain only |, -, :, and spaces
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else {
            return false
        }

        // Remove | and check if remaining is only -, :, spaces, and |
        let content = trimmed.dropFirst().dropLast()
        let allowedChars = CharacterSet(charactersIn: "-:|  ")
        let contentChars = CharacterSet(charactersIn: String(content))

        return contentChars.isSubset(of: allowedChars) && content.contains("-")
    }

    private func parseTable(_ lines: [String], startIndex: Int) -> (AnyView?, Int) {
        var tableRows: [[String]] = []
        var i = startIndex
        var hasHeader = false

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if isTableSeparator(line) {
                // This is the separator row after header
                hasHeader = true
                i += 1
                continue
            }

            if isTableRow(line) {
                let cells = parseTableRow(line)
                if !cells.isEmpty {
                    tableRows.append(cells)
                }
                i += 1
            } else {
                break
            }
        }

        if tableRows.isEmpty {
            return (nil, startIndex)
        }

        let tableView = AnyView(
            MarkdownTableView(rows: tableRows, hasHeader: hasHeader)
                .padding(.vertical, 8)
        )

        return (tableView, i)
    }

    private func parseTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)

        // Remove leading and trailing |
        if trimmed.hasPrefix("|") {
            trimmed = String(trimmed.dropFirst())
        }
        if trimmed.hasSuffix("|") {
            trimmed = String(trimmed.dropLast())
        }

        // Split by | and trim each cell
        let cells = trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        return cells
    }

    // MARK: - Heading
    private func parseHeading(_ line: String) -> AnyView? {
        if line.hasPrefix("### ") {
            return AnyView(
                Text(processInlineFormatting(String(line.dropFirst(4))))
                    .font(MarkdownTheme.Typography.h3Font)
                    .foregroundColor(MarkdownTheme.Colors.primaryText)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            )
        } else if line.hasPrefix("## ") {
            return AnyView(
                Text(processInlineFormatting(String(line.dropFirst(3))))
                    .font(MarkdownTheme.Typography.h2Font)
                    .foregroundColor(MarkdownTheme.Colors.primaryText)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            )
        } else if line.hasPrefix("# ") {
            return AnyView(
                Text(processInlineFormatting(String(line.dropFirst(2))))
                    .font(MarkdownTheme.Typography.h1Font)
                    .foregroundColor(MarkdownTheme.Colors.primaryText)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
            )
        }
        return nil
    }

    // MARK: - Bullet Point
    private func parseBulletPoint(_ line: String) -> AnyView? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            let text = String(line.dropFirst(2))
            return AnyView(
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .font(MarkdownTheme.Typography.bodyFont)
                        .foregroundColor(MarkdownTheme.Colors.secondaryText)
                    Text(processInlineFormatting(text))
                        .font(MarkdownTheme.Typography.bodyFont)
                        .foregroundColor(MarkdownTheme.Colors.primaryText)
                }
                .padding(.leading, 8)
            )
        }
        return nil
    }

    // MARK: - Numbered List
    private func parseNumberedList(_ line: String) -> AnyView? {
        guard let regex = try? NSRegularExpression(pattern: "^(\\d+)\\.\\s+(.+)$", options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 3,
              let numberRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let number = String(line[numberRange])
        let text = String(line[textRange])

        return AnyView(
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(MarkdownTheme.Typography.bodyFont)
                    .foregroundColor(MarkdownTheme.Colors.secondaryText)
                    .frame(minWidth: 20, alignment: .trailing)
                Text(processInlineFormatting(text))
                    .font(MarkdownTheme.Typography.bodyFont)
                    .foregroundColor(MarkdownTheme.Colors.primaryText)
            }
            .padding(.leading, 8)
        )
    }

    // MARK: - Inline Formatting
    func processInlineFormatting(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result = processBold(result)
        result = processInlineCode(result)
        return result
    }

    private func processBold(_ text: AttributedString) -> AttributedString {
        var result = text
        let stringContent = String(result.characters)

        guard let regex = try? NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*", options: []) else {
            return result
        }

        let nsRange = NSRange(stringContent.startIndex..., in: stringContent)
        let matches = regex.matches(in: stringContent, options: [], range: nsRange)

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range, in: stringContent),
                  let captureRange = Range(match.range(at: 1), in: stringContent) else {
                continue
            }

            let matchedText = String(stringContent[captureRange])
            let startOffset = stringContent.distance(from: stringContent.startIndex, to: fullRange.lowerBound)
            let length = stringContent.distance(from: fullRange.lowerBound, to: fullRange.upperBound)

            let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
            let attrEnd = result.index(attrStart, offsetByCharacters: length)

            var attrs = AttributeContainer()
            attrs.font = Font.system(size: 16, weight: .bold)
            result.replaceSubrange(attrStart..<attrEnd, with: AttributedString(matchedText, attributes: attrs))
        }

        return result
    }

    private func processInlineCode(_ text: AttributedString) -> AttributedString {
        var result = text
        let stringContent = String(result.characters)

        guard let regex = try? NSRegularExpression(pattern: "`([^`]+)`", options: []) else {
            return result
        }

        let nsRange = NSRange(stringContent.startIndex..., in: stringContent)
        let matches = regex.matches(in: stringContent, options: [], range: nsRange)

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range, in: stringContent),
                  let captureRange = Range(match.range(at: 1), in: stringContent) else {
                continue
            }

            let matchedText = String(stringContent[captureRange])
            let startOffset = stringContent.distance(from: stringContent.startIndex, to: fullRange.lowerBound)
            let length = stringContent.distance(from: fullRange.lowerBound, to: fullRange.upperBound)

            let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
            let attrEnd = result.index(attrStart, offsetByCharacters: length)

            var attrs = AttributeContainer()
            attrs.font = MarkdownTheme.Typography.inlineCodeFont
            attrs.backgroundColor = MarkdownTheme.Colors.inlineCodeBackground
            result.replaceSubrange(attrStart..<attrEnd, with: AttributedString(matchedText, attributes: attrs))
        }

        return result
    }
}

// MARK: - Table View
struct MarkdownTableView: View {
    let rows: [[String]]
    let hasHeader: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            tableCellView(cell, isHeader: hasHeader && rowIndex == 0)
                                .frame(minWidth: 80)

                            if colIndex < row.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(
                        hasHeader && rowIndex == 0
                            ? MarkdownTheme.Colors.codeBlockHeader
                            : (rowIndex % 2 == 0 ? Color.clear : MarkdownTheme.Colors.codeBlockBackground.opacity(0.3))
                    )

                    if rowIndex < rows.count - 1 {
                        Divider()
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MarkdownTheme.Colors.divider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func tableCellView(_ text: String, isHeader: Bool) -> some View {
        Text(processInlineFormatting(text))
            .font(isHeader ? Font.system(size: 14, weight: .semibold) : MarkdownTheme.Typography.bodyFont)
            .foregroundColor(MarkdownTheme.Colors.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func processInlineFormatting(_ text: String) -> AttributedString {
        var result = AttributedString(text)

        // Process bold
        let stringContent = String(result.characters)
        guard let regex = try? NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*", options: []) else {
            return result
        }

        let nsRange = NSRange(stringContent.startIndex..., in: stringContent)
        let matches = regex.matches(in: stringContent, options: [], range: nsRange)

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range, in: stringContent),
                  let captureRange = Range(match.range(at: 1), in: stringContent) else {
                continue
            }

            let matchedText = String(stringContent[captureRange])
            let startOffset = stringContent.distance(from: stringContent.startIndex, to: fullRange.lowerBound)
            let length = stringContent.distance(from: fullRange.lowerBound, to: fullRange.upperBound)

            let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
            let attrEnd = result.index(attrStart, offsetByCharacters: length)

            var attrs = AttributeContainer()
            attrs.font = Font.system(size: 14, weight: .bold)
            result.replaceSubrange(attrStart..<attrEnd, with: AttributedString(matchedText, attributes: attrs))
        }

        return result
    }
}

// MARK: - Preview
#Preview("Smart Markdown") {
    ScrollView {
        SmartMarkdownRenderer(content: """
        # 标题一

        ## 各自优势

        | 维度 | Apple | Google |
        |------|-------|--------|
        | **核心优势** | 硬件生态整合 | 软件服务广度 |
        | **商业模式** | 硬件销售为主 | 广告收入为主 |
        | **用户理念** | 精品化、简洁 | 开放化、个性化 |

        **Google 优势：**
        - 搜索和 AI 技术领先
        - 开放平台吸引更多合作伙伴

        1. 第一项
        2. 第二项
        """)
        .padding()
    }
}

#Preview("Table Only") {
    ScrollView {
        SmartMarkdownRenderer(content: """
        | Name | Age | City |
        |------|-----|------|
        | Alice | 25 | Beijing |
        | Bob | 30 | Shanghai |
        """)
        .padding()
    }
}
