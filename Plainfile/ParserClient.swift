import Foundation
import PlainfileCore

/// Talks to the isolated parser service. One connection per job, and every
/// job has a time limit: if the parser hangs (for example on a file crafted
/// to make it loop), the connection is cut and the file is reported as
/// unreadable instead of blocking the app.
struct ParserClient: Sendable {
    static let timeLimit: TimeInterval = 30

    enum ClientError: LocalizedError {
        case service(String)
        case badReply
        case timedOut

        var errorDescription: String? {
            switch self {
            case .service(let message): message
            case .badReply: "This file could not be read."
            case .timedOut: "Reading this file took too long, so Plainfile stopped."
            }
        }
    }

    func scanImage(_ data: Data) async throws -> ScanReport {
        try await run { service, once in
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

    func stripImage(_ data: Data, removing ids: Set<String>) async throws -> Data {
        try await run { service, once in
            service.stripImage(data, removing: Array(ids)) { output, message in
                if let message {
                    once.resume(throwing: ClientError.service(message))
                } else if let output {
                    once.resume(returning: output)
                } else {
                    once.resume(throwing: ClientError.badReply)
                }
            }
        }
    }

    func imagesMatch(_ original: Data, _ stripped: Data) async throws -> Bool {
        try await run { service, once in
            service.imagesMatch(original, stripped) { match, message in
                if let message {
                    once.resume(throwing: ClientError.service(message))
                } else {
                    once.resume(returning: match)
                }
            }
        }
    }

    /// Opens a fresh connection for one call, enforces the time limit, and
    /// turns a crash or cut connection into a plain error.
    private func run<T: Sendable>(
        _ call: (ParserServiceProtocol, ResumeOnce<T>) -> Void
    ) async throws -> T {
        let connection = NSXPCConnection(serviceName: ParserService.name)
        connection.remoteObjectInterface = NSXPCInterface(with: ParserServiceProtocol.self)
        connection.resume()
        let job = Job(connection)
        defer { job.finish() }

        let deadline = DispatchWorkItem { job.timeOut() }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.timeLimit, execute: deadline)
        defer { deadline.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                // A crash or a cut connection; never show the raw XPC error.
                once.resume(throwing: job.timedOut ? ClientError.timedOut : ClientError.badReply)
            }
            guard let service = proxy as? ParserServiceProtocol else {
                once.resume(throwing: ClientError.badReply)
                return
            }
            call(service, once)
        }
    }
}

/// Owns one job's connection so the deadline can cut it from another thread.
private final class Job: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NSXPCConnection
    private var didTimeOut = false

    init(_ connection: NSXPCConnection) { self.connection = connection }

    var timedOut: Bool { lock.withLock { didTimeOut } }

    func timeOut() {
        lock.withLock { didTimeOut = true }
        connection.invalidate()
    }

    func finish() { connection.invalidate() }
}

/// XPC can call both the reply and the error handler; resume only once.
final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    private func take() -> CheckedContinuation<T, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }

    func resume(returning value: T) { take()?.resume(returning: value) }
    func resume(throwing error: Error) { take()?.resume(throwing: error) }
}
