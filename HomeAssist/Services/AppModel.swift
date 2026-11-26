import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    var entities: [HAEntity] = []
    var client: HAClient?
    var errorMessage: String?
    var isLoading = false

    private let urlKey = "serverURL"
    private let tokenAccount = "accessToken"

    var savedURL: String { UserDefaults.standard.string(forKey: urlKey) ?? "http://homeassistant.local:8123" }
    var isConnected: Bool { client != nil }

    init() {
        if let url = UserDefaults.standard.string(forKey: urlKey),
           let token = KeychainStore.load(account: tokenAccount) {
            client = HAClient(urlString: url, token: token)
        }
    }

    func connect(urlString: String, token rawToken: String) async {
        errorMessage = nil
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate = HAClient(urlString: urlString, token: token) else {
            errorMessage = HAError.invalidURL.localizedDescription; return
        }
        isLoading = true; defer { isLoading = false }
        do {
            try await candidate.checkConnection()
            UserDefaults.standard.set(candidate.baseURL.absoluteString, forKey: urlKey)
            KeychainStore.save(token, account: tokenAccount)
            client = candidate
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func disconnect() {
        KeychainStore.delete(account: tokenAccount)
        client = nil; entities = []
    }

    func refresh() async {
        guard let client else { return }
        do {
            entities = try await client.states().sorted { $0.friendlyName < $1.friendlyName }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func toggle(_ entity: HAEntity) async {
        guard let client else { return }
        do {
            try await client.callService(domain: "homeassistant", service: "toggle", entityId: entity.entityId)
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
}
