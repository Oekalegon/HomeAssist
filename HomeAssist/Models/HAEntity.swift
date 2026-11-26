import Foundation

struct HAEntity: Identifiable, Decodable, Sendable, Hashable {
    let entityId: String
    let state: String
    let attributes: [String: JSONValue]

    var id: String { entityId }
    var domain: String { entityId.split(separator: ".").first.map(String.init) ?? "" }
    var friendlyName: String { attributes["friendly_name"]?.stringValue ?? entityId }
    var isOn: Bool { state == "on" }

    /// Domains that can be toggled with homeassistant.toggle.
    var isToggleable: Bool {
        ["light", "switch", "fan", "input_boolean", "automation"].contains(domain)
    }

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id", state, attributes
    }
}

/// Minimal type-erased JSON for entity attributes.
enum JSONValue: Decodable, Sendable, Hashable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    var stringValue: String? { if case .string(let s) = self { s } else { nil } }
}
