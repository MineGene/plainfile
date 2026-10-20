import Foundation

/// The interface between the main app and the isolated parser service.
///
/// The app sends bytes; the service replies with plain data (a JSON-encoded
/// `ScanReport`, cleaned image bytes or a yes/no) or an error message. Plain
/// data types only, so a compromised service can send nothing back but data.
@objc public protocol ParserServiceProtocol {
    func scanImage(_ data: Data, reply: @escaping @Sendable (Data?, String?) -> Void)

    /// Returns the image with the metadata fields whose IDs are listed removed.
    func stripImage(
        _ data: Data, removing ids: [String], reply: @escaping @Sendable (Data?, String?) -> Void)

    /// Whether two images show exactly the same picture.
    func imagesMatch(
        _ original: Data, _ stripped: Data, reply: @escaping @Sendable (Bool, String?) -> Void)
}

public enum ParserService {
    public static let name = "com.minegene.plainfile.parser"
}
