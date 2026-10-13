import AppKit
import XCTest
@testable import NotepadKit

final class NotepadTests: XCTestCase {
    func testTextFileKeepsEncodingAndLineEndings() {
        let bytes = Data([0xFF, 0xFE]) + "가\r\n나".data(using: .utf16LittleEndian)!
        let file = TextFile(data: bytes)
        XCTAssertEqual(file, TextFile(text: "가\n나", encoding: .utf16le, lineEnding: .crlf))
        XCTAssertEqual(file.data(lossy: false), bytes)

        XCTAssertEqual(TextFile(data: Data("a\nb".utf8)), TextFile(text: "a\nb", encoding: .utf8, lineEnding: .lf))
        XCTAssertEqual(TextFile(data: Data([0xEF, 0xBB, 0xBF, 0x61])).encoding, .utf8bom)
        // not valid UTF-8, so it is read as ANSI
        XCTAssertEqual(TextFile(data: Data([0x63, 0x61, 0x66, 0xE9])).encoding, .ansi)
        XCTAssertNil(TextFile(text: "한글 ☃", encoding: .ansi).data(lossy: false))
    }

    func testHeaderFooterCodes() {
        XCTAssertEqual(formatHeaderFooter("&lA&&B&cPage &p&r&f", file: "a.txt", page: 3), ["A&B", "Page 3", "a.txt"])
        XCTAssertEqual(formatHeaderFooter("&f", file: "a.txt", page: 1), ["", "a.txt", ""])
    }

    func testMarkdownRoundTrip() {
        let markdown = """
        # Title

        Some **bold**, *italic* and ~~gone~~ text with a [link](https://example.com) and `code`.

        - one
        - two
            1. first
            2. second
        - [ ] todo
        - [x] done


        | A | B |
        | --- | --- |
        | 1 | 2 |

        ```swift
        let x = 1

        ```

        """
        let rendered = renderMarkdown(markdown, font: NSFont.userFixedPitchFont(ofSize: 12)!)
        XCTAssertFalse(rendered.string.contains("**"))
        XCTAssertEqual(serializeMarkdown(rendered), markdown)
    }
}
