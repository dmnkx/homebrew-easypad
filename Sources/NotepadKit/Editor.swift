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

/// The tabs of one window. Each tab is its own NSWindow and only the selected one is on screen,
/// so the tab strip can sit in the title bar like Notepad's (macOS window tabs always add a row below it).
final class TabGroup {
    var tabs: [EditorWindowController] = []
    var closing: [EditorWindowController] = []
    var shown: EditorWindowController? { tabs.first { $0.window?.isVisible == true } }
}

/// A filled bar: the tab strip itself, or one tab on it (top corners rounded, bottom flush with the menu row).
private final class TabView: NSStackView {
    var fill = NSColor.clear
    var radius: CGFloat = 0
    /// Left unpainted, so the selected tab shows the very backdrop the menu row has; no painted color matches it in every window state.
    weak var cutout: TabView?

    private func shape(_ frame: NSRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: frame.minX, y: frame.minY - radius, width: frame.width, height: frame.height + radius), xRadius: radius, yRadius: radius)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = shape(bounds, radius)
        if let cutout { path.append(shape(cutout.frame, cutout.radius)) }
        path.windingRule = .evenOdd
        fill.setFill()
        path.fill()
    }

    override func layout() {
        super.layout()
        needsDisplay = true   // the cutout follows the tab as it moves
    }
}

