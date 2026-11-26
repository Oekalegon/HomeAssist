import SwiftUI

/// Entities as tiles, in sections (Climate, Lights, Sensors, Other).
struct EntitySectionsGrid: View {
    let sections: [(section: EntitySection, entities: [HAEntity])]
    let onDetails: (HAEntity) -> Void

    var body: some View {
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
                                EntityTile(entity: entity) { onDetails(entity) }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}
