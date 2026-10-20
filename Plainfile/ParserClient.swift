import Foundation
import PlainfileCore

/// Talks to the isolated parser service. One connection per job.
struct ParserClient: Sendable {
    enum ClientError: LocalizedError {
        case service(String)
        case badReply

        var errorDescription: String? {
            switch self {
            case .service(let message): message
            case .badReply: "The parser returned an unexpected result."
            }
        }
    }

    func scanImage(_ data: Data) async throws -> ScanReport {
        let connection = NSXPCConnection(serviceName: ParserService.name)
        connection.remoteObjectInterface = NSXPCInterface(with: ParserServiceProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(throwing: error)
            }
            guard let service = proxy as? ParserServiceProtocol else {
                once.resume(throwing: ClientError.badReply)
                return
            }
            service.scanImage(data) { json, message in
                if let message {
                    once.resume(throwing: ClientError.service(message))
                } else if let json, let report = try? JSONDecoder().decode(ScanReport.self, from: json) {
                    once.resume(returning: report)
                } else {
                    once.resume(throwing: ClientError.badReply)
                }
            }
        }
    }
}

/// XPC can call both the reply and the error handler; resume only once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ScanReport, Error>?

    init(_ continuation: CheckedContinuation<ScanReport, Error>) { self.continuation = continuation }

    private func take() -> CheckedContinuation<ScanReport, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }

    func resume(returning value: ScanReport) { take()?.resume(returning: value) }
    func resume(throwing error: Error) { take()?.resume(throwing: error) }
}
