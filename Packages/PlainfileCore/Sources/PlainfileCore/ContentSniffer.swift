import Foundation

/// What a file actually contains, judged from its first bytes rather than its
/// name. Only compares fixed signatures (no parsing), so it is safe to run in
/// the main app.
public enum ContentKind: String, Sendable, Equatable {
    case jpeg, png, gif, webp, heif, avif, tiff, bmp, pdf, html, svg, xml, zip, empty, unknown

    public var isImage: Bool {
        switch self {
        case .jpeg, .png, .gif, .webp, .heif, .avif, .tiff, .bmp: true
        default: false
        }
    }

    /// Plain-language description, e.g. "a WebP image" or "a web page".
    public var description: String {
        switch self {
        case .jpeg: "a JPEG image"
        case .png: "a PNG image"
        case .gif: "a GIF image"
        case .webp: "a WebP image"
        case .heif: "a HEIC image"
        case .avif: "an AVIF image"
        case .tiff: "a TIFF image"
        case .bmp: "a BMP image"
        case .pdf: "a PDF document"
        case .html: "a web page (HTML)"
        case .svg: "an SVG drawing"
        case .xml: "an XML document"
        case .zip: "a ZIP archive or Office document"
        case .empty: "nothing (the file is empty)"
        case .unknown: "data Plainfile doesn't recognise"
        }
    }
}

public enum ContentSniffer {
    /// How many leading bytes `kind(of:)` needs.
    public static let prefixLength = 512

    public static func kind(of prefix: Data) -> ContentKind {
        let b = [UInt8](prefix.prefix(prefixLength))
        guard !b.isEmpty else { return .empty }

        func starts(_ bytes: [UInt8], at offset: Int = 0) -> Bool {
            b.count >= offset + bytes.count && Array(b[offset..<(offset + bytes.count)]) == bytes
        }
        func ascii(_ text: String, at offset: Int = 0) -> Bool { starts(Array(text.utf8), at: offset) }

        if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if ascii("GIF87a") || ascii("GIF89a") { return .gif }
        if ascii("RIFF") && ascii("WEBP", at: 8) { return .webp }
        if ascii("ftyp", at: 4), b.count >= 12 {
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            if ["avif", "avis"].contains(brand) { return .avif }
            if ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].contains(brand) {
                return .heif
            }
        }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if ascii("BM") && b.count >= 26 { return .bmp }
        if ascii("%PDF-") { return .pdf }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return .zip }

        // Text formats: skip a byte-order mark and leading whitespace.
        var text = String(decoding: b, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lower = text.drop { $0.isWhitespace }.lowercased()
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") || lower.hasPrefix("<head") {
            return .html
        }
        if lower.hasPrefix("<svg") || (lower.hasPrefix("<?xml") && lower.contains("<svg")) { return .svg }
        if lower.hasPrefix("<?xml") { return .xml }
        return .unknown
    }

    /// Reads just the first bytes of a file.
    public static func kind(ofFileAt url: URL) throws -> ContentKind {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return kind(of: try handle.read(upToCount: prefixLength) ?? Data())
    }
}
