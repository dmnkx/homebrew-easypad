import AppKit
import UniformTypeIdentifiers

final class Document: NSDocument {
    static let plain = "public.plain-text"
    static let markdown = "net.daringfireball.markdown"

    var file = TextFile()
    /// True once the content is Markdown, either a .md file or text the user applied formatting to.
    var isMarkdown = false
    private var savePanel: NSSavePanel?
    private var encodingPopup: NSPopUpButton?

    var editor: EditorWindowController? { windowControllers.first as? EditorWindowController }

    override class var autosavesInPlace: Bool { false }
    override class var readableTypes: [String] { [plain, markdown] }
    override class var writableTypes: [String] { [plain, markdown] }
    override class func isNativeType(_ type: String) -> Bool { true }

    override func makeWindowControllers() {
        isMarkdown = isMarkdown || fileType == Document.markdown
        let controller = EditorWindowController()
        // "New window" and the "open files in a new window" setting keep this tab out of the current window
        let own = (NSDocumentController.shared as? DocumentController)?.opensNewWindow == true || (fileURL != nil && Settings.opensInNewWindow)
        if !own, let active = EditorWindowController.active { controller.join(active) }
        addWindowController(controller)
        controller.load()
    }

    override var displayName: String! {
        get { fileURL == nil ? L("Untitled") : super.displayName }
        set { super.displayName = newValue }
    }

    // MARK: Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        file = TextFile(data: data)
        isMarkdown = typeName == Document.markdown
        // a file starting with .LOG is a journal: every open appends a timestamp
        if file.text.hasPrefix(".LOG") { file.text += "\n" + timeDateString() + "\n" }
        editor?.load()
    }

    override func data(ofType typeName: String) throws -> Data {
        if let editor { file.text = editor.source }
        if let data = file.data(lossy: false) { return data }
        let alert = NSAlert()
        alert.messageText = L("This file contains characters in Unicode format which will be lost if you save this file as an ANSI encoded text file. To keep the Unicode information, click Cancel below and then select one of the Unicode options from the Encoding drop down list. Continue?")
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn, let data = file.data(lossy: true) else {
            throw CocoaError(.userCancelled)
        }
        return data
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        if saveOperation != .saveOperation, let popup = encodingPopup {
            file.encoding = TextEncoding(rawValue: popup.indexOfSelectedItem) ?? file.encoding
            encodingPopup = nil
        }
        if typeName == Document.markdown { editor?.gatherImages(for: url) }
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            if error == nil {
                self.isMarkdown = self.isMarkdown || typeName == Document.markdown
                self.editor?.applySettings()
                self.editor?.updateStatus()
            }
            completionHandler(error)
        }
    }

    /// Formatting cannot live in a .txt file, so saving one asks what to keep.
    override func save(_ sender: Any?) {
        guard isMarkdown, fileType == Document.plain, fileURL != nil, editor?.formatted == true else { return super.save(sender) }
        let alert = NSAlert()
        alert.messageText = L("Save as Markdown to keep formatting")
        alert.informativeText = L("This is a text file. To keep the current formatting, like bolding and headings, save it as a Markdown file (.md).")
        alert.addButton(withTitle: L("Save as Markdown file"))
        alert.addButton(withTitle: L("Save as text file"))
        alert.addButton(withTitle: L("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            fileType = Document.markdown
            saveAs(sender)
        case .alertSecondButtonReturn:
            editor?.convertToPlainText()
            super.save(sender)
        default:
            break
        }
    }

    // MARK: Save panel: file type and encoding, like Notepad's Save As dialog

    override var shouldRunSavePanelWithAccessoryView: Bool { false }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        typeName == Document.markdown ? "md" : "txt"
    }

    override var fileTypeFromLastRunSavePanel: String? {
        try? NSDocumentController.shared.typeForContents(of: savePanel?.url ?? URL(fileURLWithPath: "a.txt"))
    }

    override func prepareSavePanel(_ panel: NSSavePanel) -> Bool {
        let types = NSPopUpButton()
        types.addItems(withTitles: [L("Text documents (*.txt)"), L("Markdown file (*.md)"), L("All files")])
        types.selectItem(at: fileType == Document.markdown ? 1 : 0)
        types.target = self
        types.action = #selector(saveTypePicked(_:))
        let encodings = NSPopUpButton()
        encodings.addItems(withTitles: TextEncoding.allCases.map(\.title))
        encodings.selectItem(at: file.encoding.rawValue)

        let row = NSStackView(views: [types, NSTextField(labelWithString: L("Encoding:")), encodings])
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        row.frame.size = row.fittingSize
        panel.accessoryView = row
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = true
        savePanel = panel
        encodingPopup = encodings
        saveTypePicked(types)
        return true
    }

    @objc private func saveTypePicked(_ sender: NSPopUpButton) {
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        let choices: [[UTType]] = [[.plainText], [markdownType], []]
        savePanel?.allowedContentTypes = choices[sender.indexOfSelectedItem]
    }

    // MARK: Printing

    override func preparePageLayout(_ pageLayout: NSPageLayout) -> Bool {
        func field(_ key: String) -> NSTextField {
            let field = NSTextField(string: "")
            field.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + key, options: [.continuouslyUpdatesValue: true])
            field.widthAnchor.constraint(equalToConstant: 160).isActive = true
            return field
        }
        let rows: [(String, String)] = [
            (L("Header:"), "header"), (L("Footer:"), "footer"),
            (L("Left:") + " (mm)", "marginLeft"), (L("Right:") + " (mm)", "marginRight"),
            (L("Top:") + " (mm)", "marginTop"), (L("Bottom:") + " (mm)", "marginBottom"),
        ]
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), field($0.1)] })
        grid.frame.size = grid.fittingSize
        let controller = NSViewController()
        controller.title = L("Notepad")
        controller.view = grid
        pageLayout.addAccessoryController(controller)
        return true
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        func points(_ key: String) -> CGFloat { CGFloat(UserDefaults.standard.double(forKey: key)) * 72 / 25.4 }
        info.leftMargin = points("marginLeft")
        info.rightMargin = points("marginRight")
        info.topMargin = points("marginTop")
        info.bottomMargin = points("marginBottom")
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.dictionary().setObject(true, forKey: NSPrintInfo.AttributeKey.headerAndFooter.rawValue as NSString)

        let width = max(info.paperSize.width - info.leftMargin - info.rightMargin, 72)
        let view = PrintView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.name = displayName
        view.textStorage?.setAttributedString(editor?.printable ?? NSAttributedString(string: file.text))
        return NSPrintOperation(view: view, printInfo: info)
    }

    // MARK: Session ("continue previous session")

    var sessionItem: SessionItem? {
        guard let editor else { return nil }
        let text = editor.source
        if fileURL == nil && text.isEmpty { return nil }
        return SessionItem(path: fileURL?.path, text: isDocumentEdited || fileURL == nil ? text : nil,
                           encoding: file.encoding, lineEnding: file.lineEnding, markdown: isMarkdown, formatted: editor.formatted)
    }

    /// Puts back text that was never saved when the last session ended.
    func restoreSession(_ item: SessionItem) {
        guard let text = item.text else { return }
        file = TextFile(text: text, encoding: item.encoding, lineEnding: item.lineEnding)
        isMarkdown = item.markdown
        if fileURL == nil { fileType = isMarkdown ? Document.markdown : Document.plain }   // untitled tabs start as Markdown
        editor?.load(formatted: item.formatted)
        updateChangeCount(.changeDone)
    }
}

