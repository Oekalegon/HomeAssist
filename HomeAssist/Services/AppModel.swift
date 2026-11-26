import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    var entities: [HAEntity] = []
    var client: HAClient?
    var errorMessage: String?
    var isLoading = false
    /// True while the WebSocket is connected and delivering live state changes.
    var isLive = false
    private var liveTask: Task<Void, Never>?

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
        let token = AccessToken.normalized(rawToken)
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
            startLiveUpdates()
        } catch { errorMessage = error.localizedDescription }
    }

    func disconnect() {
        stopLiveUpdates()
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
            // With a live connection the resulting state_changed event updates the list.
            if !isLive { await refresh() }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Starts the WebSocket and keeps it alive, reconnecting with exponential backoff (1s…30s).
    /// Does nothing if already running or not connected to a server.
    func startLiveUpdates() {
        guard liveTask == nil, let client else { return }
        let socket = HAWebSocketClient(baseURL: client.baseURL, token: client.token)
        liveTask = Task { [weak self] in
            var delay = 1.0
            while !Task.isCancelled {
                do {
                    for try await update in socket.updates() {
                        guard let self else { return }
                        switch update {
                        case .connected:
                            delay = 1
                            isLive = true
                            await refresh()
                        case .change(let change):
                            entities = entities.applying(change)
                        }
                    }
                } catch HAError.unauthorized {
                    self?.isLive = false
                    self?.errorMessage = HAError.unauthorized.localizedDescription
                    self?.liveTask = nil
                    return
                } catch {}
                self?.isLive = false
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 30)
            }
        }
    }

    func stopLiveUpdates() {
        liveTask?.cancel()
        liveTask = nil
        isLive = false
    }
}
