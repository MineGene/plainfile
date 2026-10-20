import Foundation

/// Removes metadata from PNG files by dropping metadata chunks.
///
/// ImageIO doesn't remove PNG metadata when copying, so PNGs are handled
/// here. A PNG is a signature followed by chunks (length, type, data, CRC).
/// Chunks that define the picture are copied byte for byte; text, EXIF, XMP,
/// timestamps, Content Credentials and unknown ancillary chunks are dropped.
/// Pixel data (IDAT) is never touched, so the picture is unchanged.
///
/// Runs inside the parser XPC service. Every length is bounds-checked.
public enum PNGStripper {
    static let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    /// Ancillary chunks that affect how the picture looks, so they are kept.
    /// Critical chunks (upper-case first letter, e.g. IHDR, PLTE, IDAT, IEND)
    /// are always kept.
    static let keptAncillary: Set<String> = [
        "tRNS", "cHRM", "gAMA", "iCCP", "sBIT", "sRGB", "cICP", "mDCv", "cLLi", "bKGD", "pHYs",
    ]

    public static func isPNG(_ data: Data) -> Bool {
        data.count >= signature.count && data.prefix(signature.count) == signature
    }

    /// Returns the PNG with metadata chunks removed, and the types it dropped.
    public static func strip(_ data: Data) throws -> (output: Data, dropped: [String]) {
        guard isPNG(data) else { throw StripError.unreadable }
        let bytes = [UInt8](data)
        var output = Data(signature)
        var dropped: [String] = []
        var offset = signature.count
        var sawEnd = false

        while offset < bytes.count {
            // length (4) + type (4) + data (length) + CRC (4)
            guard offset + 8 <= bytes.count else { throw StripError.unreadable }
            let length =
                Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length <= 0x7FFF_FFFF else { throw StripError.unreadable }
            let typeBytes = bytes[(offset + 4)..<(offset + 8)]
            guard typeBytes.allSatisfy({ (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) })
            else { throw StripError.unreadable }
            let type = String(decoding: typeBytes, as: UTF8.self)
            let end = offset + 12 + length
            guard end <= bytes.count else { throw StripError.unreadable }

            let critical = typeBytes.first.map { (0x41...0x5A).contains($0) } ?? false
            if critical || keptAncillary.contains(type) {
                output.append(contentsOf: bytes[offset..<end])
            } else {
                dropped.append(type)
            }
            offset = end
            if type == "IEND" {
                sawEnd = true
                break  // Anything after IEND is a trailer; drop it.
            }
        }
        guard sawEnd else { throw StripError.unreadable }
        if offset < bytes.count { dropped.append("trailing data") }
        return (output, dropped)
    }
}
