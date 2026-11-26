import Foundation

/// A decoded message from the Home Assistant WebSocket API.
enum HAWebSocketMessage: Sendable, Equatable {
    case authRequired
    case authOk
    case authInvalid(String)
    case result(id: Int, success: Bool)
    case stateChanged(StateChange)
    /// Any message type the app does not act on (e.g. `pong`).
    case other

    private struct Envelope: Decodable {
        let type: String
        let id: Int?
        let success: Bool?
        let message: String?
        let event: Event?

        struct Event: Decodable {
            let data: Data
            struct Data: Decodable {
                let entityId: String
                let newState: HAEntity?
                enum CodingKeys: String, CodingKey { case entityId = "entity_id", newState = "new_state" }
            }
        }
    }

    static func parse(_ data: Data) throws -> HAWebSocketMessage {
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        switch env.type {
        case "auth_required": return .authRequired
        case "auth_ok": return .authOk
        case "auth_invalid": return .authInvalid(env.message ?? "")
        case "result": return .result(id: env.id ?? -1, success: env.success ?? false)
        case "event":
            guard let d = env.event?.data else { return .other }
            return .stateChanged(StateChange(entityId: d.entityId, newState: d.newState))
        default: return .other
        }
    }
}
