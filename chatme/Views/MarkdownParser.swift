import Foundation

actor MarkdownParser {
    func parse(_ content: String) -> [MarkdownElement] {
        let lines = content.components(separatedBy: .newlines)
        var elements: [MarkdownElement] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmedLine.isEmpty {
                i += 1
                continue
            }

            // Parse different markdown elements
            if let heading = parseHeading(trimmedLine) {
                elements.append(heading)
                i += 1
            } else if let (codeBlock, nextIndex) = parseCodeBlock(lines, startIndex: i) {
                elements.append(codeBlock)
                i = nextIndex
            } else if isHorizontalRule(trimmedLine) {
                elements.append(MarkdownElement(type: .horizontalRule, content: ""))
                i += 1
            } else if let (list, nextIndex) = parseList(lines, startIndex: i) {
                elements.append(list)
                i = nextIndex
            } else if let (blockquote, nextIndex) = parseBlockquote(lines, startIndex: i) {
                elements.append(blockquote)
                i = nextIndex
            } else {
                // Regular paragraph
                let (paragraph, nextIndex) = parseParagraph(lines, startIndex: i)
                elements.append(paragraph)
                i = nextIndex
            }
        }

        return elements
    }

    private func parseHeading(_ line: String) -> MarkdownElement? {
        let headingPattern = #/^(#{1,6})\s+(.+)/#

        if let match = line.firstMatch(of: headingPattern) {
            let level = match.1.count
            let text = String(match.2)
            return MarkdownElement(type: .heading(level: level), content: text)
        }

        return nil
    }

    private func parseCodeBlock(_ lines: [String], startIndex: Int) -> (MarkdownElement, Int)? {
        let line = lines[startIndex]
        let codeBlockPattern = #/^```(\w+)?/#

        guard let match = line.firstMatch(of: codeBlockPattern) else {
            return nil
        }

        let language = match.1.map(String.init)
        var codeLines: [String] = []
        var i = startIndex + 1

        // Find the closing ```
        while i < lines.count {
            let currentLine = lines[i]
            if currentLine.trimmingCharacters(in: .whitespaces) == "```" {
                let code = codeLines.joined(separator: "\n")
                let element = MarkdownElement(type: .codeBlock(language: language), content: code)
                return (element, i + 1)
            }
            codeLines.append(currentLine)
            i += 1
        }

        // If no closing found, treat as incomplete code block (still render it)
        let code = codeLines.joined(separator: "\n")
        let element = MarkdownElement(type: .codeBlock(language: language), content: code)
        return (element, i)
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        // Match ---, ***, or ___ (with at least 3 characters)
        let hrPattern = #/^[-*_]{3,}$/#
        return line.firstMatch(of: hrPattern) != nil
    }

    private func parseList(_ lines: [String], startIndex: Int) -> (MarkdownElement, Int)? {
        let line = lines[startIndex]

        // Check for unordered list
        let unorderedPattern = #/^[-*+]\s+(.+)/#
        // Check for ordered list
        let orderedPattern = #/^\d+\.\s+(.+)/#

        let isUnordered = line.firstMatch(of: unorderedPattern) != nil
        let isOrdered = line.firstMatch(of: orderedPattern) != nil

        guard isUnordered || isOrdered else {
            return nil
        }

        var listItems: [MarkdownElement] = []
        var i = startIndex

        while i < lines.count {
            let currentLine = lines[i]

            if let match = currentLine.firstMatch(of: unorderedPattern), isUnordered {
                let itemText = String(match.1)
                listItems.append(MarkdownElement(type: .paragraph, content: itemText))
            } else if let match = currentLine.firstMatch(of: orderedPattern), isOrdered {
                let itemText = String(match.1)
                listItems.append(MarkdownElement(type: .paragraph, content: itemText))
            } else if currentLine.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty line might end the list, but check next line
                if i + 1 < lines.count {
                    let nextLine = lines[i + 1]
                    let nextIsUnordered = nextLine.firstMatch(of: unorderedPattern) != nil
                    let nextIsOrdered = nextLine.firstMatch(of: orderedPattern) != nil

                    if (isUnordered && nextIsUnordered) || (isOrdered && nextIsOrdered) {
                        i += 1
                        continue
                    }
                }
                break
            } else {
                // Not a list item, end the list
                break
            }

            i += 1
        }

        if !listItems.isEmpty {
            let element = MarkdownElement(type: .list(ordered: isOrdered), content: "", children: listItems)
            return (element, i)
        }

        return nil
    }

    private func parseBlockquote(_ lines: [String], startIndex: Int) -> (MarkdownElement, Int)? {
        let line = lines[startIndex]
        let blockquotePattern = #/^>\s*(.*)/#

        guard line.firstMatch(of: blockquotePattern) != nil else {
            return nil
        }

        var quoteLines: [String] = []
        var i = startIndex

        while i < lines.count {
            let currentLine = lines[i]

            if let quoteMatch = currentLine.firstMatch(of: blockquotePattern) {
                quoteLines.append(String(quoteMatch.1))
            } else if currentLine.trimmingCharacters(in: .whitespaces).isEmpty {
                // Check if next line continues the blockquote
                if i + 1 < lines.count && lines[i + 1].firstMatch(of: blockquotePattern) != nil {
                    quoteLines.append("") // Add empty line
                } else {
                    break
                }
            } else {
                break
            }

            i += 1
        }

        let content = quoteLines.joined(separator: "\n")
        let element = MarkdownElement(type: .blockquote, content: content)
        return (element, i)
    }

    private func parseParagraph(_ lines: [String], startIndex: Int) -> (MarkdownElement, Int) {
        var paragraphLines: [String] = []
        var i = startIndex

        while i < lines.count {
            let line = lines[i]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Stop at empty line or start of another element
            if trimmedLine.isEmpty {
                break
            }

            // Stop if we hit another markdown element
            if isMarkdownElement(trimmedLine) {
                break
            }

            paragraphLines.append(line)
            i += 1
        }

        let content = paragraphLines.joined(separator: "\n")
        let element = MarkdownElement(type: .paragraph, content: content)
        return (element, i)
    }

    private func isMarkdownElement(_ line: String) -> Bool {
        // Check if line starts a markdown element
        let patterns = [
            #/^#{1,6}\s+.+/#,  // Heading
            #/^```.*/#,         // Code block
            #/^[-*_]{3,}$/#,    // Horizontal rule
            #/^[-*+]\s+.+/#,    // Unordered list
            #/^\d+\.\s+.+/#,    // Ordered list
            #/^>\s*.*/#         // Blockquote
        ]

        return patterns.contains { line.firstMatch(of: $0) != nil }
    }
}

