import AppKit

@MainActor public func runApp() {
    let app = NSApplication.shared
    _ = DocumentController()   // the first document controller created becomes the shared one
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static func register() {
        defaults.register(defaults: [
            "theme": 0, "fontSize": 11, "wordWrap": true, "formatting": true, "openInNewWindow": 0, "startNew": 0,
            "recentFiles": true, "spellCheck": true, "autocorrect": true, "statusBar": true,
            "header": "&f", "footer": L("Page &p"), "marginLeft": 20, "marginRight": 20, "marginTop": 25, "marginBottom": 25,
        ])
    }

    static var theme: Int { defaults.integer(forKey: "theme") }
    static var formatting: Bool { defaults.bool(forKey: "formatting") }
    static var opensInNewWindow: Bool { defaults.integer(forKey: "openInNewWindow") == 1 }
    static var startNew: Bool { defaults.integer(forKey: "startNew") == 1 }
    static var recentFiles: Bool { defaults.bool(forKey: "recentFiles") }
    static var spellCheck: Bool { defaults.bool(forKey: "spellCheck") }
    static var autocorrect: Bool { defaults.bool(forKey: "autocorrect") }

    static var wordWrap: Bool {
        get { defaults.bool(forKey: "wordWrap") }
        set { defaults.set(newValue, forKey: "wordWrap") }
    }

    static var statusBar: Bool {
        get { defaults.bool(forKey: "statusBar") }
        set { defaults.set(newValue, forKey: "statusBar") }
    }

    static var font: NSFont {
        get {
            let size = CGFloat(defaults.double(forKey: "fontSize"))
            return defaults.string(forKey: "fontName").flatMap { NSFont(name: $0, size: size) }
                ?? NSFont.userFixedPitchFont(ofSize: size) ?? NSFont.systemFont(ofSize: size)
        }
        set {
            defaults.set(newValue.fontName, forKey: "fontName")
            defaults.set(Double(newValue.pointSize), forKey: "fontSize")
        }
    }
}

func menuItem(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
              tag: Int = 0, target: AnyObject? = nil) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.tag = tag
    item.target = target
    return item
}

