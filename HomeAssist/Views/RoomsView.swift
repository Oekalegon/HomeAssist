import SwiftUI

struct RoomsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let status = model.registryStatus {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(model.rooms) { room in
                            NavigationLink(value: room.id) { RoomCard(room: room) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Rooms")
            .navigationDestination(for: String.self) { RoomDetailView(roomID: $0) }
            .toolbar { ToolbarItem(placement: .topBarLeading) { HomeToolbar() } }
            .refreshable {
                await model.refresh()
                await model.loadRegistry()
            }
        }
    }
}

struct RoomCard: View {
    let room: Room

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: room.symbolName).font(.title2).foregroundStyle(.tint)
            Spacer(minLength: 0)
            Text(room.name).font(.headline).lineLimit(2)
            Text(room.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct RoomDetailView: View {
    @Environment(AppModel.self) private var model
    let roomID: String
    @State private var search = ""
    @State private var details: EntityRef?

    private var room: Room? { model.rooms.first { $0.id == roomID } }

    private var sections: [(section: EntitySection, entities: [HAEntity])] {
        (room?.entities ?? []).groupedByDomainOrSection(matching: search)
    }

    var body: some View {
        Group {
            if room == nil {
                ContentUnavailableView("Room not available", systemImage: "questionmark.circle")
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                EntitySectionsGrid(sections: sections) { details = EntityRef(id: $0.entityId) }
            }
        }
        .navigationTitle(room?.name ?? "Room")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search)
        .sheet(item: $details) { EntityDetailSheet(entityID: $0.id) }
    }
}

extension Array where Element == HAEntity {
    /// `groupedBySection()` after filtering by name (everything when `search` is empty).
    func groupedByDomainOrSection(matching search: String) -> [(section: EntitySection, entities: [HAEntity])] {
        (search.isEmpty ? self : filter { $0.friendlyName.localizedCaseInsensitiveContains(search) })
            .groupedBySection()
    }
}
