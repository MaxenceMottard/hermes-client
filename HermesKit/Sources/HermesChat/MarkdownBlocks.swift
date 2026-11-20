/// A block of a message: prose (inline Markdown is rendered later) or a fenced code block.
public enum MarkdownBlock: Equatable, Sendable {
    case text(String)
    case code(language: String?, code: String)
}

/// Splits a message into prose and fenced code blocks. Inline Markdown is left in the prose.
///
/// A fence opens with three or more backticks or tildes and closes with the same marker alone on a line.
/// An unclosed fence runs to the end of the text, so a reply that is still streaming shows its code block.
public enum MarkdownParser {
    public static func blocks(in source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var prose: [String] = []
        var lines = source.components(separatedBy: "\n")[...]

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingBlankLines()
            if !text.isEmpty {
                blocks.append(.text(text))
            }
            prose.removeAll()
        }

        while let line = lines.popFirst() {
            guard let fence = openingFence(line) else {
                prose.append(line)
                continue
            }
            flushProse()
            var code: [String] = []
            while let inner = lines.popFirst() {
                if isClosingFence(inner, marker: fence.marker, length: fence.length) {
                    break
                }
                code.append(inner)
            }
            blocks.append(.code(language: fence.language, code: code.joined(separator: "\n")))
        }
        flushProse()
        return blocks
    }

    private struct Fence {
        let marker: Character
        let length: Int
        let language: String?
    }

    private static func openingFence(_ line: String) -> Fence? {
        let trimmed = line.trimmingLeadingSpaces()
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == marker }).count
        guard length >= 3 else { return nil }
        let info = trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces)
        if marker == "`", info.contains("`") {
            return nil
        }
        return Fence(marker: marker, length: length, language: info.isEmpty ? nil : info)
    }

    private static func isClosingFence(_ line: String, marker: Character, length: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= length && trimmed.allSatisfy { $0 == marker }
    }
}

extension String {
    fileprivate func trimmingLeadingSpaces() -> String {
        String(drop(while: { $0 == " " || $0 == "\t" }))
    }

    /// Removes leading and trailing blank lines, keeps the inner ones.
    fileprivate func trimmingBlankLines() -> String {
        var lines = components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
