import Foundation

/// A `state_changed` event from Home Assistant.
struct StateChange: Sendable, Hashable {
    let entityId: String
    /// The entity's new state, or `nil` when the entity was removed.
    let newState: HAEntity?
}

extension Array where Element == HAEntity {
    /// The order entities are shown in: friendly name, with the entity ID as a tie-breaker so
    /// the order is stable between updates.
    func sortedForDisplay() -> [HAEntity] {
        sorted {
            let order = $0.friendlyName.localizedStandardCompare($1.friendlyName)
            return order == .orderedSame ? $0.entityId < $1.entityId : order == .orderedAscending
        }
    }

    /// Returns a copy with `changes` applied in order, kept sorted for display.
    ///
    /// A change replaces an existing entity, adds a new one, or removes one whose `newState`
    /// is `nil`. Applying a batch at once means a burst of events costs one pass, not one
    /// per event.
    func applying(_ changes: [StateChange]) -> [HAEntity] {
        guard !changes.isEmpty else { return self }
        var byID = Dictionary(map { ($0.entityId, $0) }, uniquingKeysWith: { _, new in new })
        for change in changes { byID[change.entityId] = change.newState }
        return Array(byID.values).sortedForDisplay()
    }

    func applying(_ change: StateChange) -> [HAEntity] { applying([change]) }

    /// Entities whose name contains `search` (all when empty), grouped by domain and sorted by
    /// domain. Order within a group is preserved.
    func groupedByDomain(matching search: String = "") -> [(domain: String, entities: [HAEntity])] {
        let filtered = search.isEmpty ? self : filter { $0.friendlyName.localizedCaseInsensitiveContains(search) }
        return Dictionary(grouping: filtered, by: \.domain)
            .map { (domain: $0.key, entities: $0.value) }
            .sorted { $0.domain < $1.domain }
    }
}
