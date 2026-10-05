import Foundation
import CastCore

public enum UpstreamError: Error, Equatable {
    case badStatus(Int)
    case notHTTP
    case cancelled
}

/// Downloads media from the original site with the browser-like headers it expects.
/// `data` loads small resources (playlists, keys, segments); `stream` pipes large files
/// with back-pressure (the task is suspended while too much is buffered).
public final class UpstreamFetcher: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let dataSession: URLSession
    private var streamSession: URLSession!
    private let lock = NSLock()
    private var states: [Int: StreamState] = [:]

    public override init() {
        dataSession = URLSession(configuration: Self.configuration())
        super.init()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "telecast.upstream"
        streamSession = URLSession(configuration: Self.configuration(), delegate: self, delegateQueue: queue)
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = 6
        return configuration
    }

    func makeRequest(_ url: URL, context: RequestContext, range: String?, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        for (name, value) in context.headerFields {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return request
    }

    public func data(_ url: URL, context: RequestContext, range: String? = nil,
                     timeout: TimeInterval = 20) async throws -> (HTTPURLResponse, Data) {
        let request = makeRequest(url, context: context, range: range, timeout: timeout)
        let (data, response) = try await dataSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpstreamError.notHTTP }
        return (http, data)
    }

    public func stream(_ url: URL, context: RequestContext, range: String?) async throws -> UpstreamStream {
        let request = makeRequest(url, context: context, range: range, timeout: 30)
        let task = streamSession.dataTask(with: request)
        let state = StreamState()
        state.task = task
        lock.withLock { states[task.taskIdentifier] = state }
        task.resume()
        do {
            let response = try await state.waitForResponse()
            return UpstreamStream(response: response, state: state, task: task)
        } catch {
            task.cancel()
            throw error
        }
    }

    // MARK: URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let state = lock.withLock { states[dataTask.taskIdentifier] }
        if let http = response as? HTTPURLResponse {
            state?.receive(response: http)
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let state = lock.withLock { states[dataTask.taskIdentifier] }
        state?.receive(data: data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let state = lock.withLock { states.removeValue(forKey: task.taskIdentifier) }
        state?.complete(error: error)
    }
}

/// A large upstream download consumed chunk by chunk.
public final class UpstreamStream: @unchecked Sendable {
    public let response: HTTPURLResponse
    private let state: StreamState
    private let task: URLSessionDataTask

    init(response: HTTPURLResponse, state: StreamState, task: URLSessionDataTask) {
        self.response = response
        self.state = state
        self.task = task
    }

    /// Next chunk, or nil at the end.
    public func next() async throws -> Data? {
        try await state.next()
    }

    public func cancel() {
        task.cancel()
    }
}

final class StreamState: @unchecked Sendable {
    static let highWater = 8 * 1024 * 1024
    static let lowWater = 2 * 1024 * 1024

    private let lock = NSLock()
    private var buffer: [Data] = []
    private var buffered = 0
    private var finished = false
    private var failure: Error?
    private var response: HTTPURLResponse?
    private var responseWaiter: CheckedContinuation<HTTPURLResponse, Error>?
    private var dataWaiter: CheckedContinuation<Data?, Error>?
    private var suspended = false
    weak var task: URLSessionDataTask?

    func waitForResponse() async throws -> HTTPURLResponse {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPURLResponse, Error>) in
            let ready: Result<HTTPURLResponse, Error>? = lock.withLock {
                if let response { return .success(response) }
                if let failure { return .failure(failure) }
                if finished { return .failure(UpstreamError.cancelled) }
                responseWaiter = continuation
                return nil
            }
            if let ready { continuation.resume(with: ready) }
        }
    }

    func receive(response: HTTPURLResponse) {
        let waiter: CheckedContinuation<HTTPURLResponse, Error>? = lock.withLock {
            self.response = response
            let waiting = responseWaiter
            responseWaiter = nil
            return waiting
        }
        waiter?.resume(returning: response)
    }

    func receive(data: Data) {
        let waiter: CheckedContinuation<Data?, Error>? = lock.withLock {
            if let waiting = dataWaiter {
                dataWaiter = nil
                return waiting
            }
            buffer.append(data)
            buffered += data.count
            if buffered > Self.highWater, !suspended {
                suspended = true
                task?.suspend()
            }
            return nil
        }
        waiter?.resume(returning: data)
    }

    func complete(error: Error?) {
        let pending: (CheckedContinuation<HTTPURLResponse, Error>?, CheckedContinuation<Data?, Error>?, Error?) = lock.withLock {
            finished = true
            if let error, (error as? URLError)?.code != .cancelled {
                failure = error
            }
            let responseWaiting = responseWaiter
            let dataWaiting = dataWaiter
            responseWaiter = nil
            dataWaiter = nil
            return (responseWaiting, dataWaiting, failure)
        }
        pending.0?.resume(throwing: pending.2 ?? UpstreamError.cancelled)
        if let dataWaiting = pending.1 {
            if let failure = pending.2 {
                dataWaiting.resume(throwing: failure)
            } else {
                dataWaiting.resume(returning: nil)
            }
        }
    }

    func next() async throws -> Data? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            let ready: Result<Data?, Error>? = lock.withLock {
                if !buffer.isEmpty {
                    let chunk = buffer.removeFirst()
                    buffered -= chunk.count
                    if suspended, buffered < Self.lowWater {
                        suspended = false
                        task?.resume()
                    }
                    return .success(chunk)
                }
                if let failure { return .failure(failure) }
                if finished { return .success(nil) }
                dataWaiter = continuation
                return nil
            }
            if let ready { continuation.resume(with: ready) }
        }
    }
}
