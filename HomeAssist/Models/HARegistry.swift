import Foundation

/// A Home Assistant area ("room").
struct HAArea: Decodable, Sendable, Hashable, Identifiable {
    let areaId: String
    let name: String
    var id: String { areaId }
    enum CodingKeys: String, CodingKey { case areaId = "area_id", name }
}

struct HADevice: Decodable, Sendable, Hashable {
    let id: String
    let areaId: String?
    enum CodingKeys: String, CodingKey { case id, areaId = "area_id" }
}

struct HAEntityRegistryEntry: Decodable, Sendable, Hashable {
    let entityId: String
    let areaId: String?
    let deviceId: String?
    let hiddenBy: String?
    let disabledBy: String?
    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id", areaId = "area_id", deviceId = "device_id"
        case hiddenBy = "hidden_by", disabledBy = "disabled_by"
    }
}

/// Which room each entity belongs to, built from Home Assistant's area, device and entity
/// registries. The states list alone has no room information.
struct HARegistry: Sendable, Equatable {
    var areas: [HAArea]
    /// Entity ID → area ID, for entities that have a room.
    var entityAreas: [String: String]
    /// Entities the user hid or disabled in Home Assistant. They are not shown in rooms.
    var hiddenEntityIDs: Set<String>

    static let empty = HARegistry(areas: [], entityAreas: [:], hiddenEntityIDs: [])

    /// An entity's own area wins; otherwise it inherits its device's area.
    static func build(areas: [HAArea], devices: [HADevice], entities: [HAEntityRegistryEntry]) -> HARegistry {
        let deviceAreas = Dictionary(devices.compactMap { d in d.areaId.map { (d.id, $0) } },
                                     uniquingKeysWith: { _, new in new })
        var entityAreas: [String: String] = [:]
        var hidden: Set<String> = []
        for entry in entities {
            if entry.hiddenBy != nil || entry.disabledBy != nil { hidden.insert(entry.entityId) }
            if let area = entry.areaId ?? entry.deviceId.flatMap({ deviceAreas[$0] }) {
                entityAreas[entry.entityId] = area
            }
        }
        return HARegistry(areas: areas, entityAreas: entityAreas, hiddenEntityIDs: hidden)
    }
}

/// Loads the registries. ``HARegistryClient`` is the real one; tests use a fake.
protocol RegistrySource: Sendable {
    func load() async throws -> HARegistry
}
