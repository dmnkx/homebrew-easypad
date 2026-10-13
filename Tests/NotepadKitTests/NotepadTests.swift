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

    @MainActor func testTabsJoinAndLeaveTheirGroup() {
        let first = EditorWindowController(), second = EditorWindowController()
        second.join(first)
        XCTAssertTrue(first.group === second.group)
        XCTAssertEqual(first.group.tabs, [first, second])
        second.close()
        XCTAssertEqual(first.group.tabs, [first])
    }

    @MainActor func testTableGridPicksASizeAndInsertsIt() {
        Settings.register()
        let picker = TableGridPicker()
        let window = NSWindow(contentRect: picker.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = picker
        // squares are 18 wide with a 3 gap after a 14 left and 8 top margin: this is the third across, second down
        let point = NSPoint(x: 14 + 2 * 21 + 5, y: picker.frame.height - (8 + 21 + 5))
        picker.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
                                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        XCTAssertEqual(picker.picked.rows, 2)
        XCTAssertEqual(picker.picked.columns, 3)

        let document = Document()
        document.makeWindowControllers()
        document.editor?.insertPickedTable(picker)
        let rows = (document.editor?.source ?? "").split(separator: "\n").filter { $0.hasPrefix("|") }
        XCTAssertEqual(rows.first?.filter { $0 == "|" }.count, 4, "three columns")
    }

    @MainActor func testSavingCopiesOutsideImagesBesideTheDocument() throws {
        Settings.register()
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        let picture = root.appendingPathComponent("elsewhere/my pic.png"), note = root.appendingPathComponent("docs/note.md")
        try files.createDirectory(at: picture.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: picture)

        let document = Document()
        document.isMarkdown = true
        document.file.text = "![a](\(picture.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!))"
        document.makeWindowControllers()
        let saved = expectation(description: "saved")
        document.save(to: note, ofType: Document.markdown, for: .saveAsOperation) { error in
            XCTAssertNil(error)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 5)

        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "![a](note_Images/my%20pic.png)\r\n")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("docs/note_Images/my pic.png")), Data([1, 2, 3]))
        XCTAssertTrue(files.fileExists(atPath: picture.path), "the original stays where it was")
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
