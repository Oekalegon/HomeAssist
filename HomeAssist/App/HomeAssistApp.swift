import SwiftUI

@main
struct HomeAssistApp: App {
    @State private var model = AppModel()
    @State private var favourites = FavouritesStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if model.isConnected {
                RootTabView().environment(model).environment(favourites)
            } else {
                ConnectionView().environment(model)
            }
        }
        .onChange(of: scenePhase, initial: true) {
            // `.inactive` also happens for Control Center, the app switcher and system prompts,
            // so only a real trip to the background closes the connection.
            switch scenePhase {
            case .active: model.startLiveUpdates()
            case .background: model.stopLiveUpdates()
            default: break
            }
        }
    }
}
