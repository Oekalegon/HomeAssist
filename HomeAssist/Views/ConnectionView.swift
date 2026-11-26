import SwiftUI

struct ConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var token = ""
    @State private var showToken = false

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
                    Text("Create one in Home Assistant under your profile → Security → Long-lived access tokens.")
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
        }
    }
}
