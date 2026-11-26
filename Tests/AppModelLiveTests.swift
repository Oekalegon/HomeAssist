import XCTest
@testable import HomeAssist

/// Serves canned REST responses: `GET /api/states` returns `body`; POSTs are counted and
/// answered after a short delay so tests can overlap two toggles.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data("[]".utf8)
    nonisolated(unsafe) static var postCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isPost = request.httpMethod == "POST"
        if isPost { Self.postCount += 1 }
        nonisolated(unsafe) let this = self // URLProtocol isn't Sendable; it is only used here
        if isPost {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { this.respond(isPost: true) }
        } else {
            respond(isPost: false)
        }
    }

    private func respond(isPost: Bool) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: isPost ? Data("[]".utf8) : Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A live source the test drives by hand. Every `updates()` call is one "connection".
final class FakeLiveSource: LiveUpdateSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<LiveUpdate, Error>.Continuation] = []

    var connectionCount: Int { lock.withLock { continuations.count } }

    func updates() -> AsyncThrowingStream<LiveUpdate, Error> {
        AsyncThrowingStream { continuation in self.lock.withLock { self.continuations.append(continuation) } }
    }
    func send(_ update: LiveUpdate) { lock.withLock { continuations.last }?.yield(update) }
    func fail(_ error: Error) { lock.withLock { continuations.last }?.finish(throwing: error) }
}

@MainActor
final class AppModelLiveTests: XCTestCase {
    private let statesJSON = #"[{"entity_id":"light.a","state":"off","attributes":{"friendly_name":"A"}}]"#

    private func makeModel(source: FakeLiveSource) -> AppModel {
        StubURLProtocol.body = Data(statesJSON.utf8)
        StubURLProtocol.postCount = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let client = HAClient(urlString: "http://ha.test:8123", token: "t", session: URLSession(configuration: config))!
        let model = AppModel(client: client, makeLiveSource: { _ in source })
        model.reconnectDelay = 0.01...0.05
        model.changeBatchInterval = .milliseconds(20)
        addTeardownBlock { await MainActor.run { model.stopLiveUpdates() } }
        return model
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func change(_ state: String) -> LiveUpdate {
        let json = #"{"entity_id":"light.a","state":"\#(state)","attributes":{"friendly_name":"A"}}"#
        return .change(StateChange(entityId: "light.a", newState: try! JSONDecoder().decode(HAEntity.self, from: Data(json.utf8))))
    }

    private func goLive(_ model: AppModel, _ source: FakeLiveSource) async {
        model.startLiveUpdates()
        let opened = await waitUntil { source.connectionCount == 1 }
        XCTAssertTrue(opened)
        source.send(.connected)
        let live = await waitUntil { model.isLive && model.entities.count == 1 }
        XCTAssertTrue(live, "should be live with the snapshot loaded")
    }

    func testConnectedLoadsSnapshotThenAppliesBatchedChanges() async {
        let source = FakeLiveSource(), model = makeModel(source: source)
        await goLive(model, source)
        XCTAssertEqual(model.entities.first?.state, "off")

        source.send(change("on")); source.send(change("off")); source.send(change("on"))
        let applied = await waitUntil { model.entities.first?.state == "on" }
        XCTAssertTrue(applied, "the last change in a burst wins")
    }

    func testReconnectsAfterStreamFailureAndRefetches() async {
        let source = FakeLiveSource(), model = makeModel(source: source)
        await goLive(model, source)

        source.fail(URLError(.networkConnectionLost))
        let down = await waitUntil { !model.isLive && model.liveStatus != nil }
        XCTAssertTrue(down, "failure is surfaced, not swallowed")
        let reopened = await waitUntil { source.connectionCount == 2 }
        XCTAssertTrue(reopened, "reconnects after backoff")

        source.send(.connected)
        let live = await waitUntil { model.isLive && model.liveStatus == nil }
        XCTAssertTrue(live)
    }

    func testUnauthorizedStopsWithoutRetrying() async {
        let source = FakeLiveSource(), model = makeModel(source: source)
        await goLive(model, source)

        source.fail(HAError.unauthorized)
        let surfaced = await waitUntil { model.errorMessage != nil }
        XCTAssertTrue(surfaced)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(source.connectionCount, 1, "a rejected token must not be retried")
        XCTAssertFalse(model.isLive)
    }

    func testStopDiscardsLateEvents() async {
        let source = FakeLiveSource(), model = makeModel(source: source)
        await goLive(model, source)

        model.stopLiveUpdates()
        source.send(change("on"))
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.entities.first?.state, "off")
        XCTAssertFalse(model.isLive)
    }

    func testStopThenStartRunsOnlyOneConnection() async {
        let source = FakeLiveSource(), model = makeModel(source: source)
        model.startLiveUpdates()
        model.stopLiveUpdates()
        model.startLiveUpdates()
        let opened = await waitUntil { source.connectionCount >= 1 }
        XCTAssertTrue(opened)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(source.connectionCount, 1, "the stale run must not open a second connection")
    }

    func testToggleIgnoredWhileSameEntityIsInFlight() async {
        let source = FakeLiveSource(), model = makeModel(source: source)
        await model.refresh()
        let entity = model.entities[0]

        async let first: Void = model.toggle(entity)
        async let second: Void = model.toggle(entity)
        _ = await (first, second)
        XCTAssertEqual(StubURLProtocol.postCount, 1)

        await model.toggle(entity) // allowed again once the first finished
        XCTAssertEqual(StubURLProtocol.postCount, 2)
    }
}
