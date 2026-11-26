import SwiftUI

@main
struct HomeAssistApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if model.isConnected {
                EntityListView().environment(model)
            } else {
                ConnectionView().environment(model)
            }
        }
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active { model.startLiveUpdates() } else { model.stopLiveUpdates() }
        }
    }
}
