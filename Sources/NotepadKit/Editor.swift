import AppKit

private func statusLabel() -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.textColor = .secondaryLabelColor
    return label
}

/// Runs a small modal form of labeled text fields; true when confirmed.
func runForm(_ title: String, _ fields: [(String, NSTextField)], ok: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.addButton(withTitle: ok)
    alert.addButton(withTitle: L("Cancel"))
    let grid = NSGridView(views: fields.map { [NSTextField(labelWithString: $0.0) as NSView, $0.1] })
    for field in fields { field.1.widthAnchor.constraint(equalToConstant: 240).isActive = true }
    grid.frame.size = grid.fittingSize
    alert.accessoryView = grid
    alert.window.initialFirstResponder = fields.first?.1
    return alert.runModal() == .alertFirstButtonReturn
}

/// One tab: formatting toolbar, text view, status bar.
final class EditorWindowController: NSWindowController, NSTextViewDelegate, NSMenuItemValidation {
    let textView: NSTextView
    let scrollView = NSScrollView()
    let toolbar = NSStackView()
    let statusBar = NSStackView()
    private let position = statusLabel(), characters = statusLabel(), mode = statusLabel()
    private let zoomLabel = statusLabel(), lineEnding = statusLabel(), encoding = statusLabel()

    /// Markdown shown rendered (true) or as source (false). Plain text is never formatted.
    private(set) var formatted = false
    var baseFont = Settings.font

    var doc: Document? { document as? Document }
    let storage: NSTextStorage   // owns the text system; the text view alone would not keep it alive
    var bodyAttrs: Attrs { [.font: baseFont, .foregroundColor: NSColor.textColor] }

    /// The document text as it would be saved.
    var source: String { formatted ? serializeMarkdown(storage) : textView.string }

