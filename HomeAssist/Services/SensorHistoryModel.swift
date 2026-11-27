import Foundation
import Observation

/// Loads the history chart's data for one sensor and range.
@MainActor @Observable
final class SensorHistoryModel {
    var range: HistoryRange = .day
    private(set) var history: SensorHistory?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// How many points the chart gets, after thinning.
    static let maxPoints = 300

    private let entityID: String
    private let source: any HistorySource
    private let now: () -> Date
    /// Bumped on every load. A load that finishes after a newer one started is ignored, so
    /// quickly switching ranges can't leave the chart showing the wrong one.
    private var generation = 0

    init(entityID: String, source: any HistorySource, now: @escaping () -> Date = Date.init) {
        self.entityID = entityID
        self.source = source
        self.now = now
    }

    /// Loads the current `range`, clearing what was shown so the chart never mislabels data.
    func load() async {
        generation += 1
        let current = generation
        history = nil
        errorMessage = nil
        isLoading = true
        let end = now()
        do {
            let result = try await source.history(entityID: entityID,
                                                  start: end.addingTimeInterval(-range.duration), end: end)
            guard current == generation, !Task.isCancelled else { return }
            history = result.downsampled(maxPoints: Self.maxPoints)
            isLoading = false
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
