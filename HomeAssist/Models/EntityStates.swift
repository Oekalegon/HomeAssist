import Foundation

extension JSONValue {
    var doubleValue: Double? { if case .number(let d) = self { d } else { nil } }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { a } else { nil } }

    /// A short, human-readable rendering, used in the attributes list.
    var displayString: String {
        switch self {
        case .string(let s): s
        case .number(let d): EntityFormat.number(d)
        case .bool(let b): b ? "Yes" : "No"
        case .null: "—"
        case .array(let a): a.map(\.displayString).joined(separator: ", ")
        case .object(let o):
            o.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.displayString)" }.joined(separator: ", ")
        }
    }
}

enum EntityFormat {
    /// Up to one decimal, in the user's locale: `21.5`, `22`.
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// `heat_cool` → `Heat Cool`.
    static func title(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// The groups shown on the Favourites tab and in rooms, in display order.
enum EntitySection: Int, CaseIterable, Comparable, Sendable {
    case climate, lights, sensors, other

    var title: String {
        switch self {
        case .climate: "Climate"
        case .lights: "Lights"
        case .sensors: "Sensors"
        case .other: "Other"
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

extension HAEntity {
    var isUnavailable: Bool { state == "unavailable" }
    var unit: String? { attributes["unit_of_measurement"]?.stringValue }
    var deviceClass: String? { attributes["device_class"]?.stringValue }

    var section: EntitySection {
        switch domain {
        case "climate": .climate
        case "light": .lights
        case "sensor", "binary_sensor": .sensors
        default: .other
        }
    }

    // MARK: Light

    /// Brightness as a percentage (Home Assistant reports 0–255).
    var brightnessPercent: Int? {
        guard let raw = attributes["brightness"]?.doubleValue else { return nil }
        return Int((raw / 255 * 100).rounded())
    }

    /// The light's colour as 0…1 components, when it has one.
    var rgbColor: (red: Double, green: Double, blue: Double)? {
        guard let parts = attributes["rgb_color"]?.arrayValue?.compactMap(\.doubleValue), parts.count == 3 else {
            return nil
        }
        return (parts[0] / 255, parts[1] / 255, parts[2] / 255)
    }

    // MARK: Climate

    var currentTemperature: Double? { attributes["current_temperature"]?.doubleValue }
    var targetTemperature: Double? { attributes["temperature"]?.doubleValue }
    /// What the thermostat is doing right now (`heating`, `cooling`, `idle`), if reported.
    var hvacAction: String? { attributes["hvac_action"]?.stringValue }

    // MARK: Tile content

    /// Whether the tile is drawn highlighted.
    var isActive: Bool {
        if isUnavailable { return false }
        return switch domain {
        case "climate": state != "off"
        default: isToggleable && isOn
        }
    }

    /// A large value shown on the tile: the temperature for climate, the reading for sensors.
    var tileValue: String? {
        switch section {
        case .climate:
            return currentTemperature.map { EntityFormat.number($0) + "°" }
        case .sensors where domain == "sensor":
            if isUnavailable { return "—" }
            let value = Double(state).map(EntityFormat.number) ?? state
            return unit.map { "\(value) \($0)" } ?? value
        default:
            return nil
        }
    }

    /// The line under the name.
    var tileSubtitle: String? {
        if isUnavailable { return "Unavailable" }
        switch section {
        case .lights:
            guard isOn else { return "Off" }
            return brightnessPercent.map { "On \($0)%" } ?? "On"
        case .climate:
            let mode = EntityFormat.title(hvacAction ?? state)
            return targetTemperature.map { "\(mode) → \(EntityFormat.number($0))°" } ?? mode
        case .sensors where domain == "sensor":
            return nil
        default:
            return EntityFormat.title(state)
        }
    }

    /// An SF Symbol for the tile.
    var symbolName: String {
        switch domain {
        case "light": return isOn ? "lightbulb.fill" : "lightbulb"
        case "switch", "input_boolean": return "power"
        case "fan": return "fan"
        case "climate": return "thermometer.medium"
        case "lock": return "lock.fill"
        case "media_player": return "speaker.wave.2.fill"
        case "automation": return "gearshape.2"
        case "binary_sensor": return isOn ? "circle.fill" : "circle"
        case "sensor":
            switch deviceClass {
            case "temperature": return "thermometer.medium"
            case "humidity": return "humidity"
            case "battery": return "battery.100percent"
            case "power", "energy", "voltage", "current": return "bolt.fill"
            case "illuminance": return "sun.max"
            default: return "gauge"
            }
        default: return "square.grid.2x2"
        }
    }
}

extension Array where Element == HAEntity {
    /// Groups entities by section in display order, keeping the given order inside each group
    /// and leaving out empty sections.
    func groupedBySection() -> [(section: EntitySection, entities: [HAEntity])] {
        EntitySection.allCases.compactMap { section in
            let members = filter { $0.section == section }
            return members.isEmpty ? nil : (section: section, entities: members)
        }
    }
}
