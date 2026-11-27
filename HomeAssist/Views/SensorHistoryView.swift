import Charts
import SwiftUI

/// The history chart shown in a sensor's detail sheet: a range picker, the value under the
/// finger (or the latest), the chart, and the high and low for the range.
struct SensorHistoryView: View {
    let entity: HAEntity
    @State private var model: SensorHistoryModel
    @State private var selectedDate: Date?

    init(entity: HAEntity, source: any HistorySource) {
        self.entity = entity
        _model = State(initialValue: SensorHistoryModel(entityID: entity.entityId, source: source))
    }

    private var unit: String { entity.unit.map { " \($0)" } ?? "" }

    private var shown: HistoryPoint? {
        guard let history = model.history else { return nil }
        return selectedDate.flatMap(history.nearest(to:)) ?? history.latest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: Binding(get: { model.range }, set: { model.range = $0 })) {
                ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            header
            content.frame(height: 200)
            if let low = model.history?.minimum, let high = model.history?.maximum {
                HStack {
                    Text("Low \(EntityFormat.number(low))\(unit)")
                    Spacer()
                    Text("High \(EntityFormat.number(high))\(unit)")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: model.range) { await model.load() }
    }

    @ViewBuilder private var header: some View {
        if let shown {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(EntityFormat.number(shown.value))\(unit)").font(.title2.weight(.semibold))
                Text(shown.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let message = model.errorMessage {
            VStack(spacing: 8) {
                Text(message).font(.footnote).foregroundStyle(.red)
                Button("Try again") { Task { await model.load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let history = model.history {
            if history.isEmpty {
                ContentUnavailableView("No history for this period", systemImage: "chart.xyaxis.line")
            } else {
                chart(history)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chart(_ history: SensorHistory) -> some View {
        let low = history.minimum ?? 0, high = history.maximum ?? 0
        let pad = max((high - low) * 0.1, 0.5)
        let floor = low - pad
        return Chart {
            ForEach(Array(history.runs.enumerated()), id: \.offset) { index, run in
                ForEach(run) { point in
                    AreaMark(x: .value("Time", point.date), yStart: .value("Floor", floor),
                             yEnd: .value("Value", point.value), series: .value("Run", "area\(index)"))
                        .foregroundStyle(.tint.opacity(0.15))
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value),
                             series: .value("Run", "line\(index)"))
                        .foregroundStyle(.tint)
                }
                if run.count == 1, let only = run.first {
                    PointMark(x: .value("Time", only.date), y: .value("Value", only.value))
                }
            }
            if let selected = selectedDate.flatMap(history.nearest(to:)) {
                RuleMark(x: .value("Selected", selected.date)).foregroundStyle(.secondary)
                PointMark(x: .value("Selected", selected.date), y: .value("Value", selected.value))
            }
        }
        .chartYScale(domain: floor...(high + pad))
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(); AxisTick()
                AxisValueLabel(format: model.range == .day ? .dateTime.hour() : .dateTime.month().day())
            }
        }
        .accessibilityLabel("\(entity.friendlyName) history, \(model.range.title)")
        .accessibilityValue(accessibilitySummary(history))
    }

    private func accessibilitySummary(_ history: SensorHistory) -> String {
        guard let latest = history.latest, let low = history.minimum, let high = history.maximum else { return "" }
        return "Latest \(EntityFormat.number(latest.value))\(unit), low \(EntityFormat.number(low)), high \(EntityFormat.number(high))"
    }
}
