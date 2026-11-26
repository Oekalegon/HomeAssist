import Foundation

/// A `state_changed` event from Home Assistant.
struct StateChange: Sendable, Hashable {
    let entityId: String
    /// The entity's new state, or `nil` when the entity was removed.
    let newState: HAEntity?
}

extension Array where Element == HAEntity {
    /// Returns a copy with `change` applied, keeping the list sorted by friendly name.
    ///
    /// Replaces an existing entity, inserts a new one, or removes one whose `newState` is `nil`.
    func applying(_ change: StateChange) -> [HAEntity] {
        var result = self
        let index = result.firstIndex { $0.entityId == change.entityId }
        switch (change.newState, index) {
        case (nil, let i?):
            result.remove(at: i)
        case (nil, nil):
            break
        case (let new?, let i?):
            result[i] = new
        case (let new?, nil):
            let position = result.firstIndex { $0.friendlyName > new.friendlyName } ?? result.endIndex
            result.insert(new, at: position)
        }
        return result
    }
}
