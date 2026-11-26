import Foundation

enum HAError: LocalizedError {
    case invalidURL, unauthorized, subscribeFailed, registryDenied, registryFailed(String), http(Int), transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The server URL is not valid."
        case .unauthorized: "Home Assistant rejected the access token."
        case .registryDenied: "Your Home Assistant user can't read rooms. An administrator account is required."
        case .registryFailed(let message): "Couldn't load rooms: \(message)"
        case .subscribeFailed: "Home Assistant refused the live-updates subscription."
        case .http(let code): "Home Assistant returned HTTP \(code)."
        case .transport(let e): e.localizedDescription
        }
    }
}

/// Thin REST client for the Home Assistant API.
struct HAClient: Sendable {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    init?(urlString: String, token: String, session: URLSession = .shared) {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "http://" + s }
        guard let url = URL(string: s), url.host != nil else { return nil }
        self.baseURL = url
        self.token = token
        self.session = session
    }

    /// Verifies URL + token. Returns on success, throws otherwise.
    func checkConnection() async throws {
        _ = try await send(path: "api/", method: "GET", body: nil)
    }

    func states() async throws -> [HAEntity] {
        let data = try await send(path: "api/states", method: "GET", body: nil)
        return try JSONDecoder().decode([HAEntity].self, from: data)
    }

    func callService(domain: String, service: String, entityId: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["entity_id": entityId])
        _ = try await send(path: "api/services/\(domain)/\(service)", method: "POST", body: body)
    }

    private func send(path: String, method: String, body: Data?) async throws -> Data {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw HAError.http(-1) }
            switch http.statusCode {
            case 200..<300: return data
            case 401: throw HAError.unauthorized
            default: throw HAError.http(http.statusCode)
            }
        } catch let e as HAError { throw e }
        catch { throw HAError.transport(error) }
    }
}
