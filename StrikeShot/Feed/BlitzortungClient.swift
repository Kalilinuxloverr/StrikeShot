import Foundation

/// Streams live strikes from the blitzortung.org websocket network with
/// endpoint failover and exponential backoff.
final class BlitzortungClient: @unchecked Sendable {

    enum Status {
        case connecting
        case connected
        case failed(String)
    }

    /// ponytail: hardcoded community endpoints; swap for remote config if they churn.
    static let endpoints: [URL] = (1...8).compactMap {
        URL(string: "ws://ws\($0).blitzortung.org:8080/")
    }

    private static let initMessage = #"{"a":111}"#
    private static let maxBackoffSeconds = 30.0

    var onStatus: ((Status) -> Void)?

    private let lock = NSLock()
    private var runTask: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?

    func strikes() -> AsyncStream<Strike> {
        AsyncStream { continuation in
            let task = Task.detached { [weak self] in
                await self?.run(continuation)
                continuation.finish()
            }
            lock.withLock { runTask = task }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() {
        lock.withLock {
            runTask?.cancel()
            runTask = nil
            // Break a pending receive() so the run loop unwinds promptly.
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
        }
    }

    private func run(_ continuation: AsyncStream<Strike>.Continuation) async {
        var endpointIndex = 0
        var backoff = 1.0
        var consecutiveFailures = 0
        while !Task.isCancelled {
            let url = Self.endpoints[endpointIndex % Self.endpoints.count]
            onStatus?(.connecting)
            do {
                try await pump(url: url, into: continuation) {
                    backoff = 1
                    consecutiveFailures = 0
                    self.onStatus?(.connected)
                }
            } catch {
                guard !Task.isCancelled else { break }
                consecutiveFailures += 1
                if consecutiveFailures >= Self.endpoints.count {
                    // Every endpoint refused in a row: surface it, keep retrying.
                    onStatus?(.failed(error.localizedDescription))
                }
                endpointIndex += 1
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, Self.maxBackoffSeconds)
            }
        }
    }

    /// Connects, sends the init message and yields strikes until the socket dies.
    private func pump(
        url: URL,
        into continuation: AsyncStream<Strike>.Continuation,
        onOpen: () -> Void
    ) async throws {
        let socket = URLSession.shared.webSocketTask(with: url)
        lock.withLock { self.socket = socket }
        defer {
            socket.cancel(with: .goingAway, reason: nil)
            lock.withLock { if self.socket === socket { self.socket = nil } }
        }
        socket.resume()
        try await socket.send(.string(Self.initMessage))
        onOpen()
        while !Task.isCancelled {
            let message = try await socket.receive()
            guard case .string(let payload) = message else { continue }
            if let strike = BlitzortungDecoder.strike(fromPayload: payload) {
                continuation.yield(strike)
            }
        }
    }
}
