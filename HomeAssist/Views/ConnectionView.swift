import SwiftUI

struct ConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var token = ""
    @State private var showToken = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("http://homeassistant.local:8123", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
                Section {
                    HStack {
                        Group {
                            if showToken {
                                TextField("Long-lived access token", text: $token)
                            } else {
                                SecureField("Long-lived access token", text: $token)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button(showToken ? "Hide token" : "Show token",
                               systemImage: showToken ? "eye.slash" : "eye") { showToken.toggle() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                    // Fills the field straight from the clipboard. Pasting into a secure field
                    // can drop all but one character (seen in the simulator).
                    PasteButton(payloadType: String.self) { strings in
                        if let pasted = strings.first { token = pasted }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create one in Home Assistant under your profile → Security → Long-lived access tokens.")
                        if !token.isEmpty && !AccessToken.looksComplete(token) {
                            Text("This doesn't look like a complete token (they are about 180 characters). Check that it pasted fully.")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await model.connect(urlString: url, token: token) }
                    } label: {
                        HStack { Text("Connect"); if model.isLoading { Spacer(); ProgressView() } }
                    }
                    .disabled(url.isEmpty || token.isEmpty || model.isLoading)
                }
            }
            .navigationTitle("Connect")
            .onAppear { if url.isEmpty { url = model.savedURL } }
            // Never leave the token revealed after the app has been backgrounded.
            .onChange(of: scenePhase) { if scenePhase != .active { showToken = false } }
        }
    }
}