// MARK: - Enhanced Streaming Support
extension MarkdownParser {
    func parseStreaming(_ content: String, isComplete: Bool = false) async -> [MarkdownElement] {
        // For streaming content, we need to be more careful about parsing
        if !isComplete {
            let shouldParse = await shouldParseIncomplete(content)
            if !shouldParse {
                // Return a single paragraph element for incomplete content
                return [MarkdownElement(type: .paragraph, content: content)]
            }
        }

        return await parse(content)
    }

    private func shouldParseIncomplete(_ content: String) async -> Bool {
        // Only parse incomplete content if it clearly contains complete markdown elements

        // Look for complete code blocks
        let codeBlockStarts = await content.countMatches(of: #/^```/#)
        let codeBlockEnds = await content.countMatches(of: #/^```$/#)

        // If we have matching delimiters, it's likely safe to parse
        return (codeBlockStarts > 0 && codeBlockStarts == codeBlockEnds) ||
               content.hasSuffix("\n\n") // Clear paragraph breaks
    }
}

// MARK: - String Extension for Regex Matches
private extension String {
    func countMatches(of regex: Regex<Substring>) async -> Int {
        var count = 0
        var start = self.startIndex

        while start < self.endIndex {
            if let match = self[start...].firstMatch(of: regex) {
                count += 1
                start = match.range.upperBound
            } else {
                break
            }
        }

        return count
    }

    func matches(of regex: Regex<Substring>) -> [Regex<Substring>.Match] {
        var matches: [Regex<Substring>.Match] = []
        var start = self.startIndex

        while start < self.endIndex {
            if let match = self[start...].firstMatch(of: regex) {
                matches.append(match)
                start = match.range.upperBound
            } else {
                break
            }
        }

        return matches
    }
}