private func functionKey(_ key: Int) -> String { String(utf16CodeUnits: [unichar(key)], count: 1) }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private weak var settingsTab: EditorWindowController?
    private var sessionRestored: Bool?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Settings.register()
        NSWindow.allowsAutomaticWindowTabbing = false   // tabs are the editor's own, see TabGroup
        NSApp.mainMenu = buildMenu()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: UserDefaults.didChangeNotification, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit adds its own "Open Recent" next to Open...; the Recent menu built below replaces it
        if let file = NSApp.mainMenu?.item(at: 1)?.submenu {
            file.items.filter { $0.submenu != nil && $0.title != L("Recent") }.forEach(file.removeItem)
        }
        _ = restoreSession()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !restoreSession() }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func applicationDidResignActive(_ notification: Notification) { if !Settings.startNew { Session.save() } }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Session.saveForQuit()
        let documents = NSDocumentController.shared
        guard documents.hasEditedDocuments else { return .terminateNow }
        documents.reviewUnsavedDocuments(withAlertTitle: nil, cancellable: true, delegate: self,
                                         didReviewAllSelector: #selector(documentController(_:didReviewAll:contextInfo:)), contextInfo: nil)
        return .terminateLater
    }

    @objc private func documentController(_ controller: NSDocumentController, didReviewAll: Bool, contextInfo: UnsafeMutableRawPointer?) {
        NSApp.reply(toApplicationShouldTerminate: didReviewAll)
    }

    /// Reopens last session's tabs once; true if there was anything to reopen.
    private func restoreSession() -> Bool {
        if sessionRestored == nil { sessionRestored = !Settings.startNew && Session.restore() }
        return sessionRestored == true
    }

    @objc private func applyTheme() {
        let wanted = [nil, NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)][min(max(Settings.theme, 0), 2)]
        if NSApp.appearance?.name != wanted?.name { NSApp.appearance = wanted }
    }

    // MARK: Settings and font

    /// Settings open as a tab, like Notepad's; asking again goes back to that tab.
    @objc func showSettings(_ sender: Any?) {
        if let settingsTab { return settingsTab.select() }
        let tab = EditorWindowController()
        tab.showSettings()
        if let active = EditorWindowController.active { tab.join(active) }
        settingsTab = tab
        tab.select()
    }

    @objc func showFonts(_ sender: Any?) {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(Settings.font, isMultiple: false)
        manager.orderFrontFontPanel(sender)
    }

    @objc func changeFont(_ sender: NSFontManager?) {
        if let sender { Settings.font = sender.convert(Settings.font) }
    }

    // MARK: Recent files

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = Settings.recentFiles ? NSDocumentController.shared.recentDocumentURLs : []
        for url in urls {
            let item = menuItem(url.lastPathComponent, #selector(openRecent(_:)), target: self)
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        if urls.isEmpty {
            menu.addItem(menuItem(L("No recent files"), nil))
        } else {
            menu.addItem(.separator())
            menu.addItem(menuItem(L("Clear list"), #selector(NSDocumentController.clearRecentDocuments(_:))))
        }
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    // MARK: Menu bar (Ctrl shortcuts of Notepad become Command)

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach { menu.addItem($0) }
            item.submenu = menu
            return item
        }
        let documents = NSDocumentController.shared
        let finder = #selector(NSResponder.performTextFinderAction(_:))
        let option: NSEvent.ModifierFlags = [.command, .option], shift: NSEvent.ModifierFlags = [.command, .shift]

        main.addItem(submenu("", [
            menuItem(L("About EasyPad"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            menuItem(L("Settings..."), #selector(showSettings(_:)), ",", target: self),
            .separator(),
            menuItem(L("Hide EasyPad"), #selector(NSApplication.hide(_:)), "h"),
            menuItem(L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", option),
            menuItem(L("Show All"), #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            menuItem(L("Quit EasyPad"), #selector(NSApplication.terminate(_:)), "q"),
        ]))

        let recent = submenu(L("Recent"), [])
        recent.submenu?.delegate = self
        // T works wherever N does; a menu item holds one shortcut, so a hidden twin carries the second
        func twin(_ item: NSMenuItem) -> NSMenuItem {
            let twin = menuItem(item.title, item.action, "t", item.keyEquivalentModifierMask, target: item.target)
            twin.isHidden = true
            twin.allowsKeyEquivalentWhenHidden = true
            return twin
        }
        // new tabs are Markdown; the Shift variant makes a plain text one
        let newTab = menuItem(L("New tab"), #selector(NSDocumentController.newDocument(_:)), "n")
        let newTextTab = menuItem(L("New text tab"), #selector(DocumentController.newTextDocument(_:)), "n", shift, target: documents)
        main.addItem(submenu(L("File"), [
            newTab, twin(newTab), newTextTab, twin(newTextTab),
            menuItem(L("New window"), #selector(DocumentController.newWindowDocument(_:)), target: documents),
            menuItem(L("Open..."), #selector(NSDocumentController.openDocument(_:)), "o"),
            recent,
            .separator(),
            menuItem(L("Save"), #selector(NSDocument.save(_:)), "s"),
            menuItem(L("Save as..."), #selector(NSDocument.saveAs(_:)), "s", shift),
            menuItem(L("Save all"), #selector(NSDocumentController.saveAllDocuments(_:)), "s", option),
            .separator(),
            menuItem(L("Page setup..."), #selector(NSDocument.runPageLayout(_:))),
            menuItem(L("Print..."), #selector(NSDocument.printDocument(_:)), "p"),
            .separator(),
            menuItem(L("Close tab"), #selector(NSWindow.performClose(_:)), "w"),
            menuItem(L("Close window"), #selector(EditorWindowController.closeWindowTabs(_:)), "w", shift),
        ]))

        main.addItem(submenu(L("Edit"), [
            menuItem(L("Undo"), Selector(("undo:")), "z"),
            menuItem(L("Redo"), Selector(("redo:")), "z", shift),
            .separator(),
            menuItem(L("Cut"), #selector(NSText.cut(_:)), "x"),
            menuItem(L("Copy"), #selector(NSText.copy(_:)), "c"),
            menuItem(L("Paste"), #selector(NSText.paste(_:)), "v"),
            menuItem(L("Delete"), #selector(NSText.delete(_:))),
            .separator(),
            menuItem(L("Search with Bing"), #selector(EditorWindowController.searchWithBing(_:)), "e"),
            .separator(),
            menuItem(L("Find"), finder, "f", tag: NSTextFinder.Action.showFindInterface.rawValue),
            menuItem(L("Find next"), finder, functionKey(NSF3FunctionKey), [], tag: NSTextFinder.Action.nextMatch.rawValue),
            menuItem(L("Find previous"), finder, functionKey(NSF3FunctionKey), .shift, tag: NSTextFinder.Action.previousMatch.rawValue),
            menuItem(L("Replace"), finder, "f", option, tag: NSTextFinder.Action.showReplaceInterface.rawValue),
            menuItem(L("Go to"), #selector(EditorWindowController.goToLine(_:)), "g"),
            .separator(),
            menuItem(L("Select all"), #selector(NSText.selectAll(_:)), "a"),
            menuItem(L("Time/Date"), #selector(EditorWindowController.insertTimeDate(_:)), functionKey(NSF5FunctionKey), []),
            .separator(),
            menuItem(L("Font..."), #selector(showFonts(_:)), target: self),
        ]))

        let zoom = #selector(EditorWindowController.zoomText(_:)), markdownView = #selector(EditorWindowController.setMarkdownView(_:))
        main.addItem(submenu(L("View"), [
            submenu(L("Zoom"), [
                menuItem(L("Zoom in"), zoom, "=", tag: 1),
                menuItem(L("Zoom out"), zoom, "-", tag: -1),
                menuItem(L("Restore default zoom"), zoom, "0", tag: 0),
            ]),
            menuItem(L("Status bar"), #selector(EditorWindowController.toggleStatusBar(_:))),
            menuItem(L("Word wrap"), #selector(EditorWindowController.toggleWordWrap(_:)), "z", .option),
            submenu(L("Markdown"), [menuItem(L("Formatted"), markdownView, tag: 0), menuItem(L("Syntax"), markdownView, tag: 1)]),
        ]))

        // shortcut: Notepad clears formatting with Ctrl+Space, which macOS reserves for input sources, so it is Command+\ here
        main.addItem(submenu(L("Format"), [
            menuItem(L("Bold"), #selector(EditorWindowController.toggleBold(_:)), "b"),
            menuItem(L("Italic"), #selector(EditorWindowController.toggleItalic(_:)), "i"),
            menuItem(L("Strikethrough"), #selector(EditorWindowController.toggleStrikethrough(_:)), "x", shift),
            menuItem(L("Link"), #selector(EditorWindowController.insertLink(_:)), "k"),
            menuItem(L("Remove link"), #selector(EditorWindowController.removeLink(_:))),
            menuItem(L("Clear formatting"), #selector(EditorWindowController.clearFormatting(_:)), "\\"),
            .separator(),
            submenu(L("Headings"), headingItems()),
            submenu(L("Lists"), listItems()),
            submenu(L("Table"), tableItems()),
            submenu(L("Image"), imageItems()),
        ]))

        let window = submenu(L("Window"), [
            menuItem(L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"),
            .separator(),
            menuItem(L("Next tab"), #selector(EditorWindowController.cycleTab(_:)), "\t", .control, tag: 1),
            menuItem(L("Previous tab"), #selector(EditorWindowController.cycleTab(_:)), "\t", [.control, .shift], tag: -1),
            menuItem(L("Close other tabs"), #selector(EditorWindowController.closeOtherTabs(_:))),
            menuItem(L("Close tabs to the right"), #selector(EditorWindowController.closeTabsToRight(_:))),
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu
        return main
    }
}

/// The settings page shown in a tab: titled sections of rounded cards.
final class SettingsView: NSStackView {
    private let fontButton = NSButton(title: "", target: nil, action: #selector(AppDelegate.showFonts(_:)))

    override var isFlipped: Bool { true }   // so the scroll view starts at the top

    init() {
        super.init(frame: .zero)

        let defaults = NSUserDefaultsController.shared
        func toggle(_ key: String) -> NSSwitch {
            let toggle = NSSwitch()
            toggle.bind(.value, to: defaults, withKeyPath: "values." + key)
            return toggle
        }
        func popup(_ titles: [String], _ key: String) -> NSPopUpButton {
            let popup = NSPopUpButton()
            popup.addItems(withTitles: titles)
            popup.isBordered = false
            popup.bind(.selectedIndex, to: defaults, withKeyPath: "values." + key)
            return popup
        }
        // one setting: icon, name, optional explanation, control at the right edge
        func row(_ symbol: String, _ title: String, _ detail: String? = nil, _ control: NSControl) -> NSView {
            let icon = NSImageView(image: symbolImage(symbol))
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            icon.contentTintColor = .labelColor
            icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
            let labels = NSStackView(views: [NSTextField(labelWithString: title)])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 2
            if let detail {
                let text = NSTextField(labelWithString: detail)
                text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                text.textColor = .secondaryLabelColor
                labels.addArrangedSubview(text)
            }
            control.setAccessibilityLabel(title)
            let row = NSStackView()
            row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            row.spacing = 12
            row.addView(icon, in: .leading)
            row.addView(labels, in: .leading)
            row.addView(control, in: .trailing)
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
            return row
        }
        // a titled group of settings on one rounded card, like the sections of Notepad's settings page
        func section(_ title: String, _ rows: [NSView]) -> [NSView] {
            let header = NSTextField(labelWithString: title)
            header.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            let list = NSStackView()
            list.orientation = .vertical
            list.alignment = .trailing
            list.spacing = 0
            for (index, row) in rows.enumerated() {
                if index > 0 {
                    let line = NSBox()
                    line.boxType = .separator
                    list.addArrangedSubview(line)
                    line.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -54).isActive = true   // starts under the names, not the icons
                }
                list.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            }
            let card = NSBox()
            card.boxType = .custom
            card.cornerRadius = 10
            card.borderWidth = 0
            card.fillColor = .controlBackgroundColor
            card.contentViewMargins = .zero
            card.addSubview(list)
            list.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                list.topAnchor.constraint(equalTo: card.topAnchor), list.bottomAnchor.constraint(equalTo: card.bottomAnchor),
                list.leadingAnchor.constraint(equalTo: card.leadingAnchor), list.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            ])
            return [header, card]
        }

        fontButton.isBordered = false
        fontButton.image = symbolImage("chevron.right")
        fontButton.imagePosition = .imageTrailing
        fontButton.contentTintColor = .secondaryLabelColor
        let heading = NSTextField(labelWithString: L("Settings"))
        heading.font = .systemFont(ofSize: 26, weight: .bold)
        let page = self
        ([heading] +
            section(L("Appearance"), [
                row("circle.lefthalf.filled", L("App theme"), nil, popup([L("Use system setting"), L("Light"), L("Dark")], "theme")),
            ]) + section(L("Text formatting"), [
                row("textformat", L("Font"), nil, fontButton),
                row("arrow.turn.down.left", L("Word wrap"), L("Fit text within window by default"), toggle("wordWrap")),
                row("bold.italic.underline", L("Formatting"), nil, toggle("formatting")),
            ]) + section(L("Opening EasyPad"), [
                row("doc", L("Opening files"), nil, popup([L("Open in a new tab"), L("Open in a new window")], "openInNewWindow")),
                row("arrow.counterclockwise", L("When EasyPad starts"), nil,
                    popup([L("Continue previous session"), L("Start new session and discard unsaved changes")], "startNew")),
                row("clock", L("Recent Files"), nil, toggle("recentFiles")),
            ]) + section(L("Spelling"), [
                row("textformat.abc.dottedunderline", L("Spell check"), nil, toggle("spellCheck")),
                row("wand.and.stars", L("Autocorrect"), nil, toggle("autocorrect")),
            ])).forEach(page.addArrangedSubview)
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 8
        page.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        page.setCustomSpacing(20, after: heading)
        for (index, view) in page.arrangedSubviews.enumerated().dropFirst() {
            if index % 2 == 0 {
                view.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -48).isActive = true   // cards span the tab, less the side margins
                page.setCustomSpacing(20, after: view)
            } else {
                page.setCustomSpacing(8, after: view)
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(showFont), name: UserDefaults.didChangeNotification, object: nil)
        showFont()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func showFont() {
        let font = Settings.font
        fontButton.title = "\(font.displayName ?? font.fontName) \(Int(font.pointSize))"
    }
}
