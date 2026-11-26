import Foundation

/// One item from a live connection to Home Assistant.
enum LiveUpdate: Sendable {
    /// Authenticated and subscribed. Fetch a full state snapshot now: anything that changed
    /// before this point was not delivered as an event.
    case connected
    case change(StateChange)
}

/// A source of live state changes. ``HAWebSocketClient`` is the real one; tests use a fake.
///
/// Each call to ``updates()`` opens one connection. The stream ends (with an error if the
/// connection failed) when the connection closes, so callers own reconnect and backoff.
protocol LiveUpdateSource: Sendable {
    func updates() -> AsyncThrowingStream<LiveUpdate, Error>
}
