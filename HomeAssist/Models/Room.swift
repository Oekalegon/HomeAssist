import Foundation

/// A room: an area and the entities in it.
struct Room: Identifiable, Equatable {
    static let unassignedID = "unassigned"

    let id: String
    let name: String
    let entities: [HAEntity]

    var isUnassigned: Bool { id == Self.unassignedID }

    /// The current temperature: from a thermostat, else a temperature sensor.
    var temperature: Double? {
        entities.first { $0.section == .climate && $0.currentTemperature != nil }?.currentTemperature
            ?? entities.first { $0.domain == "sensor" && $0.deviceClass == "temperature" }
                .flatMap { Double($0.state) }
    }

    /// One line for the room card, e.g. "2 lights on · 21.5°".
    var summary: String {
        let lights = entities.filter { $0.section == .lights && !$0.isUnavailable }
        let on = lights.filter(\.isOn).count
        var parts: [String] = []
        if !lights.isEmpty { parts.append(on == 0 ? "Lights off" : on == 1 ? "1 light on" : "\(on) lights on") }
        if let temperature { parts.append(EntityFormat.number(temperature) + "°") }
        if parts.isEmpty { parts.append(entities.count == 1 ? "1 device" : "\(entities.count) devices") }
        return parts.joined(separator: " · ")
    }

    /// An SF Symbol guessed from the room's name (English and Dutch).
    var symbolName: String {
        let n = name.lowercased()
        let guesses: [(keywords: [String], symbol: String)] = [
            (["kitchen", "keuken"], "fork.knife"),
            (["bed", "slaap"], "bed.double"),
            (["bath", "badkamer", "toilet", "wc", "shower"], "shower"),
            (["living", "lounge", "woonkamer", "salon"], "sofa"),
            (["office", "study", "kantoor", "werkkamer"], "desktopcomputer"),
            (["garage"], "car"),
            (["garden", "tuin", "patio", "terras"], "tree"),
            (["hall", "gang", "entrance", "hal"], "door.left.hand.open"),
        ]
        if isUnassigned { return "questionmark.square.dashed" }
        return guesses.first { g in g.keywords.contains { n.contains($0) } }?.symbol ?? "house"
    }
}

extension HARegistry {
    /// The rooms for `entities`, sorted by name with "Unassigned" last. Hidden and disabled
    /// entities are left out, and so are rooms that end up empty.
    func rooms(for entities: [HAEntity], unassignedName: String = "Unassigned") -> [Room] {
        let visible = entities.filter { !hiddenEntityIDs.contains($0.entityId) }
        let known = Set(areas.map(\.areaId))
        let byArea = Dictionary(grouping: visible) { entity -> String in
            entityAreas[entity.entityId].flatMap { known.contains($0) ? $0 : nil } ?? Room.unassignedID
        }
        var rooms = areas
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .compactMap { area in byArea[area.areaId].map { Room(id: area.areaId, name: area.name, entities: $0) } }
        if let loose = byArea[Room.unassignedID] {
            rooms.append(Room(id: Room.unassignedID, name: unassignedName, entities: loose))
        }
        return rooms
    }
}
