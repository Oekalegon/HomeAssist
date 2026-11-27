import Foundation

struct HistoryPoint: Equatable, Sendable, Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// How far back the chart looks.
enum HistoryRange: CaseIterable, Identifiable, Sendable {
    case day, week, month

    var id: Self { self }
    var title: String {
        switch self {
        case .day: "24 h"
        case .week: "7 d"
        case .month: "30 d"
        }
    }
    var duration: TimeInterval {
        switch self {
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        case .month: 30 * 24 * 3600
        }
    }
}

/// Where history comes from. `HAClient` is the real one; tests use a fake.
protocol HistorySource: Sendable {
    func history(entityID: String, start: Date, end: Date) async throws -> SensorHistory
}

/// The numeric history of one sensor, as runs of points.
///
/// A new run starts after every stretch where the sensor was `unavailable`, `unknown` or
/// otherwise not a number, so the chart shows a gap there instead of a misleading line.
struct SensorHistory: Equatable, Sendable {
    var runs: [[HistoryPoint]]

    var points: [HistoryPoint] { runs.flatMap { $0 } }
    var isEmpty: Bool { runs.allSatisfy(\.isEmpty) }
    var latest: HistoryPoint? { runs.last?.last }
    var minimum: Double? { points.map(\.value).min() }
    var maximum: Double? { points.map(\.value).max() }

    /// The point closest in time to `date`, for scrubbing.
    func nearest(to date: Date) -> HistoryPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    // MARK: Parsing

    private struct RawState: Decodable {
        let state: String
        let lastChanged: String?
        let lastUpdated: String?
        enum CodingKeys: String, CodingKey { case state, lastChanged = "last_changed", lastUpdated = "last_updated" }
    }

    /// Parses Home Assistant's history reply (`[[{state, last_changed}, …]]`).
    ///
    /// Times before `start` are clamped to `start`, and a sensor that is still reporting a number
    /// at the end of the window gets a final point at `end` so the line reaches the right edge.
    static func parse(_ data: Data, start: Date, end: Date) throws -> SensorHistory {
        guard let states = try JSONDecoder().decode([[RawState]].self, from: data).first else {
            return SensorHistory(runs: [])
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func date(_ text: String) -> Date? { fractional.date(from: text) ?? plain.date(from: text) }

        var runs: [[HistoryPoint]] = []
        var current: [HistoryPoint] = []
        for raw in states {
            guard let when = (raw.lastChanged ?? raw.lastUpdated).flatMap(date) else { continue }
            if let value = Double(raw.state) {
                current.append(HistoryPoint(date: min(max(when, start), end), value: value))
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if let last = current.last {
            if last.date < end { current.append(HistoryPoint(date: end, value: last.value)) }
            runs.append(current)
        }
        return SensorHistory(runs: runs)
    }

    // MARK: Thinning

    /// Reduces the history to roughly `maxPoints`, keeping each stretch's highs and lows so
    /// peaks survive. A month of readings can be thousands of points; the chart needs a few hundred.
    func downsampled(maxPoints: Int) -> SensorHistory {
        let total = runs.reduce(0) { $0 + $1.count }
        guard total > maxPoints, maxPoints >= 4 else { return self }
        let ratio = Double(maxPoints) / Double(total)
        return SensorHistory(runs: runs.map { Self.thin($0, budget: max(2, Int(Double($0.count) * ratio))) })
    }

    private static func thin(_ run: [HistoryPoint], budget: Int) -> [HistoryPoint] {
        guard run.count > budget, let first = run.first, let last = run.last else { return run }
        let size = Int((Double(run.count) / Double(max(1, budget / 2))).rounded(.up))
        var out: [HistoryPoint] = []
        for lower in stride(from: 0, to: run.count, by: size) {
            let slice = run[lower..<min(lower + size, run.count)]
            guard let low = slice.min(by: { $0.value < $1.value }),
                  let high = slice.max(by: { $0.value < $1.value }) else { continue }
            out.append(contentsOf: low.date == high.date ? [low] : [low, high].sorted { $0.date < $1.date })
        }
        if out.first != first { out.insert(first, at: 0) }
        if out.last != last { out.append(last) }
        return out
    }
}

extension HAEntity {
    /// Whether the history chart applies: a sensor that reports numbers.
    var hasNumericHistory: Bool {
        domain == "sensor" && (unit != nil || Double(state) != nil)
    }
}
