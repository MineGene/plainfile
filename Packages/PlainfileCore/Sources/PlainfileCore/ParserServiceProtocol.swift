import Foundation

/// The interface between the main app and the isolated parser service.
///
/// The app sends bytes; the service replies with a JSON-encoded `ScanReport`
/// or an error message. Plain data types only, so a compromised service can
/// send nothing back but data.
@objc public protocol ParserServiceProtocol {
    func scanImage(_ data: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
}

public enum ParserService {
    public static let name = "com.minegene.plainfile.parser"
}
