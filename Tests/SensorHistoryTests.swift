import XCTest
@testable import HomeAssist

final class SensorHistoryParsingTests: XCTestCase {
    private let start = ISO8601DateFormatter().date(from: "2026-11-27T00:00:00Z")!
    private var end: Date { start.addingTimeInterval(24 * 3600) }

    private func parse(_ json: String) throws -> SensorHistory {
        try SensorHistory.parse(Data(json.utf8), start: start, end: end)
    }

    func testParsesMinimalResponseWithFractionalTimes() throws {
        let h = try parse("""
        [[{"entity_id":"sensor.t","state":"19.5","last_changed":"2026-11-27T01:00:00.123456+00:00"},
          {"state":"20.5","last_changed":"2026-11-27T02:00:00+00:00"}]]
        """)
        XCTAssertEqual(h.runs.count, 1)
        XCTAssertEqual(h.runs[0].map(\.value), [19.5, 20.5, 20.5], "extended to the end of the window")
        XCTAssertEqual(h.runs[0].last?.date, end)
        XCTAssertEqual(h.minimum, 19.5); XCTAssertEqual(h.maximum, 20.5); XCTAssertEqual(h.latest?.value, 20.5)
    }

    func testUnavailableSplitsRunsAndEndsTheLine() throws {
        let h = try parse("""
        [[{"state":"10","last_changed":"2026-11-27T01:00:00+00:00"},
          {"state":"unavailable","last_changed":"2026-11-27T02:00:00+00:00"},
          {"state":"12","last_changed":"2026-11-27T03:00:00+00:00"},
          {"state":"unknown","last_changed":"2026-11-27T04:00:00+00:00"}]]
        """)
        XCTAssertEqual(h.runs.map { $0.map(\.value) }, [[10], [12]], "gaps are not joined; no extension after 'unknown'")
    }

    func testTimesBeforeTheWindowAreClamped() throws {
        let h = try parse(#"[[{"state":"5","last_changed":"2026-11-26T20:00:00+00:00"}]]"#)
        XCTAssertEqual(h.runs[0].first?.date, start)
    }

    func testEmptyAndNonNumericReplies() throws {
        XCTAssertTrue(try parse("[]").isEmpty)
        XCTAssertTrue(try parse("[[]]").isEmpty)
        XCTAssertTrue(try parse(#"[[{"state":"on","last_changed":"2026-11-27T01:00:00+00:00"}]]"#).isEmpty)
    }

    func testNearestPoint() {
        let a = HistoryPoint(date: start, value: 1)
        let b = HistoryPoint(date: start.addingTimeInterval(100), value: 2)
        let h = SensorHistory(runs: [[a], [b]])
        XCTAssertEqual(h.nearest(to: start.addingTimeInterval(30)), a)
        XCTAssertEqual(h.nearest(to: start.addingTimeInterval(80)), b)
        XCTAssertNil(SensorHistory(runs: []).nearest(to: start))
    }

    func testDownsamplingKeepsPeaksEndsAndBoundsTheCount() {
        let points = (0..<5000).map { HistoryPoint(date: start.addingTimeInterval(Double($0)), value: sin(Double($0) / 50)) }
        var spiked = points
        spiked[2500] = HistoryPoint(date: spiked[2500].date, value: 9)
        let thin = SensorHistory(runs: [spiked]).downsampled(maxPoints: 300)
        XCTAssertLessThan(thin.points.count, 400)
        XCTAssertEqual(thin.maximum, 9, "the spike survives thinning")
        XCTAssertEqual(thin.runs[0].first, spiked.first)
        XCTAssertEqual(thin.runs[0].last, spiked.last)
        XCTAssertEqual(thin.runs[0], thin.runs[0].sorted { $0.date < $1.date }, "stays in time order")
    }

    func testSmallHistoryIsLeftAlone() {
        let h = SensorHistory(runs: [[HistoryPoint(date: start, value: 1), HistoryPoint(date: end, value: 2)]])
        XCTAssertEqual(h.downsampled(maxPoints: 300), h)
    }

    func testHasNumericHistory() throws {
        func e(_ id: String, _ state: String, _ attrs: String = "") -> HAEntity {
            try! JSONDecoder().decode(HAEntity.self, from: Data(
                #"{"entity_id":"\#(id)","state":"\#(state)","attributes":{\#(attrs)}}"#.utf8))
        }
        XCTAssertTrue(e("sensor.t", "19.8").hasNumericHistory)
        XCTAssertTrue(e("sensor.t", "unavailable", #""unit_of_measurement":"°C""#).hasNumericHistory)
        XCTAssertFalse(e("sensor.when", "2026-11-27T10:00:00+00:00").hasNumericHistory)
        XCTAssertFalse(e("binary_sensor.door", "on").hasNumericHistory)
        XCTAssertFalse(e("light.a", "on").hasNumericHistory)
    }
}

final class FakeHistorySource: HistorySource, @unchecked Sendable {
    struct Call: Equatable { let entityID: String; let start: Date; let end: Date }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.withLock { _calls } }
    var delay: Duration = .zero
    var result: Result<SensorHistory, Error> = .success(SensorHistory(runs: []))

    func history(entityID: String, start: Date, end: Date) async throws -> SensorHistory {
        lock.withLock { _calls.append(Call(entityID: entityID, start: start, end: end)) }
        try await Task.sleep(for: delay)
        return try result.get()
    }
}

@MainActor
final class SensorHistoryModelTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-27T12:00:00Z")!
    private func series(_ v: Double) -> SensorHistory { SensorHistory(runs: [[HistoryPoint(date: now, value: v)]]) }

    func testLoadsTheRangeEndingNow() async {
        let source = FakeHistorySource()
        source.result = .success(series(1))
        let model = SensorHistoryModel(entityID: "sensor.t", source: source, now: { self.now })
        model.range = .week
        await model.load()
        XCTAssertEqual(source.calls, [.init(entityID: "sensor.t", start: now.addingTimeInterval(-7 * 24 * 3600), end: now)])
        XCTAssertEqual(model.history, series(1))
        XCTAssertFalse(model.isLoading)
    }

    func testFailureIsSurfaced() async {
        let source = FakeHistorySource()
        source.result = .failure(HAError.http(500))
        let model = SensorHistoryModel(entityID: "sensor.t", source: source, now: { self.now })
        await model.load()
        XCTAssertNil(model.history)
        XCTAssertEqual(model.errorMessage, HAError.http(500).errorDescription)
        XCTAssertFalse(model.isLoading)
    }

    func testAnOlderSlowLoadCannotOverwriteANewerOne() async {
        let source = FakeHistorySource()
        source.delay = .milliseconds(150)
        source.result = .success(series(1))
        let model = SensorHistoryModel(entityID: "sensor.t", source: source, now: { self.now })
        async let slow: Void = model.load()
        try? await Task.sleep(for: .milliseconds(30))
        source.delay = .zero
        source.result = .success(series(2))
        model.range = .month
        await model.load()
        await slow
        XCTAssertEqual(model.history, series(2), "the later request wins")
    }
}
