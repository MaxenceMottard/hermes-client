import Testing

@testable import HermesChat

@Suite("Markdown blocks")
struct MarkdownParserTests {
    @Test("plain text is one text block")
    func plainText() {
        #expect(MarkdownParser.blocks(in: "Hello\nworld") == [.text("Hello\nworld")])
    }

    @Test("an empty source has no blocks")
    func empty() {
        #expect(MarkdownParser.blocks(in: "").isEmpty)
        #expect(MarkdownParser.blocks(in: "  \n\n ").isEmpty)
    }

    @Test("prose, a fenced block with its language, then prose")
    func fencedBlockBetweenProse() {
        let source = "Run this:\n```swift\nprint(1)\nprint(2)\n```\nThen stop."
        #expect(
            MarkdownParser.blocks(in: source) == [
                .text("Run this:"),
                .code(language: "swift", code: "print(1)\nprint(2)"),
                .text("Then stop."),
            ])
    }

    @Test("a fence without a language has no language")
    func fenceWithoutLanguage() {
        #expect(MarkdownParser.blocks(in: "```\nx\n```") == [.code(language: nil, code: "x")])
    }

    @Test("tilde fences are recognised and close only with a tilde fence")
    func tildeFence() {
        #expect(MarkdownParser.blocks(in: "~~~\n```\n~~~") == [.code(language: nil, code: "```")])
    }

    @Test("an unclosed fence (reply still streaming) runs to the end of the text")
    func unclosedFence() {
        #expect(
            MarkdownParser.blocks(in: "Here:\n```py\nprint(") == [
                .text("Here:"),
                .code(language: "py", code: "print("),
            ])
    }

    @Test("inline code with backticks on the same line is not a fence")
    func inlineCodeIsNotFence() {
        #expect(MarkdownParser.blocks(in: "Use `ls` or ``ls -la``.") == [.text("Use `ls` or ``ls -la``.")])
    }

    @Test("the code block keeps its indentation and blank lines")
    func codeKeepsWhitespace() {
        let source = "```\n    indented\n\n  more\n```"
        #expect(MarkdownParser.blocks(in: source) == [.code(language: nil, code: "    indented\n\n  more")])
    }
}
