import SwiftUI

struct EntityListView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    private var grouped: [(domain: String, entities: [HAEntity])] {
        model.entities.groupedByDomain(matching: search)
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                if let status = model.liveStatus {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(grouped, id: \.domain) { group in
                    Section(group.domain) {
                        ForEach(group.entities) { entity in
                            EntityRow(entity: entity)
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Home")
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: model.isLive ? "bolt.fill" : "bolt.slash")
                        .foregroundStyle(model.isLive ? .green : .secondary)
                        .accessibilityLabel(model.isLive ? "Live updates on" : "Live updates off")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Disconnect", systemImage: "rectangle.portrait.and.arrow.right") { model.disconnect() }
                }
            }
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
