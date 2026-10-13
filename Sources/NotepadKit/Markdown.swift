import AppKit

// The formatted view keeps Markdown structure in text attributes:
// headings in .mdHeading, lists in NSParagraphStyle.textLists, tables in
// NSTextTableBlock, everything inline in font traits and the keys below.
extension NSAttributedString.Key {
    static let mdHeading = NSAttributedString.Key("mdHeading")
    static let mdCode = NSAttributedString.Key("mdCode")
    static let mdLiteral = NSAttributedString.Key("mdLiteral")
    static let mdImage = NSAttributedString.Key("mdImage")
    static let mdImageAlt = NSAttributedString.Key("mdImageAlt")
}

typealias Attrs = [NSAttributedString.Key: Any]

private let fontManager = NSFontManager.shared

enum ListKind: Int {
    case bullet = 1, numbered, task, taskDone

    init(_ list: NSTextList) {
        let format = list.markerFormat.rawValue
        self = format.contains("decimal") ? .numbered : format.contains("box") ? .task : format.contains("check") ? .taskDone : .bullet
    }

    var format: NSTextList.MarkerFormat {
        switch self {
        case .bullet: return .disc
        case .numbered: return NSTextList.MarkerFormat(rawValue: "{decimal}.")
        case .task: return .box
        case .taskDone: return .check
        }
    }

    func prefix(_ number: Int) -> String {
        switch self {
        case .bullet: return "- "
        case .numbered: return "\(number). "
        case .task: return "- [ ] "
        case .taskDone: return "- [x] "
        }
    }
}

func symbolImage(_ name: String) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 16, height: 16))
}

// MARK: - Inline attributes

func headingFont(_ level: Int, _ base: NSFont) -> NSFont {
    let scale: [CGFloat] = [2, 1.6, 1.35, 1.2, 1.1, 1]
    let sized = fontManager.convert(base, toSize: base.pointSize * scale[max(1, min(level, 6)) - 1])
    return fontManager.convert(sized, toHaveTrait: .boldFontMask)
}

private func hasTrait(_ attrs: Attrs, _ trait: NSFontTraitMask) -> Bool {
    (attrs[.font] as? NSFont).map { fontManager.traits(of: $0).contains(trait) } ?? false
}

func isBold(_ attrs: Attrs) -> Bool { hasTrait(attrs, .boldFontMask) }

func isItalic(_ attrs: Attrs) -> Bool { hasTrait(attrs, .italicFontMask) || attrs[.obliqueness] != nil }

func setBold(_ attrs: Attrs, _ on: Bool) -> Attrs {
    var attrs = attrs
    if let font = attrs[.font] as? NSFont {
        attrs[.font] = on ? fontManager.convert(font, toHaveTrait: .boldFontMask) : fontManager.convert(font, toNotHaveTrait: .boldFontMask)
    }
    return attrs
}

func setItalic(_ attrs: Attrs, _ on: Bool) -> Attrs {
    var attrs = attrs
    guard let font = attrs[.font] as? NSFont else { return attrs }
    let converted = on ? fontManager.convert(font, toHaveTrait: .italicFontMask) : fontManager.convert(font, toNotHaveTrait: .italicFontMask)
    attrs[.font] = converted
    // fonts without an italic face (most CJK fonts) get a synthetic slant
    attrs[.obliqueness] = on && !fontManager.traits(of: converted).contains(.italicFontMask) ? 0.2 : nil
    return attrs
}

func listParagraphStyle(_ lists: [NSTextList]) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    let indent = CGFloat(lists.count) * 36
    style.textLists = lists
    style.headIndent = indent
    style.tabStops = [NSTextTab(textAlignment: .left, location: indent - 25), NSTextTab(textAlignment: .left, location: indent)]
    return style
}

func imageString(alt: String, src: String, _ attrs: Attrs, _ baseURL: URL?) -> NSAttributedString {
    var image: NSImage?
    // shortcut: remote images are not downloaded and show a placeholder, load them async if that matters
    if !src.contains("://") {
        let path = src.removingPercentEncoding ?? src
        image = NSImage(contentsOf: URL(fileURLWithPath: path, relativeTo: baseURL?.deletingLastPathComponent()))
    }
    let shown = image ?? symbolImage("photo")
    let attachment = NSTextAttachment()
    attachment.image = shown
    let width = min(shown.size.width, 480)
    attachment.bounds = NSRect(x: 0, y: 0, width: width, height: shown.size.width > 0 ? shown.size.height * width / shown.size.width : 0)
    let out = NSMutableAttributedString(attachment: attachment)
    let all = NSRange(location: 0, length: out.length)
    out.addAttributes(attrs, range: all)
    out.addAttributes([.mdImage: src, .mdImageAlt: alt], range: all)
    return out
}