    var printable: NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: storage)
        copy.addAttribute(.foregroundColor, value: NSColor.black, range: NSRange(location: 0, length: copy.length))
        return copy
    }

    init() {
        // TextKit 1 on purpose: NSTextTable only works there
        let text = NSTextStorage(), layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        text.addLayoutManager(layout)
        storage = text
        layout.addTextContainer(container)
        textView = NSTextView(frame: .zero, textContainer: container)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        super.init(window: window)
        window.tabbingIdentifier = "Notepad"
        window.isRestorable = false   // Session restores tabs, including unsaved text
        window.center()
        window.setFrameAutosaveName("Editor")

        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 5
        scrollView.contentView.postsFrameChangedNotifications = true

        buildToolbar()
        statusBar.edgeInsets = NSEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        statusBar.spacing = 18
        statusBar.distribution = .gravityAreas
        statusBar.setHuggingPriority(.defaultHigh, for: .vertical)
        for view in [position, characters] { statusBar.addView(view, in: .leading) }
        for view in [mode, zoomLabel, lineEnding, encoding] { statusBar.addView(view, in: .trailing) }

        let root = NSStackView(views: [toolbar, scrollView, statusBar])
        root.orientation = .vertical
        root.distribution = .fill
        root.spacing = 0
        for view in root.arrangedSubviews {
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor).isActive = true
        }
        window.contentView = root

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(settingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(viewResized), name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        center.addObserver(self, selector: #selector(viewResized), name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildToolbar() {
        func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let button = NSButton(image: symbolImage(symbol), target: nil, action: action)
            button.bezelStyle = .texturedRounded
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
            return button
        }
        func pullDown(_ symbol: String, _ tip: String, _ items: [NSMenuItem]) -> NSPopUpButton {
            let popup = NSPopUpButton(frame: .zero, pullsDown: true)
            popup.bezelStyle = .texturedRounded
            let face = NSMenuItem()
            face.image = symbolImage(symbol)
            popup.menu?.addItem(face)
            items.forEach { popup.menu?.addItem($0) }
            popup.toolTip = tip
            popup.setAccessibilityLabel(tip)
            return popup
        }
        toolbar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        toolbar.spacing = 6
        toolbar.distribution = .gravityAreas
        toolbar.setHuggingPriority(.defaultHigh, for: .vertical)
        for view in [
            pullDown("textformat.size", L("Headings"), headingItems()),
            pullDown("list.bullet", L("Lists"), listItems()),
            button("bold", L("Bold"), #selector(toggleBold(_:))),
            button("italic", L("Italic"), #selector(toggleItalic(_:))),
            button("strikethrough", L("Strikethrough"), #selector(toggleStrikethrough(_:))),
            button("link", L("Link"), #selector(insertLink(_:))),
            pullDown("tablecells", L("Table"), tableItems()),
            pullDown("photo", L("Image"), imageItems()),
            button("eraser", L("Clear formatting"), #selector(clearFormatting(_:))),
        ] as [NSView] { toolbar.addView(view, in: .leading) }
    }

    // MARK: Content

    func load(formatted wanted: Bool? = nil) {
        guard let doc else { return }
        formatted = doc.isMarkdown && Settings.formatting && (wanted ?? true)
        show(doc.file.text)
        if doc.file.text.hasPrefix(".LOG") { textView.setSelectedRange(NSRange(location: storage.length, length: 0)) }
        applySettings()
        updateStatus()
    }

    private func show(_ source: String) {
        textView.isRichText = formatted
        let text = formatted ? renderMarkdown(source, font: baseFont, baseURL: doc?.fileURL) : NSAttributedString(string: source, attributes: bodyAttrs)
        storage.setAttributedString(text)
        if !formatted {
            textView.font = baseFont
            textView.textColor = .textColor
        }
        textView.typingAttributes = bodyAttrs
        doc?.undoManager?.removeAllActions()
    }

    func setFormatted(_ on: Bool) {
        guard on != formatted else { return }
        let text = source, selection = textView.selectedRange()
        formatted = on
        show(text)
        let location = min(selection.location, storage.length)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, storage.length - location)))
        updateStatus()
    }

    /// "Save as text file": drops the formatting, keeps the words.
    func convertToPlainText() {
        let text = textView.string
        formatted = false
        doc?.isMarkdown = false
        show(text)
        updateStatus()
    }

    // MARK: Settings

    @objc private func settingsChanged() { applySettings() }
    @objc private func viewResized() {
        applyWrap()
        updateStatus()
    }

    func applySettings() {
        toolbar.isHidden = !Settings.formatting
        statusBar.isHidden = !Settings.statusBar
        if !Settings.formatting && formatted { setFormatted(false) }
        let font = Settings.font
        if font != baseFont {
            let text = source
            baseFont = font
            show(text)
        }
        applyWrap()
        // Notepad only spell checks prose-like files by default
        let fileExtension = doc?.fileURL?.pathExtension.lowercased() ?? "txt"
        let spelling = Settings.spellCheck && ["txt", "md", "markdown", "srt", "lrc", "lic"].contains(fileExtension)
        if textView.isContinuousSpellCheckingEnabled != spelling { textView.isContinuousSpellCheckingEnabled = spelling }
        textView.isAutomaticSpellingCorrectionEnabled = spelling && Settings.autocorrect
    }

    private func applyWrap() {
        guard let container = textView.textContainer else { return }
        let wrap = Settings.wordWrap, width = scrollView.contentView.bounds.width
        if scrollView.hasHorizontalScroller == wrap { scrollView.hasHorizontalScroller = !wrap }
        textView.isHorizontallyResizable = !wrap
        container.widthTracksTextView = wrap
        if wrap {
            if textView.frame.width != width { textView.setFrameSize(NSSize(width: width, height: textView.frame.height)) }
            let inner = width - 2 * textView.textContainerInset.width
            if container.size.width != inner { container.size = NSSize(width: inner, height: CGFloat.greatestFiniteMagnitude) }
        } else if container.size.width != CGFloat.greatestFiniteMagnitude {
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    // MARK: Status bar

    private var zoom: Int { Int((scrollView.magnification * 100).rounded()) }

    func updateStatus() {
        guard let doc else { return }
        let text = textView.string as NSString, selection = textView.selectedRange()
        let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        // shortcut: counts lines from the top on every caret move, cache line starts if huge files feel slow
        var line = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: lineStart), options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
        position.stringValue = String(format: L(" Ln %d, Col %d"), line, selection.location - lineStart + 1)
        characters.stringValue = selection.length > 0
            ? String(format: L("%d of %d characters"), selection.length, text.length)
            : String(format: L("%d characters"), text.length)
        mode.stringValue = !doc.isMarkdown ? L("Plain text") : formatted ? L("Formatted") : L("Markdown syntax")
        zoomLabel.stringValue = "\(zoom)%"
        lineEnding.stringValue = doc.file.lineEnding.title
        encoding.stringValue = doc.file.encoding.title
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) { updateStatus() }
    func textViewDidChangeSelection(_ notification: Notification) { updateStatus() }
    func undoManager(for view: NSTextView) -> UndoManager? { doc?.undoManager }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let address = (link as? URL)?.absoluteString ?? "\(link)"
        let alert = NSAlert()
        alert.messageText = L("This link might be unsafe")
        alert.informativeText = L("You're about to open a link that hasn't been verified.\nOpening this link will take you outside of Notepad.\n\nOnly continue if you're sure this link is safe.") + "\n\n" + address
        alert.addButton(withTitle: L("Open link"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: address) { NSWorkspace.shared.open(url) }
        return true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Return after a heading starts a body paragraph, not another heading
        guard formatted, commandSelector == #selector(NSResponder.insertNewline(_:)), textView.typingAttributes[.mdHeading] != nil else { return false }
        textView.insertText("\n", replacementRange: textView.selectedRange())
        textView.typingAttributes = bodyAttrs
        return true
    }

    // MARK: Edit and View commands

    @objc func goToLine(_ sender: Any?) {
        let field = NSTextField(string: "")
        guard runForm(L("Go to line"), [(L("Line number"), field)], ok: L("Go to")) else { return }
        let text = textView.string as NSString
        var starts = [0]
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            starts.append(NSMaxRange(enclosing))
        }
        if starts.count > 1, text.length > 0, !CharacterSet.newlines.contains(UnicodeScalar(text.character(at: text.length - 1)) ?? " ") { starts.removeLast() }
        guard field.integerValue >= 1, field.integerValue <= starts.count else {
            let alert = NSAlert()
            alert.messageText = L("The line number is beyond the total number of lines")
            alert.runModal()
            return
        }
        let range = NSRange(location: starts[field.integerValue - 1], length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    @objc func insertTimeDate(_ sender: Any?) {
        textView.insertText(timeDateString(), replacementRange: textView.selectedRange())
    }

    @objc func searchWithBing(_ sender: Any?) {
        let selection = (textView.string as NSString).substring(with: textView.selectedRange())
        guard !selection.isEmpty, var components = URLComponents(string: "https://www.bing.com/search") else { return }
        components.queryItems = [URLQueryItem(name: "q", value: selection)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    @objc func toggleWordWrap(_ sender: Any?) { Settings.wordWrap.toggle() }
    @objc func toggleStatusBar(_ sender: Any?) { Settings.statusBar.toggle() }

    @objc func zoomText(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 0   // +1 in, -1 out, 0 reset
        scrollView.magnification = CGFloat(tag == 0 ? 100 : min(max(zoom + tag * 10, 10), 500)) / 100
        viewResized()
    }

    @objc func setMarkdownView(_ sender: Any?) { setFormatted((sender as? NSMenuItem)?.tag == 0) }

    // MARK: Tabs

    private var tabs: [NSWindow] { window?.tabbedWindows ?? [window].compactMap { $0 } }

    @objc func closeWindowTabs(_ sender: Any?) { tabs.forEach { $0.performClose(sender) } }
    @objc func closeOtherTabs(_ sender: Any?) { tabs.filter { $0 != window }.forEach { $0.performClose(sender) } }
    @objc func closeTabsToRight(_ sender: Any?) {
        guard let window, let index = tabs.firstIndex(of: window) else { return }
        tabs[(index + 1)...].forEach { $0.performClose(sender) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleWordWrap(_:)):
            item.state = Settings.wordWrap ? .on : .off
        case #selector(toggleStatusBar(_:)):
            item.state = Settings.statusBar ? .on : .off
        case #selector(setMarkdownView(_:)):
            let markdown = doc?.isMarkdown == true && Settings.formatting
            item.state = markdown && formatted == (item.tag == 0) ? .on : .off
            return markdown
        case #selector(searchWithBing(_:)):
            return textView.selectedRange().length > 0
        case #selector(tableOperation(_:)):
            return currentTable() != nil
        case #selector(removeLink(_:)):
            return formatted && currentLink() != nil
        case #selector(toggleTaskCheck(_:)):
            return formatted && [.task, .taskDone].contains(currentListKind())
        case #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleStrikethrough(_:)), #selector(insertLink(_:)),
             #selector(clearFormatting(_:)), #selector(setHeading(_:)), #selector(setList(_:)), #selector(insertTable(_:)), #selector(insertImage(_:)):
            return Settings.formatting
        default:
            break
        }
        return true
    }
}
