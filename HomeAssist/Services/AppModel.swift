import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    var entities: [HAEntity] = []
    var client: HAClient?
    var errorMessage: String?
    var isLoading = false
    /// True while the live connection is up and delivering state changes.
    var isLive = false
    /// Why live updates are not running (e.g. "Reconnecting in 4 s…"), or `nil`.
    var liveStatus: String?
    /// Entities with a toggle request in flight. Tiles show a spinner for these.
    private(set) var togglingEntityIDs: Set<String> = []

    /// Reconnect backoff: starts at the lower bound, doubles up to the upper bound. Seconds.
    var reconnectDelay: ClosedRange<Double> = 1...30
    /// Live changes are collected for this long and applied together, so a busy server doesn't
    /// re-render the list on every event.
    var changeBatchInterval: Duration = .milliseconds(250)

    private var liveTask: Task<Void, Never>?
    /// Bumped on every start/stop. A live run only touches state while its generation is
    /// current, so a run that is still unwinding can't undo its successor.
    private var liveGeneration = 0
    private var refreshTask: Task<Void, Never>?
    private var pendingChanges: [StateChange] = []
    private var flushTask: Task<Void, Never>?
    private let makeLiveSource: @Sendable (HAClient) -> any LiveUpdateSource

    private let urlKey = "serverURL"
    private let tokenAccount = "accessToken"

    var savedURL: String { UserDefaults.standard.string(forKey: urlKey) ?? "http://homeassistant.local:8123" }
    var isConnected: Bool { client != nil }

    /// - Parameters:
    ///   - client: Use this client instead of the saved credentials (tests).
    ///   - makeLiveSource: Creates the live connection for a client; replaced in tests.
    init(client: HAClient? = nil,
         makeLiveSource: @escaping @Sendable (HAClient) -> any LiveUpdateSource = {
             HAWebSocketClient(baseURL: $0.baseURL, token: $0.token)
         }) {
        self.makeLiveSource = makeLiveSource
        if let client {
            self.client = client
        } else if let url = UserDefaults.standard.string(forKey: urlKey),
                  let token = KeychainStore.load(account: tokenAccount) {
            self.client = HAClient(urlString: url, token: token)
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
            stopLiveUpdates() // a running connection would still use the old credentials
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

    /// Fetches all states. Calls made while a fetch is running share it instead of starting
    /// another, so e.g. the list appearing and the live connection coming up don't both fetch.
    func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        let task = Task { await loadStates() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func loadStates() async {
        guard let client else { return }
        do {
            entities = try await client.states().sortedForDisplay()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    /// Toggles an entity. Ignored while a toggle for the same entity is still in flight, so a
    /// double tap can't cancel itself out.
    func toggle(_ entity: HAEntity) async {
        guard let client, togglingEntityIDs.insert(entity.entityId).inserted else { return }
        defer { togglingEntityIDs.remove(entity.entityId) }
        do {
            try await client.callService(domain: "homeassistant", service: "toggle", entityId: entity.entityId)
            // With a live connection the resulting state_changed event updates the list.
            if !isLive { await refresh() }
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Live updates

    /// Starts the live connection and keeps it alive, reconnecting with exponential backoff.
    /// Does nothing if already running or not connected to a server.
    func startLiveUpdates() {
        guard liveTask == nil, let client else { return }
        liveGeneration += 1
        let generation = liveGeneration
        let source = makeLiveSource(client)
        liveTask = Task { await runLive(source: source, generation: generation) }
    }

    func stopLiveUpdates() {
        liveGeneration += 1
        liveTask?.cancel(); liveTask = nil
        flushTask?.cancel(); flushTask = nil
        pendingChanges.removeAll()
        isLive = false
        liveStatus = nil
    }

    private func runLive(source: any LiveUpdateSource, generation: Int) async {
        var delay = reconnectDelay.lowerBound
        while !Task.isCancelled, generation == liveGeneration {
            do {
                for try await update in source.updates() {
                    guard generation == liveGeneration else { return }
                    switch update {
                    case .connected:
                        delay = reconnectDelay.lowerBound
                        isLive = true
                        liveStatus = nil
                        pendingChanges.removeAll() // the snapshot below supersedes them
                        await refresh()
                    case .change(let change):
                        enqueue(change)
                    }
                }
            } catch HAError.unauthorized {
                guard generation == liveGeneration else { return }
                isLive = false
                liveStatus = nil
                errorMessage = HAError.unauthorized.localizedDescription
                liveTask = nil // bad credentials: retrying won't help
                return
            } catch {
                guard generation == liveGeneration else { return }
                liveStatus = "Live updates unavailable (\(error.localizedDescription)). "
                    + "Retrying in \(Int(delay.rounded(.up))) s…"
            }
            guard generation == liveGeneration, !Task.isCancelled else { return }
            isLive = false
            if liveStatus == nil { liveStatus = "Reconnecting in \(Int(delay.rounded(.up))) s…" }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, reconnectDelay.upperBound)
        }
    }

    private func enqueue(_ change: StateChange) {
        pendingChanges.append(change)
        guard flushTask == nil else { return }
        flushTask = Task {
            do { try await Task.sleep(for: changeBatchInterval) } catch { return }
            flushPendingChanges()
        }
    }

    private func flushPendingChanges() {
        flushTask = nil
        guard !pendingChanges.isEmpty else { return }
        entities = entities.applying(pendingChanges)
        pendingChanges.removeAll()
    }
}
