import SwiftUI

/// The live-connection indicator and the settings button shown in each tab's toolbar.
struct HomeToolbar: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        HStack {
            Image(systemName: model.isLive ? "bolt.fill" : "bolt.slash")
                .foregroundStyle(model.isLive ? .green : .secondary)
                .accessibilityLabel(model.isLive ? "Live updates on" : "Live updates off")
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}
