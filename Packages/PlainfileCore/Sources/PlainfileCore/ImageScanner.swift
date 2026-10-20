import Foundation
import ImageIO

/// Read-only image metadata scanner built on ImageIO.
///
/// Runs inside the parser XPC service. It takes bytes, not a path, so the
/// service needs no file access at all.
public enum ImageScanner {
    public static let maxBytes = 512 * 1_048_576

    /// Top-level properties that describe pixels rather than the person or device.
    private static let structuralKeys: Set<String> = [
        kCGImagePropertyPixelWidth as String,
        kCGImagePropertyPixelHeight as String,
        kCGImagePropertyDepth as String,
        kCGImagePropertyColorModel as String,
        kCGImagePropertyHasAlpha as String,
        kCGImagePropertyDPIWidth as String,
        kCGImagePropertyDPIHeight as String,
        kCGImagePropertyIsFloat as String,
        kCGImagePropertyIsIndexed as String,
        "PrimaryImage", "FileContentsDictionary",
    ]

    /// XMP namespaces that ImageIO mirrors from EXIF/TIFF; listed once, from EXIF.
    private static let mirroredXMPPrefixes: Set<String> = ["exif", "tiff", "exifEX"]

    public static func scan(data: Data) throws -> ScanReport {
        guard data.count <= maxBytes else { throw ScanError.tooLarge(limit: maxBytes) }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw ScanError.unreadable
        }
        guard let type = CGImageSourceGetType(source) as String? else { throw ScanError.notAnImage }

        let count = CGImageSourceGetCount(source)
        var fields: [MetadataField] = []
        var notes: [String] = []

        for index in 0..<count {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
            else { continue }
            let label = count > 1 ? "Image \(index + 1) · " : ""
            fields += propertyFields(props, idPrefix: "img\(index)", labelPrefix: label)
        }
        if count > 1 {
            notes.append("This file contains \(count) images. Each is listed separately.")
        }
        fields += xmpFields(source)

        notes.append(
            "Embedded thumbnails and Content Credentials are not detected yet in this preview version.")
        fields.sort { ($0.group, -$0.risk.rawValue, $0.name) < ($1.group, -$1.risk.rawValue, $1.name) }
        return ScanReport(typeIdentifier: type, imageCount: count, fields: fields, notes: notes)
    }

    // MARK: - Property dictionaries

    static func propertyFields(_ props: [String: Any], idPrefix: String, labelPrefix: String)
        -> [MetadataField]
    {
        var result: [MetadataField] = []
        for (key, value) in props {
            if let dict = value as? [String: Any], key.hasPrefix("{") {
                let source = sourceName(forDictionary: key)
                for (innerKey, innerValue) in dict {
                    let (group, risk, removeByDefault) = classify(dictionary: key, key: innerKey)
                    result.append(
                        MetadataField(
                            id: "\(idPrefix).\(key).\(innerKey)", group: group,
                            name: labelPrefix + readable(innerKey),
                            value: ValueFormatter.string(innerValue),
                            source: source, risk: risk, removeByDefault: removeByDefault,
                            literal: innerValue is String))
                }
            } else if !structuralKeys.contains(key) {
                let (group, risk, removeByDefault) = classify(dictionary: nil, key: key)
                result.append(
                    MetadataField(
                        id: "\(idPrefix).\(key)", group: group, name: labelPrefix + readable(key),
                        value: ValueFormatter.string(value), source: "Image",
                        risk: risk, removeByDefault: removeByDefault, literal: value is String))
            }
        }
        return result
    }

    static func sourceName(forDictionary key: String) -> String {
        let bare = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        if bare.hasPrefix("Maker") { return "MakerNotes (\(bare.dropFirst(5)))" }
        return bare
    }

    static func classify(dictionary: String?, key: String) -> (MetadataGroup, Risk, Bool) {
        let k = key.lowercased()
        switch dictionary {
        case "{GPS}":
            return (.location, .critical, true)
        case let d? where d.hasPrefix("{Maker"):
            return (.device, .high, true)
        case "{IPTC}":
            if k.contains("city") || k.contains("country") || k.contains("location")
                || k.contains("sublocation") || k.contains("province")
            {
                return (.location, .high, true)
            }
            if k.contains("date") || k.contains("time") { return (.dates, .medium, true) }
            return (.people, .high, true)
        default:
            break
        }
        if k == "orientation" { return (.other, .low, false) }
        // Removing the colour space or gamma can change how colours display.
        if k == "colorspace" || k == "gamma" { return (.other, .low, false) }
        if k == "profilename" { return (.other, .low, false) }
        if k.contains("serial") || k == "hostcomputer" || k == "make" || k == "model"
            || k.contains("lens")
        {
            return (.device, .high, true)
        }
        if k == "artist" || k == "copyright" || k.contains("owner") || k == "author"
            || k == "usercomment"
        {
            return (.people, .high, true)
        }
        if k.contains("date") || k.contains("subsectime") || k.contains("offsettime") {
            return (.dates, .medium, true)
        }
        if k == "software" || k.contains("history") || k.contains("documentid") || k == "comment"
            || k == "description"
        {
            return (.editHistory, .medium, true)
        }
        return (.other, .low, true)
    }

    // MARK: - XMP

    private final class Collector {
        var fields: [MetadataField] = []
    }

    static func xmpFields(_ source: CGImageSource) -> [MetadataField] {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else { return [] }
        let collector = Collector()
        let options = [kCGImageMetadataEnumerateRecursively: true] as CFDictionary
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, options) { path, tag in
            let prefix = CGImageMetadataTagCopyPrefix(tag) as String? ?? ""
            guard !ImageScanner.mirroredXMPPrefixes.contains(prefix) else { return true }
            let type = CGImageMetadataTagGetType(tag)
            guard type != .arrayUnordered, type != .arrayOrdered, type != .alternateArray,
                type != .structure, type != .alternateText
            else { return true }
            let raw = CGImageMetadataTagCopyValue(tag)
            let value = raw.map { ValueFormatter.string($0) } ?? ""
            let name = CGImageMetadataTagCopyName(tag) as String? ?? (path as String)
            let (group, risk, removeByDefault) = ImageScanner.classify(dictionary: nil, key: name)
            collector.fields.append(
                MetadataField(
                    id: "xmp.\(path as String)", group: group, name: "\(prefix):\(name)",
                    value: value, source: "XMP", risk: max(risk, .medium),
                    removeByDefault: removeByDefault, literal: (raw as? String) != nil))
            return true
        }
        return collector.fields
    }

    static func readable(_ key: String) -> String {
        var out = ""
        var previous: Character?
        for char in key {
            if let p = previous, char.isUppercase, p.isLowercase { out.append(" ") }
            out.append(char)
            previous = char
        }
        return out
    }
}
