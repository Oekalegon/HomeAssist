import SwiftUI

struct ConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var token = ""

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
                    SecureField("Long-lived access token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
