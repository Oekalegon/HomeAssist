import SwiftUI

struct EntityListView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    private var grouped: [(String, [HAEntity])] {
        let filtered = model.entities.filter {
            search.isEmpty || $0.friendlyName.localizedCaseInsensitiveContains(search)
        }
        return Dictionary(grouping: filtered, by: \.domain).sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                ForEach(grouped, id: \.0) { domain, items in
                    Section(domain) {
                        ForEach(items) { entity in
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
                Toggle("", isOn: Binding(get: { entity.isOn },
                                         set: { _ in Task { await model.toggle(entity) } }))
                    .labelsHidden()
            }
        }
    }
}