/// Prints the text with Notepad's page header and footer.
final class PrintView: NSTextView {
    var name = ""

    private func line(_ key: String) -> NSAttributedString {
        let page = NSPrintOperation.current?.currentPage ?? 1
        let parts = formatHeaderFooter(UserDefaults.standard.string(forKey: key) ?? "", file: name, page: page)
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .center, location: bounds.width / 2), NSTextTab(textAlignment: .right, location: bounds.width)]
        return NSAttributedString(string: parts.joined(separator: "\t"),
                                  attributes: [.paragraphStyle: style, .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black])
    }

    override var pageHeader: NSAttributedString { line("header") }
    override var pageFooter: NSAttributedString { line("footer") }
}

final class DocumentController: NSDocumentController {
    var opensNewWindow = false

    override var defaultType: String? { Document.markdown }
    override func documentClass(forType typeName: String) -> AnyClass? { Document.self }

    override func typeForContents(of url: URL) throws -> String {
        ["md", "markdown"].contains(url.pathExtension.lowercased()) ? Document.markdown : Document.plain
    }

    // Notepad opens any file, whatever its extension
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void) {
        super.beginOpenPanel(openPanel, forTypes: nil, completionHandler: completionHandler)
    }

    override var maximumRecentDocumentCount: Int { Settings.recentFiles ? super.maximumRecentDocumentCount : 0 }

    override func reviewUnsavedDocuments(withAlertTitle title: String?, cancellable: Bool, delegate: Any?, didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        Session.saveForQuit()
        super.reviewUnsavedDocuments(withAlertTitle: title, cancellable: cancellable, delegate: delegate, didReviewAllSelector: didReviewAllSelector, contextInfo: contextInfo)
    }

    @objc func newWindowDocument(_ sender: Any?) {
        opensNewWindow = true
        newDocument(sender)
        opensNewWindow = false
    }

    @objc func newTextDocument(_ sender: Any?) {
        guard let document = try? makeUntitledDocument(ofType: Document.plain) else { return }
        addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
    }
}

struct SessionItem: Codable {
    var path: String?
    var text: String?
    var encoding: TextEncoding
    var lineEnding: LineEnding
    var markdown: Bool
    var formatted: Bool
}

/// Notepad keeps open tabs and unsaved text across launches without touching the files.
enum Session {
    static var url: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Notepad")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("session.json")
    }

    private static var quitting = false

    static func save() {
        guard !quitting else { return }   // AppKit closes the documents while quitting; a later save would write an empty session
        let items = NSDocumentController.shared.documents.compactMap { ($0 as? Document)?.sessionItem }
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    /// With the session kept, quitting must not ask about unsaved changes.
    static func saveForQuit() {
        guard !Settings.startNew else { return }
        save()
        quitting = true
        NSDocumentController.shared.documents.forEach { $0.updateChangeCount(.changeCleared) }
    }

    static func restore() -> Bool {
        guard let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([SessionItem].self, from: data), !items.isEmpty else { return false }
        let controller = NSDocumentController.shared
        var restored = false
        for item in items {
            if let path = item.path, FileManager.default.fileExists(atPath: path) {
                // made by hand: openDocument finishes later, which would put file tabs after the unsaved ones
                let url = URL(fileURLWithPath: path)
                guard let type = try? controller.typeForContents(of: url),
                      let document = try? controller.makeDocument(withContentsOf: url, ofType: type) as? Document else { continue }
                controller.addDocument(document)
                document.makeWindowControllers()
                document.showWindows()
                document.restoreSession(item)
                restored = true
            } else if item.text != nil, let document = (try? controller.openUntitledDocumentAndDisplay(true)) as? Document {
                document.restoreSession(item)
                restored = true
            }
        }
        return restored
    }
}