/// One tab: tab strip, formatting toolbar, text view, status bar.
final class EditorWindowController: NSWindowController, NSTextViewDelegate, NSMenuItemValidation, NSWindowDelegate {
    /// The tab new documents join.
    static weak var active: EditorWindowController?
    private(set) var group = TabGroup()
    private let tabStrip = TabView()
    let textView: NSTextView
    let scrollView = NSScrollView()
    let toolbar = NSStackView()
    let statusBar = NSStackView()
    private var formatControls: [NSView] = []
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
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
        super.init(window: window)
        group.tabs = [self]
        window.delegate = self
        window.tabbingMode = .disallowed
        window.animationBehavior = .none   // switching tabs swaps windows; the open/close zoom would show
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar()   // empty, only there to make the title bar tall enough for roomy tabs
        window.toolbarStyle = .unifiedCompact
        window.isRestorable = false   // Session restores tabs, including unsaved text
        window.center()
        window.setFrameAutosaveName("Editor")

        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 10)
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
        statusBar.edgeInsets = NSEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        statusBar.spacing = 24
        statusBar.distribution = .gravityAreas
        statusBar.setHuggingPriority(.defaultHigh, for: .vertical)
        for view in [position, characters] { statusBar.addView(view, in: .leading) }
        for view in [mode, zoomLabel, lineEnding, encoding] { statusBar.addView(view, in: .trailing) }

        tabStrip.edgeInsets = NSEdgeInsets(top: 0, left: 78, bottom: 0, right: 8)   // clears the close/minimize/zoom buttons
        tabStrip.spacing = 2
        tabStrip.alignment = .bottom
        tabStrip.fill = NSColor.black.withAlphaComponent(0.1)   // darker than the menu row, so the selected tab reads as part of it
        let root = NSStackView(views: [tabStrip, toolbar, scrollView, statusBar])
        root.orientation = .vertical
        root.distribution = .fill
        root.spacing = 0
        for view in root.arrangedSubviews {
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor).isActive = true
        }
        window.contentView = root
        if let guide = window.contentLayoutGuide as? NSLayoutGuide { tabStrip.bottomAnchor.constraint(equalTo: guide.topAnchor).isActive = true }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(settingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(viewResized), name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        center.addObserver(self, selector: #selector(viewResized), name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildToolbar() {
        // menu row text and icons are 1.2 times the system size
        let size = NSFont.systemFontSize * 1.2
        func icon(_ symbol: String) -> NSImage {
            symbolImage(symbol).withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .regular)) ?? symbolImage(symbol)
        }
        func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let button = NSButton(image: icon(symbol), target: nil, action: action)
            button.isBordered = false
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
            return button
        }
        func pullDown(_ symbol: String, _ tip: String, _ items: [NSMenuItem]) -> NSPopUpButton {
            let popup = NSPopUpButton(frame: .zero, pullsDown: true)
            popup.isBordered = false
            let face = NSMenuItem()
            face.title = ""
            face.image = icon(symbol)
            popup.menu?.addItem(face)
            items.forEach { popup.menu?.addItem($0) }
            popup.toolTip = tip
            popup.setAccessibilityLabel(tip)
            return popup
        }
        toolbar.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        toolbar.spacing = 16
        toolbar.distribution = .gravityAreas
        toolbar.setHuggingPriority(.defaultHigh, for: .vertical)
        // Notepad keeps File/Edit/View inside the window; these open the same menus as the menu bar
        for (index, title) in [L("File"), L("Edit"), L("View")].enumerated() {
            let menu = NSButton(title: title, target: self, action: #selector(showMainMenu(_:)))
            menu.isBordered = false
            menu.font = .systemFont(ofSize: size)
            menu.tag = index + 1
            toolbar.addView(menu, in: .leading)
        }
        formatControls = [
            pullDown("textformat.size", L("Headings"), headingItems()),
            pullDown("list.bullet", L("Lists"), listItems()),
            button("bold", L("Bold"), #selector(toggleBold(_:))),
            button("italic", L("Italic"), #selector(toggleItalic(_:))),
            button("strikethrough", L("Strikethrough"), #selector(toggleStrikethrough(_:))),
            button("link", L("Link"), #selector(insertLink(_:))),
            pullDown("tablecells", L("Table"), tableItems()),
            pullDown("photo", L("Image"), imageItems()),
            button("eraser", L("Clear formatting"), #selector(clearFormatting(_:))),
        ]
        formatControls.forEach { toolbar.addView($0, in: .leading) }
        toolbar.addView(button("gearshape", L("Settings"), #selector(AppDelegate.showSettings(_:))), in: .trailing)
    }

    @objc private func showMainMenu(_ sender: NSButton) {
        NSApp.mainMenu?.item(at: sender.tag)?.submenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
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
        guard doc != nil else { return }   // the settings tab has no editor to configure
        formatControls.forEach { $0.isHidden = !Settings.formatting }
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
        alert.informativeText = L("You're about to open a link that hasn't been verified.\nOpening this link will take you outside of EasyPad.\n\nOnly continue if you're sure this link is safe.") + "\n\n" + address
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

    /// Turns this tab into the settings page; it has no document.
    func showSettings() {
        guard let window, let root = window.contentView as? NSStackView else { return }
        [toolbar, scrollView, statusBar].forEach { $0.isHidden = true }
        let page = SettingsView(), scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = page
        root.addArrangedSubview(scroll)
        page.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            page.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), page.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
        ])
        window.title = L("Settings")
        window.makeFirstResponder(nil)
    }

    func join(_ other: EditorWindowController) {
        group = other.group
        group.tabs.append(self)
    }

    /// Shows this tab in place of the one its window was showing.
    func select() {
        guard let window else { return }
        let others = group.tabs.filter { $0 !== self }
        if let shown = others.first(where: { $0.window?.isVisible == true })?.window { window.setFrame(shown.frame, display: false) }
        rebuildTabs()
        window.isExcludedFromWindowsMenu = false
        window.makeKeyAndOrderFront(nil)
        for other in others {
            other.window?.isExcludedFromWindowsMenu = true
            other.window?.orderOut(nil)
        }
        Self.active = self
    }

    override func showWindow(_ sender: Any?) { select() }
    func windowDidBecomeKey(_ notification: Notification) { Self.active = self }

    func windowWillClose(_ notification: Notification) {
        guard let window, let index = group.tabs.firstIndex(of: self) else { return }
        group.tabs.remove(at: index)
        if Self.active === self { Self.active = nil }
        guard window.isVisible, !group.tabs.isEmpty else { group.shown?.rebuildTabs(); return }
        let next = group.tabs[min(index, group.tabs.count - 1)]
        next.window?.setFrame(window.frame, display: false)
        next.select()
    }

    override func setDocumentEdited(_ dirtyFlag: Bool) {
        let changed = dirtyFlag != window?.isDocumentEdited
        super.setDocumentEdited(dirtyFlag)
        if changed { group.shown?.rebuildTabs() }
    }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        group.shown?.rebuildTabs()
    }

    // shortcut: tabs shrink but never scroll and cannot be dragged, add both if people keep dozens of tabs open
    func rebuildTabs() {
        tabStrip.views.forEach { tabStrip.removeView($0) }
        var first: NSView?, firstTitle: NSView?
        for tab in group.tabs {
            let title = NSButton(title: tab.doc?.displayName ?? L("Settings"), target: tab, action: #selector(selectTab(_:)))
            title.isBordered = false
            title.alignment = .left
            title.contentTintColor = .labelColor
            title.lineBreakMode = .byTruncatingTail
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            title.setContentHuggingPriority(.defaultLow, for: .horizontal)
            // like Notepad, a dot replaces the close mark while the tab has unsaved changes
            let close = NSButton(image: symbolImage(tab.doc?.isDocumentEdited == true ? "circle.fill" : "xmark"), target: tab, action: #selector(closeTab(_:)))
            close.isBordered = false
            close.controlSize = .small
            close.setContentHuggingPriority(.required, for: .horizontal)   // or the dot stretches and drifts off the tab's right edge
            close.setAccessibilityLabel(L("Close tab"))
            let view = TabView(views: [title, close])
            view.distribution = .fill
            view.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 12)
            view.radius = 8
            view.clipsToBounds = true
            if tab === self { tabStrip.cutout = view }
            view.alphaValue = tab === self ? 1 : 0.55
            view.menu = NSMenu()
            for (name, action) in [("New tab", #selector(newTab(_:))), ("Close tab", #selector(closeTab(_:))),
                                   ("Close other tabs", #selector(closeOtherTabs(_:))), ("Close tabs to the right", #selector(closeTabsToRight(_:)))] {
                view.menu?.addItem(menuItem(L(name), action, target: tab))
            }
            tabStrip.addView(view, in: .leading)
            let width = view.widthAnchor.constraint(equalToConstant: 200)
            width.priority = .defaultLow
            NSLayoutConstraint.activate([width, view.widthAnchor.constraint(lessThanOrEqualToConstant: 200)])
            if let first { view.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true }
            first = first ?? view
            firstTitle = firstTitle ?? title
        }
        let add = NSButton(image: symbolImage("plus"), target: self, action: #selector(newTab(_:)))
        add.isBordered = false
        add.toolTip = L("New tab")
        add.setAccessibilityLabel(L("New tab"))
        let addTab = TabView(views: [add])   // same insets and height as a tab, so the plus sits level with the titles
        addTab.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 4)
        add.setContentHuggingPriority(.defaultLow, for: .vertical)
        tabStrip.addView(addTab, in: .leading)
        if let firstTitle { add.heightAnchor.constraint(equalTo: firstTitle.heightAnchor).isActive = true }
    }

    @objc private func selectTab(_ sender: Any?) { select() }
    @objc private func newTab(_ sender: Any?) { NSDocumentController.shared.newDocument(sender) }
    @objc private func closeTab(_ sender: Any?) { close(tabs: [self]) }

    @objc func cycleTab(_ sender: NSMenuItem) {
        guard let index = group.tabs.firstIndex(of: self) else { return }
        group.tabs[(index + sender.tag + group.tabs.count) % group.tabs.count].select()
    }

    /// Closes tabs one at a time, bringing each unsaved one forward so its save question is visible.
    private func close(tabs: [EditorWindowController]) {
        group.closing = tabs
        closeNext()
    }

    private func closeNext() {
        guard let next = group.closing.first else { return }
        group.closing.removeFirst()
        guard let document = next.doc else {   // the settings tab: nothing to save
            next.close()
            return closeNext()
        }
        if document.isDocumentEdited { next.select() }
        document.canClose(withDelegate: self, shouldClose: #selector(document(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard shouldClose else { return group.closing = [] }
        document.close()
        closeNext()
    }

    private var others: [EditorWindowController] { group.tabs.filter { $0 !== self } }

    @objc func closeWindowTabs(_ sender: Any?) { close(tabs: others + [self]) }
    @objc func closeOtherTabs(_ sender: Any?) { close(tabs: others) }
    @objc func closeTabsToRight(_ sender: Any?) {
        guard let index = group.tabs.firstIndex(of: self) else { return }
        close(tabs: Array(group.tabs[(index + 1)...]))
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // the settings tab has no text, so only the tab commands apply to it
        if doc == nil { return [#selector(cycleTab(_:)), #selector(closeWindowTabs(_:)), #selector(closeOtherTabs(_:)), #selector(closeTabsToRight(_:))].contains(item.action) }
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
             #selector(clearFormatting(_:)), #selector(setHeading(_:)), #selector(setList(_:)), #selector(insertMarkdownTable(_:)), #selector(insertImage(_:)):
            return Settings.formatting
        default:
            break
        }
        return true
    }
}
