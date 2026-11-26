import SwiftUI

@main
struct HomeAssistApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            if model.isConnected {
                EntityListView().environment(model)
            } else {
                ConnectionView().environment(model)
            }
        }
    }
}
