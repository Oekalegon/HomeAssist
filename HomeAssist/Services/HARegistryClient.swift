import Foundation

/// Reads Home Assistant's area, device and entity registries over a short-lived WebSocket
/// connection (these commands are WebSocket-only).
///
/// Separate from the live connection so a slow or refused registry request can never hold up
/// state updates.
struct HARegistryClient: RegistrySource {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    private static let timeout: Duration = .seconds(15)
    private enum CommandID { static let areas = 1, devices = 2, entities = 3 }

    func load() async throws -> HARegistry {
        guard let url = HAWebSocketClient.webSocketURL(from: baseURL) else { throw HAError.invalidURL }
        let socket = session.webSocketTask(with: url)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        return try await withThrowingTaskGroup(of: HARegistry.self) { group in
            group.addTask { try await self.run(socket) }
            group.addTask {
                try await Task.sleep(for: Self.timeout)
                throw HAError.transport(URLError(.timedOut))
            }
            do {
                let registry = try await group.next()!
                group.cancelAll()
                return registry
            } catch {
                socket.cancel(with: .goingAway, reason: nil) // unblocks a pending receive()
                group.cancelAll()
                throw error
            }
        }
    }

    private struct Head: Decodable { let type: String; let id: Int? }
    private struct Reply<T: Decodable>: Decodable {
        let success: Bool
        let result: T?
        let error: Failure?
        struct Failure: Decodable { let code: String?; let message: String? }
    }

    private func run(_ socket: URLSessionWebSocketTask) async throws -> HARegistry {
        var areas: [HAArea]?, devices: [HADevice]?, entities: [HAEntityRegistryEntry]?
        let decoder = JSONDecoder()
        while true {
            let data: Data
            switch try await socket.receive() {
            case .data(let d): data = d
            case .string(let s): data = Data(s.utf8)
            @unknown default: continue
            }
            let head = try decoder.decode(Head.self, from: data)
            switch head.type {
            case "auth_required":
                try await send(["type": "auth", "access_token": token], on: socket)
            case "auth_ok":
                try await send(["id": CommandID.areas, "type": "config/area_registry/list"], on: socket)
                try await send(["id": CommandID.devices, "type": "config/device_registry/list"], on: socket)
                try await send(["id": CommandID.entities, "type": "config/entity_registry/list"], on: socket)
            case "auth_invalid":
                throw HAError.unauthorized
            case "result":
                switch head.id {
                case CommandID.areas: areas = try Self.result([HAArea].self, from: data)
                case CommandID.devices: devices = try Self.result([HADevice].self, from: data)
                case CommandID.entities: entities = try Self.result([HAEntityRegistryEntry].self, from: data)
                default: break
                }
                if let areas, let devices, let entities {
                    return HARegistry.build(areas: areas, devices: devices, entities: entities)
                }
            default:
                break
            }
        }
    }

    /// Decodes a command reply, turning Home Assistant's error into an `HAError`.
    static func result<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let reply = try JSONDecoder().decode(Reply<T>.self, from: data)
        if reply.success, let result = reply.result { return result }
        if reply.error?.code == "unauthorized" { throw HAError.registryDenied }
        throw HAError.registryFailed(reply.error?.message ?? reply.error?.code ?? "unknown error")
    }

    private func send(_ object: [String: Any], on socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
}