/// One paragraph per cell, laid out as a grid by NSTextTable. Row 0 is the header.
func renderTable(_ rows: [[NSAttributedString]], _ attrs: Attrs) -> NSMutableAttributedString {
    let out = NSMutableAttributedString()
    let columns = rows.map(\.count).max() ?? 0
    guard columns > 0 else { return out }
    let table = NSTextTable()
    table.numberOfColumns = columns
    table.setContentWidth(100, type: .percentageValueType)
    for (r, row) in rows.enumerated() {
        for c in 0..<columns {
            let block = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
            block.setWidth(1, type: .absoluteValueType, for: .border)
            block.setWidth(5, type: .absoluteValueType, for: .padding)
            block.setBorderColor(.gridColor)
            let style = NSMutableParagraphStyle()
            style.textBlocks = [block]
            let cell = NSMutableAttributedString(attributedString: c < row.count ? row[c] : NSAttributedString())
            cell.append(NSAttributedString(string: "\n", attributes: attrs))
            let all = NSRange(location: 0, length: cell.length)
            cell.addAttribute(.paragraphStyle, value: style, range: all)
            if r == 0 {
                cell.enumerateAttributes(in: all, options: []) { a, range, _ in cell.setAttributes(setBold(a, true), range: range) }
            }
            out.append(cell)
        }
    }
    return out
}

// MARK: - Markdown -> attributed text

private func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

