import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("Address", value: model.client?.baseURL.absoluteString ?? "—")
                    LabeledContent("Live updates", value: model.isLive ? "On" : "Off")
                    if let status = model.liveStatus {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = model.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Disconnect", role: .destructive) { confirmDisconnect = true }
                } footer: {
                    Text("Removes the saved access token from this device.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .confirmationDialog("Disconnect from Home Assistant?", isPresented: $confirmDisconnect,
                                titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { dismiss(); model.disconnect() }
            }
        }
        .presentationDetents([.medium])
    }
}
