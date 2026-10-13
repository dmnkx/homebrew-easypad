import Foundation

/// "ANSI" is the legacy code page: CP949 on a Korean system, Windows-1252 otherwise.
let ansiEncoding: String.Encoding = isKorean
    ? String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
    : .windowsCP1252

public enum TextEncoding: Int, CaseIterable, Codable {
    case ansi, utf16le, utf16be, utf8, utf8bom

    public var title: String { ["ANSI", "UTF-16 LE", "UTF-16 BE", "UTF-8", L("UTF-8 with BOM")][rawValue] }

    var bom: [UInt8] {
        switch self {
        case .utf16le: return [0xFF, 0xFE]
        case .utf16be: return [0xFE, 0xFF]
        case .utf8bom: return [0xEF, 0xBB, 0xBF]
        default: return []
        }
    }

    var encoding: String.Encoding {
        switch self {
        case .ansi: return ansiEncoding
        case .utf16le: return .utf16LittleEndian
        case .utf16be: return .utf16BigEndian
        default: return .utf8
        }
    }
}

public enum LineEnding: Int, Codable {
    case crlf, lf, cr

    public var title: String { [" Windows (CRLF)", " Unix (LF)", " Macintosh (CR)"][rawValue] }
    var string: String { ["\r\n", "\n", "\r"][rawValue] }
}

/// A text file as Notepad sees it: `text` always uses "\n"; the original
/// encoding and line ending are kept so saving writes the file back the same way.
public struct TextFile: Equatable {
    public var text: String
    public var encoding: TextEncoding
    public var lineEnding: LineEnding

    public init(text: String = "", encoding: TextEncoding = .utf8, lineEnding: LineEnding = .crlf) {
        self.text = text
        self.encoding = encoding
        self.lineEnding = lineEnding
    }

    public init(data: Data) {
        // shortcut: BOM-less UTF-16 is not detected, add a heuristic if such files show up
        let head = [UInt8](data.prefix(3))
        if head.starts(with: TextEncoding.utf8bom.bom) {
            encoding = .utf8bom
        } else if head.starts(with: TextEncoding.utf16le.bom) {
            encoding = .utf16le
        } else if head.starts(with: TextEncoding.utf16be.bom) {
            encoding = .utf16be
        } else {
            encoding = String(data: data, encoding: .utf8) != nil ? .utf8 : .ansi
        }
        let body = data.dropFirst(encoding.bom.count)
        let raw = String(data: body, encoding: encoding.encoding) ?? String(data: body, encoding: .isoLatin1) ?? ""

        lineEnding = .crlf
        let scalars = raw.unicodeScalars
        if let i = scalars.firstIndex(where: { $0 == "\r" || $0 == "\n" }) {
            let next = scalars.index(after: i)
            lineEnding = scalars[i] == "\n" ? .lf : (next < scalars.endIndex && scalars[next] == "\n") ? .crlf : .cr
        }
        text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// Returns nil when the encoding cannot hold the text and `lossy` is false.
    public func data(lossy: Bool) -> Data? {
        let out = text.replacingOccurrences(of: "\n", with: lineEnding.string)
        guard let body = out.data(using: encoding.encoding, allowLossyConversion: lossy) else { return nil }
        return Data(encoding.bom) + body
    }
}

/// Expands Notepad's page header/footer codes into [left, center, right].
/// &f file name, &p page, &d date, &t time, &l &c &r alignment, && ampersand.
public func formatHeaderFooter(_ template: String, file: String, page: Int, date: Date = Date()) -> [String] {
    var parts = ["", "", ""], section = 1, chars = Array(template), i = 0
    while i < chars.count {
        guard chars[i] == "&", i + 1 < chars.count else {
            parts[section].append(chars[i])
            i += 1
            continue
        }
        switch chars[i + 1].lowercased() {
        case "f": parts[section] += file
        case "p": parts[section] += String(page)
        case "d": parts[section] += DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)
        case "t": parts[section] += DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
        case "l": section = 0
        case "c": section = 1
        case "r": section = 2
        case "&": parts[section] += "&"
        default: parts[section] += "&" + String(chars[i + 1])
        }
        i += 2
    }
    return parts
}

/// The stamp F5 inserts, e.g. "3:45 PM 10/13/2026".
func timeDateString() -> String {
    DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short) + " "
        + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
}
