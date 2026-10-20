import Foundation
import PlainfileCore

/// Isolated parser service. It has no network or user-file entitlements:
/// it only ever sees the bytes the main app sends for one job.
final class ParserServiceImplementation: NSObject, ParserServiceProtocol {
    func scanImage(_ data: Data, reply: @escaping @Sendable (Data?, String?) -> Void) {
        do {
            let report = try ImageScanner.scan(data: data)
            reply(try JSONEncoder().encode(report), nil)
        } catch let error as ScanError {
            reply(nil, error.description)
        } catch {
            reply(nil, "This file could not be read.")
        }
    }
}

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
        -> Bool
    {
        connection.exportedInterface = NSXPCInterface(with: ParserServiceProtocol.self)
        connection.exportedObject = ParserServiceImplementation()
        connection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
