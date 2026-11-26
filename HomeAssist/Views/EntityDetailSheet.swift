import SwiftUI

/// Details for one entity. Controls for lights and climate come in a later change.
struct EntityDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(FavouritesStore.self) private var favourites
    @Environment(\.dismiss) private var dismiss
    let entityID: String

    private var entity: HAEntity? { model.entities.first { $0.entityId == entityID } }

    var body: some View {
        NavigationStack {
            Group {
                if let entity {
                    List {
                        Section {
                            LabeledContent("State", value: entity.tileSubtitle ?? entity.tileValue ?? entity.state)
                            LabeledContent("Entity ID", value: entity.entityId)
                        }
                        Section {
                            let isFavourite = favourites.contains(entityID)
                            Button(isFavourite ? "Remove from Favourites" : "Add to Favourites",
                                   systemImage: isFavourite ? "star.slash" : "star") {
                                favourites.toggle(entityID)
                            }
                        }
                        Section("Attributes") {
                            ForEach(entity.attributes.sorted { $0.key < $1.key }, id: \.key) { key, value in
                                LabeledContent(key, value: value.displayString)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Device not available", systemImage: "questionmark.circle")
                }
            }
            .navigationTitle(entity?.friendlyName ?? "Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}
