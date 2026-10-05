import Foundation
import Network
import CastCore

/// Writes one HTTP response on an accepted connection, with back-pressure.
final class ResponseWriter: @unchecked Sendable {
    let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func send(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func sendHead(_ head: HTTPResponseHead) async throws {
        try await send(head.serialized())
    }

    /// Simple complete response (head + small body).
    func respond(status: Int, type: String = "text/plain; charset=utf-8", body: Data = Data(), isHead: Bool = false,
                 extraHeaders: [(String, String)] = []) async {
        var headers: [(String, String)] = [("Content-Type", type), ("Content-Length", String(body.count)),
                                           ("Connection", "close"), DLNAHeaders.cors]
        headers += extraHeaders
        do {
            try await sendHead(HTTPResponseHead(status: status, headers: headers))
            if !isHead { try await send(body) }
        } catch {
            // the TV went away
        }
    }

    /// Ends the response: half-closes the connection once pending data is sent.
    func finish() {
        let connection = self.connection
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// Resumes a continuation at most once.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}
