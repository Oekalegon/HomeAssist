import Foundation

/// Streams live state changes from Home Assistant's WebSocket API.
///
/// One call to ``updates()`` opens one connection. The stream ends (with an error if the
/// connection failed) when the socket closes, so callers own reconnect and backoff.
struct HAWebSocketClient: Sendable {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    enum Update: Sendable {
        /// Authenticated and subscribed. Fetch a full state snapshot now: anything that changed
        /// before this point was not delivered as an event.
        case connected
        case change(StateChange)
    }

    private static let subscribeID = 1
    private static let pingInterval: Duration = .seconds(30)

    /// `http(s)://host/…` → `ws(s)://host/…/api/websocket`.
    static func webSocketURL(from baseURL: URL) -> URL? {
        guard var comps = URLComponents(url: baseURL.appending(path: "api/websocket"),
                                        resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        return comps.url
    }

    func updates() -> AsyncThrowingStream<Update, Error> {
        AsyncThrowingStream { continuation in
            guard let url = Self.webSocketURL(from: baseURL) else {
                continuation.finish(throwing: HAError.invalidURL)
                return
            }
            let socket = session.webSocketTask(with: url)
            socket.resume()

            // Detects half-dead connections: a failed ping closes the socket, which makes
            // `receive()` throw and ends the stream.
            let pinger = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pingInterval)
                    socket.sendPing { error in
                        if error != nil { socket.cancel(with: .abnormalClosure, reason: nil) }
                    }
                }
            }
            let reader = Task {
                do {
                    try await self.read(socket, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                pinger.cancel()
                reader.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func read(_ socket: URLSessionWebSocketTask,
                      into continuation: AsyncThrowingStream<Update, Error>.Continuation) async throws {
        while true {
            let data: Data
            switch try await socket.receive() {
            case .data(let d): data = d
            case .string(let s): data = Data(s.utf8)
            @unknown default: continue
            }
            switch try HAWebSocketMessage.parse(data) {
            case .authRequired:
                try await send(["type": "auth", "access_token": token], on: socket)
            case .authOk:
                try await send(["id": Self.subscribeID, "type": "subscribe_events",
                                "event_type": "state_changed"], on: socket)
            case .authInvalid:
                throw HAError.unauthorized
            case .result(let id, let success) where id == Self.subscribeID:
                guard success else { throw HAError.http(-1) }
                continuation.yield(.connected)
            case .stateChanged(let change):
                continuation.yield(.change(change))
            case .result, .other:
                break
            }
        }
    }

    private func send(_ object: [String: Any], on socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
}
