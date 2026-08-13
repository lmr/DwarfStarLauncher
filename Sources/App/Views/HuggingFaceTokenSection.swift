import SwiftUI
import HuggingFaceDownloader

struct HuggingFaceTokenSection: View {
    @Environment(ServerManager.self) private var serverManager

    @State private var hasToken: Bool = false
    @State private var isSettingToken = false
    @State private var draftToken: String = ""
    @State private var saveError: String?

    private func loadToken() {
        let tokenStore = ConfigTokenStore()
        hasToken = tokenStore.exists() || serverManager.config.hfToken != nil
    }

    private func saveToken() {
        do {
            try ConfigTokenStore().save(draftToken)
            // Mirror into ServerConfig so other UI parts (e.g. argument building) stay consistent.
            serverManager.config.hfToken = draftToken.isEmpty ? nil : draftToken
            hasToken = !draftToken.isEmpty
            draftToken = ""
            saveError = nil
            isSettingToken = false
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func clearToken() {
        try? ConfigTokenStore().delete()
        serverManager.config.hfToken = nil
        hasToken = false
        saveError = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hugging Face Token")
                .font(.headline)

            if let error = saveError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("Set Token") {
                    draftToken = ""
                    saveError = nil
                    isSettingToken = true
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $isSettingToken, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Set Hugging Face Token")
                            .font(.headline)

                        Text("Your token is never displayed. Paste it below to save it for downloads.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        SecureField("Paste your token", text: $draftToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 240)

                        HStack {
                            Spacer()
                            Button("Cancel") {
                                isSettingToken = false
                                saveError = nil
                            }
                            .keyboardShortcut(.cancelAction)
                            Button("Save") {
                                saveToken()
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(draftToken.isEmpty)
                        }
                    }
                    .padding()
                }

                if hasToken {
                    Button("Clear Token") {
                        clearToken()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

            Text(hasToken
                ? "A Hugging Face token is configured. It is required for downloading models from Hugging Face and is stored in your app configuration."
                : "No token is configured yet. This token is required for downloading models from Hugging Face and will be stored in your app configuration."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: loadToken)
    }
}
