import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum StripError: Error, Sendable, Equatable, CustomStringConvertible {
    case tooLarge(limit: Int)
    case unreadable
    case unsupportedType(String)
    case multipleImages(Int)
    case writeFailed

    public var description: String {
        switch self {
        case .tooLarge(let limit):
            "This file is larger than \(limit / 1_048_576) MB, the current limit."
        case .unreadable:
            "This file could not be read."
        case .unsupportedType(let type):
            "Removing metadata from this kind of image (\(type)) isn't supported yet. Nothing was changed."
        case .multipleImages(let count):
            "This file contains \(count) images. Files with more than one image aren't supported yet. Nothing was changed."
        case .writeFailed:
            "macOS couldn't write a cleaned copy of this image. Nothing was changed."
        }
    }
}

/// Removes chosen metadata from an image without re-encoding its pixels.
///
/// Runs inside the parser XPC service. It starts from the image's own metadata
/// and deletes the chosen tags, so every kept value is passed through as it
/// was rather than re-written. The picture data is copied, never recompressed:
/// formats ImageIO can't copy that way are refused instead of re-encoded.
public enum ImageStripper {
    /// Formats that come out fully clean with untouched image data. TIFF is
    /// left out: ImageIO always rewrites its camera make, model and artist.
    public static let supportedTypes: Set<String> = [
        UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier,
        UTType.heif.identifier,
    ]

    public static func strip(data: Data, removing ids: Set<String>) throws -> Data {
        guard data.count <= ImageScanner.maxBytes else {
            throw StripError.tooLarge(limit: ImageScanner.maxBytes)
        }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            let type = CGImageSourceGetType(source)
        else { throw StripError.unreadable }
        let count = CGImageSourceGetCount(source)
        guard count == 1 else { throw StripError.multipleImages(count) }
        guard supportedTypes.contains(type as String) else {
            throw StripError.unsupportedType(type as String)
        }

        // ImageIO doesn't remove PNG metadata when copying; drop the chunks instead.
        if type as String == UTType.png.identifier {
            return ids.isEmpty ? data : try PNGStripper.strip(data).output
        }

        let original = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let paths = Set(
            ids.flatMap { id in original.map { xmpPaths(forFieldID: id, in: $0) } ?? [] })

        // Start from the image's own metadata minus the removed tags. It
        // replaces all EXIF, IPTC and XMP in the copy, so anything not in it
        // (maker notes, embedded thumbnails) is dropped too.
        let metadata: CGMutableImageMetadata =
            original.flatMap { CGImageMetadataCreateMutableCopy($0) } ?? CGImageMetadataCreateMutable()
        for path in paths {
            CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
        }
        let merge = false

        var options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: merge,
        ]
        if removesAllLocation(ids, in: source) {
            options[kCGImageMetadataShouldExcludeGPS] = true
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else {
            throw StripError.writeFailed
        }
        // CopyImageSource finalises the destination itself on success.
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil)
        else { throw StripError.writeFailed }
        return output as Data
    }

    /// Maps a scanner field ID to the XMP path(s) ImageIO uses for it.
    ///
    /// Scanner IDs look like `img0.{GPS}.Latitude` (a property-dictionary
    /// value), `img0.Orientation` (a top-level property) or `xmp.<path>`.
    static func xmpPaths(forFieldID id: String, in metadata: CGImageMetadata) -> [String] {
        if id.hasPrefix("xmp.") {
            // An item of a list (e.g. dc:creator[0]) removes the whole list.
            let path = id.dropFirst(4)
            return [String(path.prefix { $0 != "[" })]
        }
        guard id.hasPrefix("img") else { return [] }
        let parts = id.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
        let property: (dictionary: String, key: String)
        switch parts.count {
        case 3 where parts[1].hasPrefix("{"):
            property = (String(parts[1]), String(parts[2]))
        case 2:
            // Top-level properties such as Orientation live in the TIFF dictionary.
            property = (kCGImagePropertyTIFFDictionary as String, String(parts[1]))
        default:
            return []
        }
        guard
            let tag = CGImageMetadataCopyTagMatchingImageProperty(
                metadata, property.dictionary as CFString, property.key as CFString),
            let prefix = CGImageMetadataTagCopyPrefix(tag) as String?,
            let name = CGImageMetadataTagCopyName(tag) as String?
        else { return [] }
        return ["\(prefix):\(name)"]
    }

    /// True when every GPS value in the image is among the IDs being removed.
    static func removesAllLocation(_ ids: Set<String>, in source: CGImageSource) -> Bool {
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        else { return false }
        let gpsKey = kCGImagePropertyGPSDictionary as String
        return gps.keys.allSatisfy { ids.contains("img0.\(gpsKey).\($0)") }
    }
}

/// Checks that two images show exactly the same picture.
public enum ImageComparator {
    public static func pixelsMatch(_ original: Data, _ stripped: Data) throws -> Bool {
        guard let a = try render(original), let b = try render(stripped) else {
            throw StripError.unreadable
        }
        return a == b
    }

    /// Decodes an image (not its embedded thumbnail), at most 1024 px on the
    /// long side, ignoring orientation, into plain RGBA bytes plus its size.
    private static func render(_ data: Data) throws -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let width = props[kCGImagePropertyPixelWidth as String] as? Int,
            let height = props[kCGImagePropertyPixelHeight as String] as? Int
        else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let pixels = context.data else { return nil }
        var result = Data("\(width)x\(height):".utf8)
        result.append(Data(bytes: pixels, count: image.height * image.width * 4))
        return result
    }
}
