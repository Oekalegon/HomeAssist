import Foundation
import Observation
import SwiftUI

/// The user's pinned entities, in their own order, kept on this device.
///
/// Only IDs are stored. An ID whose entity no longer exists is skipped when displaying but not
/// deleted, in case the entity comes back.
@MainActor @Observable
final class FavouritesStore {
    private(set) var ids: [String]
    private let defaults: UserDefaults
    private let key = "favouriteEntityIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.ids = defaults.stringArray(forKey: key) ?? []
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func add(_ id: String) {
        guard !contains(id) else { return }
        ids.append(id)
        save()
    }

    func remove(_ id: String) {
        ids.removeAll { $0 == id }
        save()
    }

    func toggle(_ id: String) {
        if contains(id) { remove(id) } else { add(id) }
    }

    /// Reorders favourites within one section, as `onMove` reports it for that section's rows.
    ///
    /// - Parameter sectionIDs: The IDs shown in the section, in display order. Favourites in
    ///   other sections keep their place.
    func move(within sectionIDs: [String], from source: IndexSet, to destination: Int) {
        var reordered = sectionIDs
        reordered.move(fromOffsets: source, toOffset: destination)
        let members = Set(sectionIDs)
        var next = reordered.makeIterator()
        ids = ids.map { members.contains($0) ? (next.next() ?? $0) : $0 }
        save()
    }

    /// The favourites that exist in `all`, in the user's order.
    func entities(in all: [HAEntity]) -> [HAEntity] {
        let byID = Dictionary(all.map { ($0.entityId, $0) }, uniquingKeysWith: { _, new in new })
        return ids.compactMap { byID[$0] }
    }

    private func save() { defaults.set(ids, forKey: key) }
}
