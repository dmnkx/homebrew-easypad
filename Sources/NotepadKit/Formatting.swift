import AppKit
import UniformTypeIdentifiers

// Menu items shared by the formatting toolbar and the Format menu.
func headingItems() -> [NSMenuItem] {
    ["Title", "Subtitle", "Heading", "Subheading", "Section", "Subsection", "Body"].enumerated().map {
        menuItem(L($0.element), #selector(EditorWindowController.setHeading(_:)), tag: $0.offset < 6 ? $0.offset + 1 : 0)
    }
}

func listItems() -> [NSMenuItem] {
    [
        menuItem(L("Bulleted list"), #selector(EditorWindowController.setList(_:)), tag: ListKind.bullet.rawValue),
        menuItem(L("Numbered list"), #selector(EditorWindowController.setList(_:)), tag: ListKind.numbered.rawValue),
        menuItem(L("Task list"), #selector(EditorWindowController.setList(_:)), tag: ListKind.task.rawValue),
        menuItem(L("Check list"), #selector(EditorWindowController.toggleTaskCheck(_:))),
    ]
}

func tableItems() -> [NSMenuItem] {
    let insert: [NSMenuItem] = [menuItem(L("Insert table"), #selector(EditorWindowController.insertTable(_:))), NSMenuItem.separator()]
    return insert + ["Row above", "Row below", "Column left", "Column right", "Delete row", "Delete column", "Delete table"].enumerated().map {
        menuItem(L($0.element), #selector(EditorWindowController.tableOperation(_:)), tag: $0.offset)
    }
}

func imageItems() -> [NSMenuItem] {
    [
        menuItem(L("Insert from this device"), #selector(EditorWindowController.insertImage(_:)), tag: 0),
        menuItem(L("Insert via link"), #selector(EditorWindowController.insertImage(_:)), tag: 1),
    ]
}

extension EditorWindowController {
    /// Formatting commands work on rendered Markdown; plain text becomes Markdown on first use.
    private func ensureFormatted() -> Bool {
        guard Settings.formatting, let doc else { return false }
        if !doc.isMarkdown {
            doc.isMarkdown = true
            if doc.fileURL == nil { doc.fileType = Document.markdown }
        }
        setFormatted(true)
        return true
    }

    /// Undoable replacement of a range.
    private func replace(_ range: NSRange, with text: NSAttributedString) {
        guard textView.shouldChangeText(in: range, replacementString: text.string) else { return }
        storage.replaceCharacters(in: range, with: text)
        textView.didChangeText()
    }

    /// Undoable attribute change; with nothing selected it applies to what is typed next.
    private func restyle(_ range: NSRange, _ change: (Attrs) -> Attrs) {
        guard range.length > 0 else {
            textView.typingAttributes = change(textView.typingAttributes)
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range, options: []) { attrs, runRange, _ in storage.setAttributes(change(attrs), range: runRange) }
        storage.endEditing()
        textView.didChangeText()
        let caret = textView.selectedRange().location
        if caret > range.location {
            textView.typingAttributes = storage.attributes(at: caret - 1, effectiveRange: nil)
        } else if caret < storage.length {
            textView.typingAttributes = storage.attributes(at: caret, effectiveRange: nil)
        }
    }

    private var currentParagraphs: NSRange { (storage.string as NSString).paragraphRange(for: textView.selectedRange()) }

    // MARK: Inline styles

    private func toggle(_ isOn: (Attrs) -> Bool, _ set: (Attrs, Bool) -> Attrs) {
        guard ensureFormatted() else { return }
        let range = textView.selectedRange()
        let on = !isOn(range.length > 0 ? storage.attributes(at: range.location, effectiveRange: nil) : textView.typingAttributes)
        restyle(range) { set($0, on) }
    }

    @objc func toggleBold(_ sender: Any?) { toggle(isBold, setBold) }
    @objc func toggleItalic(_ sender: Any?) { toggle(isItalic, setItalic) }
    @objc func toggleStrikethrough(_ sender: Any?) {
        toggle({ $0[.strikethroughStyle] != nil }) { attrs, on in
            var attrs = attrs
            attrs[.strikethroughStyle] = on ? NSUnderlineStyle.single.rawValue : nil
            return attrs
        }
    }

    @objc func clearFormatting(_ sender: Any?) {
        guard formatted else { return }
        let selection = textView.selectedRange(), body = bodyAttrs
        restyle(selection.length > 0 ? selection : currentParagraphs) { attrs in
            var plain = body
            for key in [NSAttributedString.Key.paragraphStyle, .attachment, .mdImage, .mdImageAlt] { plain[key] = attrs[key] }
            return plain
        }
    }

    @objc func setHeading(_ sender: Any?) {
        guard ensureFormatted() else { return }
        let level = (sender as? NSMenuItem)?.tag ?? 0, base = baseFont
        restyle(currentParagraphs) { attrs in
            var styled = attrs
            styled[.font] = level > 0 ? headingFont(level, base) : base
            styled[.mdHeading] = level > 0 ? level : nil
            return isItalic(attrs) ? setItalic(styled, true) : styled
        }
    }

    // MARK: Lists

    func currentListKind() -> ListKind? {
        (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.last.map { ListKind($0) }
    }

    @objc func setList(_ sender: Any?) {
        guard ensureFormatted(), let kind = ListKind(rawValue: (sender as? NSMenuItem)?.tag ?? 0) else { return }
        applyList(kind)
    }

    @objc func toggleTaskCheck(_ sender: Any?) {
        guard formatted, let kind = currentListKind() else { return }
        if kind == .task { applyList(.taskDone) } else if kind == .taskDone { applyList(.task) }
    }

    /// Turns the selected paragraphs into list items of `kind`, or back into body text if they already are.
    private func applyList(_ kind: ListKind) {
        let selection = currentParagraphs
        let remove = currentListKind() == kind
        let list = NSTextList(markerFormat: kind.format, options: 0)
        let edited = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: selection))

        var paragraphs: [NSRange] = [], location = 0
        let original = edited.string as NSString
        while location < original.length {
            let paragraph = original.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(paragraph)
            location = NSMaxRange(paragraph)
        }
        if paragraphs.isEmpty { paragraphs = [NSRange(location: 0, length: 0)] }

        // last to first, so earlier ranges stay valid while markers are added and removed
        for (index, range) in paragraphs.enumerated().reversed() {
            var range = range
            var attrs = range.length > 0 ? edited.attributes(at: range.location, effectiveRange: nil) : textView.typingAttributes
            let oldStyle = attrs[.paragraphStyle] as? NSParagraphStyle
            if oldStyle?.textBlocks.isEmpty == false { continue }   // table cells stay table cells
            let oldLists = oldStyle?.textLists ?? []
            let text = edited.string as NSString
            if !oldLists.isEmpty, range.length > 1, text.character(at: range.location) == 9 {
                let tab = text.range(of: "\t", range: NSRange(location: range.location + 1, length: range.length - 1))
                if tab.location != NSNotFound {
                    let marker = NSRange(location: range.location, length: NSMaxRange(tab) - range.location)
                    edited.deleteCharacters(in: marker)
                    range.length -= marker.length
                }
            }
            let style = remove ? NSParagraphStyle.default : listParagraphStyle(Array(oldLists.dropLast()) + [list])
            edited.addAttribute(.paragraphStyle, value: style, range: range)
            guard !remove else { continue }
            attrs[.paragraphStyle] = style
            for key in [NSAttributedString.Key.attachment, .mdImage, .mdImageAlt, .link] { attrs[key] = nil }
            edited.insert(NSAttributedString(string: "\t\(list.marker(forItemNumber: index + 1))\t", attributes: attrs), at: range.location)
        }
        replace(selection, with: edited)
        let end = selection.location + edited.length - (edited.string.hasSuffix("\n") ? 1 : 0)
        textView.setSelectedRange(NSRange(location: end, length: 0))
        if edited.length > 0, end > 0 { textView.typingAttributes = storage.attributes(at: end - 1, effectiveRange: nil) }
    }

    // MARK: Links and images

    func currentLink() -> (range: NSRange, address: String)? {
        guard storage.length > 0 else { return nil }
        var range = NSRange()
        let index = min(textView.selectedRange().location, storage.length - 1)
        guard let link = storage.attribute(.link, at: index, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) else { return nil }
        return (range, (link as? URL)?.absoluteString ?? "\(link)")
    }

    @objc func insertLink(_ sender: Any?) {
        guard ensureFormatted() else { return }
        var range = textView.selectedRange()
        let existing = currentLink()
        if range.length == 0, let existing { range = existing.range }
        let text = NSTextField(string: (storage.string as NSString).substring(with: range))
        let address = NSTextField(string: existing?.address ?? "")
        guard runForm(L("Link"), [(L("Display text"), text), (L("Address"), address)], ok: L("Insert")), !address.stringValue.isEmpty else { return }
        var attrs = textView.typingAttributes
        attrs[.link] = address.stringValue
        replace(range, with: NSAttributedString(string: text.stringValue.isEmpty ? address.stringValue : text.stringValue, attributes: attrs))
    }

    @objc func removeLink(_ sender: Any?) {
        guard let link = currentLink() else { return }
        restyle(link.range) { attrs in
            var attrs = attrs
            attrs[.link] = nil
            return attrs
        }
    }

    @objc func insertImage(_ sender: Any?) {
        guard ensureFormatted() else { return }
        var source = ""
        if (sender as? NSMenuItem)?.tag == 1 {
            let address = NSTextField(string: "")
            guard runForm(L("Insert image"), [(L("Address"), address)], ok: L("Insert")) else { return }
            source = address.stringValue
        } else {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            // shortcut: the image is referenced where it is, Notepad copies it into "<name>_Images"; copy it if documents must be portable
            let folder = doc?.fileURL?.deletingLastPathComponent().path
            let path = folder.map { url.path.hasPrefix($0 + "/") ? String(url.path.dropFirst($0.count + 1)) : url.path } ?? url.path
            source = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        }
        guard !source.isEmpty else { return }
        var attrs = textView.typingAttributes
        attrs[.link] = nil
        replace(textView.selectedRange(), with: imageString(alt: "", src: source, attrs, doc?.fileURL))
    }

    // MARK: Tables

    struct TableContext {
        var range: NSRange
        var cells: [[NSAttributedString]]
        var row: Int
        var column: Int
    }

    /// The table around the caret, with its cells read back from the text.
    func currentTable() -> TableContext? {
        guard formatted, storage.length > 0 else { return nil }
        let text = storage.string as NSString
        func block(_ location: Int) -> NSTextTableBlock? {
            guard location >= 0, location < storage.length else { return nil }
            return (storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock
        }
        let caret = min(textView.selectedRange().location, storage.length - 1)
        guard let here = block(caret) else { return nil }
        var start = text.paragraphRange(for: NSRange(location: caret, length: 0)).location
        while let before = block(start - 1), before.table === here.table {
            start = text.paragraphRange(for: NSRange(location: start - 1, length: 0)).location
        }
        var end = start, cells: [[NSAttributedString]] = []
        while let cell = block(end), cell.table === here.table {
            let paragraph = text.paragraphRange(for: NSRange(location: end, length: 0))
            var content = paragraph
            if text.character(at: NSMaxRange(paragraph) - 1) == 10 { content.length -= 1 }
            while cells.count <= cell.startingRow { cells.append([]) }
            cells[cell.startingRow].append(storage.attributedSubstring(from: content))
            end = NSMaxRange(paragraph)
        }
        return TableContext(range: NSRange(location: start, length: end - start), cells: cells, row: here.startingRow, column: here.startingColumn)
    }

    @objc func insertTable(_ sender: Any?) {
        guard ensureFormatted() else { return }
        let rows = NSTextField(string: "3"), columns = NSTextField(string: "3")
        guard runForm(L("Insert table"), [(L("Number of rows"), rows), (L("Number of columns"), columns)], ok: L("Insert")) else { return }
        let empty = NSAttributedString(string: "", attributes: bodyAttrs)
        let row = Array(repeating: empty, count: min(max(columns.integerValue, 1), 20))
        let table = renderTable(Array(repeating: row, count: min(max(rows.integerValue, 1), 100)), bodyAttrs)
        let selection = textView.selectedRange()
        // a table starts on its own line
        if selection.location > 0, (storage.string as NSString).character(at: selection.location - 1) != 10 {
            table.insert(NSAttributedString(string: "\n", attributes: bodyAttrs), at: 0)
        }
        replace(selection, with: table)
    }

    /// Tags follow tableItems(): rows above/below, columns left/right, delete row/column/table.
    @objc func tableOperation(_ sender: Any?) {
        guard var table = currentTable() else { return }
        let columns = table.cells.map(\.count).max() ?? 0
        let empty = NSAttributedString(string: "", attributes: bodyAttrs)
        switch (sender as? NSMenuItem)?.tag ?? -1 {
        case 0: table.cells.insert(Array(repeating: empty, count: columns), at: table.row)
        case 1: table.cells.insert(Array(repeating: empty, count: columns), at: table.row + 1)
        case 2, 3:
            let offset = (sender as? NSMenuItem)?.tag == 3 ? 1 : 0
            for row in table.cells.indices { table.cells[row].insert(empty, at: min(table.column + offset, table.cells[row].count)) }
        case 4: table.cells.remove(at: table.row)
        case 5:
            for row in table.cells.indices where table.column < table.cells[row].count { table.cells[row].remove(at: table.column) }
        case 6: table.cells = []
        default: return
        }
        replace(table.range, with: renderTable(table.cells, bodyAttrs))
    }
}
