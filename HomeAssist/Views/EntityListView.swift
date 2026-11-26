import SwiftUI

struct EntityListView: View {
    @Environment(AppModel.self) private var model
    @Environment(FavouritesStore.self) private var favourites
    @State private var search = ""
    @State private var details: EntityRef?

    private var grouped: [(domain: String, entities: [HAEntity])] {
        model.entities.groupedByDomain(matching: search)
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                Text("Rooms are coming soon. For now this lists every device; swipe a row to favourite it, or press and hold for details.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let status = model.liveStatus {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(grouped, id: \.domain) { group in
                    Section(group.domain) {
                        ForEach(group.entities) { entity in
                            EntityRow(entity: entity)
                                .onLongPressGesture { details = EntityRef(id: entity.entityId) }
                                .swipeActions {
                                    Button(favourites.contains(entity.entityId) ? "Unfavourite" : "Favourite",
                                           systemImage: "star") { favourites.toggle(entity.entityId) }
                                        .tint(.yellow)
                                }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Rooms")
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .toolbar { ToolbarItem(placement: .topBarLeading) { HomeToolbar() } }
            .sheet(item: $details) { EntityDetailSheet(entityID: $0.id) }
        }
    }
}

struct EntityRow: View {
    @Environment(AppModel.self) private var model
    let entity: HAEntity

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entity.friendlyName)
                Text(entity.state).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if entity.isToggleable {
                Toggle(entity.friendlyName, isOn: Binding(get: { entity.isOn },
                                                          set: { _ in Task { await model.toggle(entity) } }))
                    .labelsHidden() // the row already shows the name; VoiceOver still reads it
            }
        }
    }
}
