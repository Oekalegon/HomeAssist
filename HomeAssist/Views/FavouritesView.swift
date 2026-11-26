import SwiftUI

struct FavouritesView: View {
    @Environment(AppModel.self) private var model
    @Environment(FavouritesStore.self) private var favourites
    @State private var editMode: EditMode = .inactive
    @State private var details: EntityRef?

    private var sections: [(section: EntitySection, entities: [HAEntity])] {
        favourites.entities(in: model.entities).groupedBySection()
    }

    var body: some View {
        NavigationStack {
            Group {
                if favourites.ids.isEmpty {
                    ContentUnavailableView("No favourites yet", systemImage: "star",
                        description: Text("Press and hold any device, then choose Add to Favourites."))
                } else if editMode.isEditing {
                    editList
                } else {
                    tileGrid
                }
            }
            .navigationTitle("Favourites")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HomeToolbar() }
                ToolbarItem(placement: .topBarTrailing) {
                    if !favourites.ids.isEmpty { EditButton() }
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(item: $details) { EntityDetailSheet(entityID: $0.id) }
            .refreshable { await model.refresh() }
        }
    }

    private var tileGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(sections, id: \.section) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.section.title).font(.headline)
                        // Thermostats get the full width; everything else is a two-up grid.
                        LazyVGrid(columns: group.section == .climate
                                  ? [GridItem(.flexible())]
                                  : [GridItem(.adaptive(minimum: 150), spacing: 12)],
                                  spacing: 12) {
                            ForEach(group.entities) { entity in
                                EntityTile(entity: entity) { details = EntityRef(id: entity.entityId) }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var editList: some View {
        List {
            ForEach(sections, id: \.section) { group in
                Section(group.section.title) {
                    ForEach(group.entities) { entity in
                        Label(entity.friendlyName, systemImage: entity.symbolName)
                    }
                    .onMove { source, destination in
                        favourites.move(within: group.entities.map(\.entityId), from: source, to: destination)
                    }
                    .onDelete { offsets in
                        for index in offsets { favourites.remove(group.entities[index].entityId) }
                    }
                }
            }
        }
    }
}
