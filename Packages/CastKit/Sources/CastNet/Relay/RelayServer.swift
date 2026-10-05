import Foundation
import Network
import CastCore

/// The phone-side HTTP server the TV reads from. Serves bundled test media under `/t/`
/// and the registered relay sessions under `/s/<id>/…` (see `RelayRoute`).
public final class RelayServer: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "telecast.relay.server")
    private let testFiles: URL?
    let fetcher: UpstreamFetcher
    private var listener: NWListener?
    private var currentPort: UInt16?
    private var handlers: [String: RelaySessionHandler] = [:]
    private var contacts: [String: Date] = [:]
    private var requestHook: (@Sendable (HTTPRequestHead) -> Void)?

    public init(testFiles: URL?, fetcher: UpstreamFetcher = UpstreamFetcher()) {
        self.testFiles = testFiles
        self.fetcher = fetcher
    }

    public var port: UInt16? { lock.withLock { currentPort } }

    public var isRunning: Bool { lock.withLock { listener != nil && currentPort != nil } }

    /// Test/debug hook called for every request head.
    public var onRequest: (@Sendable (HTTPRequestHead) -> Void)? {
        get { lock.withLock { requestHook } }
        set { lock.withLock { requestHook = newValue } }
    }

    public func start() async throws {
        if isRunning { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        let once = ResumeOnce()
        let port: UInt16 = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume(returning: listener?.port?.rawValue ?? 0) }
                case .failed(let error):
                    castLog("relay", "Serveur relais en échec : \(error)")
                    if let listener { self?.markStopped(listener) }
                    if once.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if let listener { self?.markStopped(listener) }
                    if once.claim() { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        lock.withLock {
            self.listener = listener
            self.currentPort = port
        }
        castLog("relay", "Relais prêt sur le port \(port)")
    }

    /// Restarts the listener if iOS invalidated it (after a suspension).
    public func ensureRunning() async throws {
        if !isRunning { try await start() }
    }

    public func stop() {
        let current: NWListener? = lock.withLock {
            let running = listener
            listener = nil
            currentPort = nil
            handlers.removeAll()
            contacts.removeAll()
            return running
        }
        current?.cancel()
    }

    public func baseURL(host: String) -> URL? {
        guard let port else { return nil }
        return URL(string: "http://\(host):\(port)")
    }

    /// The URL the TV must use: the phone's Wi-Fi address.
    public func lanBaseURL() -> URL? {
        baseURL(host: NetworkInterfaces.wifi()?.address ?? "127.0.0.1")
    }

    public func register(_ config: RelaySessionConfig) {
        let handler = RelaySessionHandler(config: config, fetcher: fetcher)
        lock.withLock { handlers[config.id] = handler }
        castLog("relay", "Session \(config.id) (\(config.mode.rawValue)) → \(config.mediaPlaylistURL ?? config.sourceURL)")
    }

    public func unregister(_ id: String) {
        lock.withLock {
            handlers[id] = nil
            contacts[id] = nil
        }
    }

    public func lastContact(_ id: String) -> Date? {
        lock.withLock { contacts[id] }
    }

    // MARK: - Connections

    private func markStopped(_ stopped: NWListener) {
        lock.withLock {
            if listener === stopped {
                listener = nil
                currentPort = nil
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(connection, buffer: Data())
    }

    private func receiveHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var accumulated = buffer
            if let data { accumulated.append(data) }
            if HTTPRequestParser.headerEnd(in: accumulated) != nil, let head = HTTPRequestParser.parse(accumulated) {
                Task { await self.handle(head, connection: connection) }
            } else if error != nil || isComplete || accumulated.count > 64 * 1024 {
                connection.cancel()
            } else {
                self.receiveHead(connection, buffer: accumulated)
            }
        }
    }

    private func handle(_ head: HTTPRequestHead, connection: NWConnection) async {
        let writer = ResponseWriter(connection: connection)
        defer { writer.finish() }
        onRequest?(head)
        let isHead = head.method == "HEAD"
        guard head.method == "GET" || isHead else {
            await writer.respond(status: 405)
            return
        }
        let route = RelayRoute.parse(path: head.path)
        castLog("relay", "\(head.method) \(head.path)\(head.header("range").map { " Range=\($0)" } ?? "")")
        switch route {
        case .health:
            await writer.respond(status: 200, body: Data("ok".utf8), isHead: isHead)
        case .testFile(let relative):
            await serveTestFile(relative, head: head, writer: writer)
        case .notFound:
            await writer.respond(status: 404, body: Data("not found".utf8), isHead: isHead)
        default:
            guard let sessionID = route.sessionID, let handler = lock.withLock({ handlers[sessionID] }) else {
                await writer.respond(status: 404, body: Data("unknown session".utf8), isHead: isHead)
                return
            }
            lock.withLock { contacts[sessionID] = Date() }
            let base = head.header("host").flatMap { URL(string: "http://\($0)") } ?? lanBaseURL()
                ?? URL(string: "http://127.0.0.1")!
            await handler.handle(route: route, head: head, writer: writer, base: base)
        }
    }

    // MARK: - Test files

    private func serveTestFile(_ relative: String, head: HTTPRequestHead, writer: ResponseWriter) async {
        let isHead = head.method == "HEAD"
        guard let root = testFiles else {
            await writer.respond(status: 404, isHead: isHead)
            return
        }
        let file = root.appendingPathComponent(relative)
        guard file.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else {
            await writer.respond(status: 404, isHead: isHead)
            return
        }
        let type = Self.contentType(forExtension: file.pathExtension)
        var status = 200
        var body = data
        var headers: [(String, String)] = [("Content-Type", type), ("Accept-Ranges", "bytes"), ("Connection", "close"),
                                           DLNAHeaders.cors]
        if let rangeHeader = head.header("range"), let range = Self.byteRange(rangeHeader, size: data.count) {
            status = 206
            body = data.subdata(in: range)
            headers.append(("Content-Range", "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)"))
        }
        headers.append(("Content-Length", String(body.count)))
        headers += DLNAHeaders.streaming(mime: type, seekable: true,
                                         requested: head.header("getcontentfeatures.dlna.org") != nil)
        do {
            try await writer.sendHead(HTTPResponseHead(status: status, headers: headers))
            if !isHead { try await writer.send(body) }
        } catch {
            // the TV went away
        }
    }

    static func contentType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts": return "video/mp2t"
        case "m4s": return "video/iso.segment"
        case "aac": return "audio/aac"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "mkv": return "video/x-matroska"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }

    /// `bytes=a-b`, `bytes=a-`, `bytes=-n` → half-open range within `size`.
    static func byteRange(_ header: String, size: Int) -> Range<Int>? {
        guard header.lowercased().hasPrefix("bytes="), size > 0 else { return nil }
        let spec = header.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = Int(parts[1]), suffix > 0 else { return nil }
            return max(0, size - suffix)..<size
        }
        guard let start = Int(parts[0]), start < size else { return nil }
        let end = parts[1].isEmpty ? size - 1 : min(Int(parts[1]) ?? size - 1, size - 1)
        guard end >= start else { return nil }
        return start..<(end + 1)
    }
}
