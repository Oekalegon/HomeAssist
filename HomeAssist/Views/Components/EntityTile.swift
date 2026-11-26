import SwiftUI

/// A tappable tile for one entity.
///
/// Tap toggles anything that can be switched; everything else (and a press-and-hold on any
/// tile) opens the details. The tile only shows the state the server has confirmed: while a
/// toggle is in flight it shows a spinner, and the new state arrives through the live update.
struct EntityTile: View {
    @Environment(AppModel.self) private var model
    let entity: HAEntity
    /// Shown under the name, e.g. on the Favourites tab where tiles from several rooms mix.
    var roomName: String?
    let onDetails: () -> Void

    private var tint: Color {
        if let rgb = entity.rgbColor { return Color(red: rgb.red, green: rgb.green, blue: rgb.blue) }
        switch entity.section {
        case .lights: return .yellow
        case .climate:
            switch entity.hvacAction {
            case "heating": return .orange
            case "cooling": return .blue
            default: return .accentColor
            }
        default: return .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: entity.symbolName)
                    .font(.title2)
                    .foregroundStyle(entity.isActive ? tint : .secondary)
                Spacer()
                if model.togglingEntityIDs.contains(entity.entityId) { ProgressView() }
            }
            if let value = entity.tileValue {
                Text(value).font(.title2.weight(.semibold)).minimumScaleFactor(0.7).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(entity.friendlyName).font(.subheadline).lineLimit(2)
            if let roomName {
                Text(roomName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let subtitle = entity.tileSubtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(entity.isActive ? tint.opacity(0.18) : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16))
        .opacity(entity.isUnavailable ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            if entity.isToggleable, !entity.isUnavailable {
                Task { await model.toggle(entity) }
            } else {
                onDetails()
            }
        }
        .onLongPressGesture { onDetails() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Details") { onDetails() }
    }
}

/// Identifies the entity whose details sheet is showing.
struct EntityRef: Identifiable { let id: String }