// groups: 1 alt 2 src | 3 text 4 url | 5 code | 6 bold+italic | 7,8 bold | 9 strike | 10,11 italic
private let inlineRegex = regex(#"!\[([^\]]*)\]\(([^)]+)\)|\[([^\]]+)\]\(([^)]+)\)|`([^`]+)`|\*\*\*(.+?)\*\*\*|\*\*(.+?)\*\*|__(.+?)__|~~(.+?)~~|\*(.+?)\*|(?<![A-Za-z0-9])_(.+?)_(?![A-Za-z0-9])"#)
private let headingRegex = regex(#"^(#{1,6})[ \t]+(.*)$"#)
private let listRegex = regex(#"^([ \t]*)([-*+]|\d+[.)])[ \t]+(\[([ xX])\][ \t]+)?(.*)$"#)
private let tableRuleRegex = regex(#"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"#)

private func groups(_ re: NSRegularExpression, _ string: String) -> [String?]? {
    let ns = string as NSString
    guard let match = re.firstMatch(in: string, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? nil : ns.substring(with: match.range(at: $0)) }
}

private func tableCells(_ line: String) -> [String] {
    var trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("|") { trimmed.removeFirst() }
    if trimmed.hasSuffix("|") { trimmed.removeLast() }
    return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
}

func renderInline(_ string: String, _ attrs: Attrs, _ baseURL: URL?) -> NSMutableAttributedString {
    let out = NSMutableAttributedString()
    let ns = string as NSString
    var position = 0
    while let match = inlineRegex.firstMatch(in: string, range: NSRange(location: position, length: ns.length - position)) {
        out.append(NSAttributedString(string: ns.substring(with: NSRange(location: position, length: match.range.location - position)), attributes: attrs))
        func group(_ index: Int) -> String? {
            match.range(at: index).location == NSNotFound ? nil : ns.substring(with: match.range(at: index))
        }
        var inner = attrs
        if let src = group(2) {
            out.append(imageString(alt: group(1) ?? "", src: src, attrs, baseURL))
        } else if let text = group(3), let url = group(4) {
            inner[.link] = url
            out.append(renderInline(text, inner, baseURL))
        } else if let code = group(5) {
            inner[.mdCode] = true
            inner[.font] = NSFont.monospacedSystemFont(ofSize: (attrs[.font] as? NSFont)?.pointSize ?? 12, weight: .regular)
            out.append(NSAttributedString(string: code, attributes: inner))
        } else if let text = group(6) {
            out.append(renderInline(text, setItalic(setBold(attrs, true), true), baseURL))
        } else if let text = group(7) ?? group(8) {
            out.append(renderInline(text, setBold(attrs, true), baseURL))
        } else if let text = group(9) {
            inner[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            out.append(renderInline(text, inner, baseURL))
        } else if let text = group(10) ?? group(11) {
            out.append(renderInline(text, setItalic(attrs, true), baseURL))
        }
        position = NSMaxRange(match.range)
    }
    out.append(NSAttributedString(string: ns.substring(from: position), attributes: attrs))
    return out
}

/// Blank lines separate blocks: one is implied between blocks, each extra one
/// becomes an empty paragraph. serializeMarkdown is the exact inverse.
func renderMarkdown(_ source: String, font: NSFont, baseURL: URL? = nil) -> NSAttributedString {
    let body: Attrs = [.font: font, .foregroundColor: NSColor.textColor]
    var literal = body
    literal[.mdLiteral] = true
    literal[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)

    var lines = source.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }

    let out = NSMutableAttributedString()
    var pendingNewline: Attrs?   // attributes of the paragraph still waiting for its terminator
    var started = false
    func add(_ content: NSAttributedString, _ attrs: Attrs) {
        if let pending = pendingNewline { out.append(NSAttributedString(string: "\n", attributes: pending)) }
        out.append(content)
        pendingNewline = attrs
        started = true
    }

    var blanks = 0, fenced = false, i = 0
    var indents: [Int] = [], counters: [Int] = [], lists: [NSTextList] = []
    while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if !fenced && trimmed.isEmpty {
            blanks += 1
            i += 1
            continue
        }
        if blanks > 0 {
            for _ in 0..<(started ? blanks - 1 : blanks) { add(NSAttributedString(), body) }
            blanks = 0
        }
        if let item = fenced || trimmed.hasPrefix("```") ? nil : groups(listRegex, line) {
            let indent = (item[1] ?? "").reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            while let last = indents.last, indent < last {
                indents.removeLast()
                lists.removeLast()
                counters.removeLast()
            }
            var kind: ListKind = item[2]?.first?.isNumber == true ? .numbered : .bullet
            if let box = item[4] { kind = box == " " ? .task : .taskDone }
            if indents.last != indent {
                indents.append(indent)
                lists.append(NSTextList(markerFormat: kind.format, options: 0))
                counters.append(0)
            } else if ListKind(lists[lists.count - 1]) != kind {
                lists[lists.count - 1] = NSTextList(markerFormat: kind.format, options: 0)
            }
            counters[counters.count - 1] += 1
            var attrs = body
            attrs[.paragraphStyle] = listParagraphStyle(lists)
            let paragraph = NSMutableAttributedString(string: "\t\(lists[lists.count - 1].marker(forItemNumber: counters[counters.count - 1]))\t", attributes: attrs)
            paragraph.append(renderInline(item[5] ?? "", attrs, baseURL))
            add(paragraph, attrs)
            i += 1
            continue
        }
        indents = []
        lists = []
        counters = []
        if fenced || trimmed.hasPrefix("```") {
            // fenced code is kept verbatim, fence lines included
            if trimmed.hasPrefix("```") { fenced.toggle() }
            add(NSAttributedString(string: line, attributes: literal), literal)
            i += 1
        } else if let heading = groups(headingRegex, line) {
            var attrs = body
            let level = heading[1]?.count ?? 1
            attrs[.font] = headingFont(level, font)
            attrs[.mdHeading] = level
            add(renderInline(heading[2] ?? "", attrs, baseURL), attrs)
            i += 1
        } else if trimmed.hasPrefix("|"), i + 1 < lines.count, groups(tableRuleRegex, lines[i + 1]) != nil {
            var rows = [tableCells(line)]
            i += 2
            while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                rows.append(tableCells(lines[i]))
                i += 1
            }
            // every cell already ends its own paragraph, so nothing stays pending
            add(renderTable(rows.map { $0.map { renderInline($0, body, baseURL) } }, body), body)
            pendingNewline = nil
        } else {
            add(renderInline(line, body, baseURL), body)
            i += 1
        }
    }
    for _ in 0..<blanks { add(NSAttributedString(), body) }
    return out
}

// MARK: - Attributed text -> Markdown

// shortcut: literal * _ ` [ typed in the formatted view are not escaped, escape them if round trips start changing text
func inlineMarkdown(_ text: NSAttributedString, _ range: NSRange, ignoreBold: Bool = false) -> String {
    var out = ""
    text.enumerateAttributes(in: range, options: []) { attrs, runRange, _ in
        if let src = attrs[.mdImage] as? String {
            out += "![\(attrs[.mdImageAlt] as? String ?? "")](\(src))"
            return
        }
        let run = (text.string as NSString).substring(with: runRange)
        // emphasis markers must hug the text, so surrounding spaces stay outside them
        let lead = String(run.prefix { $0 == " " || $0 == "\t" })
        let trail = run.dropFirst(lead.count).reversed().prefix { $0 == " " || $0 == "\t" }
        var core = String(run.dropFirst(lead.count).dropLast(trail.count))
        guard !core.isEmpty else {
            out += run
            return
        }
        if attrs[.mdCode] != nil {
            core = "`\(core)`"
        } else {
            let bold = !ignoreBold && isBold(attrs), italic = isItalic(attrs)
            if bold && italic { core = "***\(core)***" } else if bold { core = "**\(core)**" } else if italic { core = "*\(core)*" }
            if attrs[.strikethroughStyle] != nil { core = "~~\(core)~~" }
        }
        if let link = attrs[.link] { core = "[\(core)](\((link as? URL)?.absoluteString ?? "\(link)"))" }
        out += lead + core + String(trail.reversed())
    }
    return out
}

func serializeMarkdown(_ text: NSAttributedString) -> String {
    let ns = text.string as NSString
    guard ns.length > 0 else { return "" }
    enum Kind { case list, literal, other }

    var out = "", pendingEmpty = 0, previous: Kind?
    func emit(_ block: String, _ kind: Kind) {
        if let previous { out += previous == kind && kind != .other && pendingEmpty == 0 ? "\n" : "\n\n" }
        out += String(repeating: "\n", count: pendingEmpty) + block
        pendingEmpty = 0
        previous = kind
    }

    var table: NSTextTable?, rows: [[String]] = []
    func flushTable() {
        guard table != nil else { return }
        var lines = rows.map { "| " + $0.joined(separator: " | ") + " |" }
        lines.insert("|" + String(repeating: " --- |", count: rows.first?.count ?? 0), at: min(1, lines.count))
        emit(lines.joined(separator: "\n"), .other)
        table = nil
        rows = []
    }

    var counters: [Int] = [], location = 0
    while location < ns.length {
        let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
        location = NSMaxRange(paragraph)
        var content = paragraph
        if ns.character(at: NSMaxRange(paragraph) - 1) == 10 { content.length -= 1 }
        let attrs = text.attributes(at: paragraph.location, effectiveRange: nil)
        let style = attrs[.paragraphStyle] as? NSParagraphStyle

        if let block = style?.textBlocks.first as? NSTextTableBlock {
            if block.table !== table {
                flushTable()
                table = block.table
            }
            while rows.count <= block.startingRow { rows.append([]) }
            rows[block.startingRow].append(inlineMarkdown(text, content, ignoreBold: block.startingRow == 0))
            continue
        }
        flushTable()
        if let lists = style?.textLists, !lists.isEmpty {
            // the "\t<marker>\t" in front of the item is presentation only
            let item = ns.substring(with: content) as NSString
            if item.hasPrefix("\t") {
                let tab = item.range(of: "\t", range: NSRange(location: 1, length: item.length - 1))
                if tab.location != NSNotFound {
                    content = NSRange(location: content.location + tab.location + 1, length: content.length - tab.location - 1)
                }
            }
            counters = Array(counters.prefix(lists.count))
            while counters.count < lists.count { counters.append(0) }
            counters[lists.count - 1] += 1
            let kind = ListKind(lists[lists.count - 1])
            emit(String(repeating: "    ", count: lists.count - 1) + kind.prefix(counters[lists.count - 1]) + inlineMarkdown(text, content), .list)
            continue
        }
        counters = []
        if attrs[.mdLiteral] != nil {
            emit(ns.substring(with: content), .literal)
        } else if content.length == 0 {
            pendingEmpty += 1
        } else {
            let level = attrs[.mdHeading] as? Int
            emit((level.map { String(repeating: "#", count: $0) + " " } ?? "") + inlineMarkdown(text, content, ignoreBold: level != nil), .other)
        }
    }
    flushTable()
    // a trailing newline means one more, empty, paragraph
    if ns.character(at: ns.length - 1) == 10 { pendingEmpty += 1 }
    out += String(repeating: "\n", count: pendingEmpty)
    return previous == nil ? out : out + "\n"
}
