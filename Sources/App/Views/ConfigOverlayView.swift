import SwiftUI

// MARK: - Settings Groups

enum SettingsGroup: String, CaseIterable, Identifiable {
    case model, mtp, server, advanced, ds4, interface

    var id: Self { self }

    var label: String {
        switch self {
        case .model: return "Model"
        case .mtp: return "MTP"
        case .server: return "Server"
        case .advanced: return "Advanced"
        case .ds4: return "DS4 Build"
        case .interface: return "Interface"
        }
    }

    var systemImage: String {
        switch self {
        case .model: return "cpu"
        case .mtp: return "bolt.fill"
        case .server: return "network"
        case .advanced: return "slider.horizontal.3"
        case .ds4: return "shippingbox"
        case .interface: return "textformat"
        }
    }
}

struct ConfigOverlayView: View {
    @Environment(ServerManager.self) private var serverManager
    @Environment(ModelManager.self) private var modelManager
    @Environment(ModelDownloader.self) private var modelDownloader
    @Environment(ProjectImportManager.self) private var projectImportManager

    @State private var selectedGroup: SettingsGroup = .model
    @State private var showFolderPicker = false
    @State private var persistTask: Task<Void, Never>? = nil
    @State private var savedStatusTask: Task<Void, Never>? = nil
    @State private var saveError: String?
    @State private var showSaved = false
    @State private var hostCustomMode = false
    @State private var showModelsDirPicker = false

    // Local config mirror for editing
    @State private var localModelPath: String
    @State private var localHfToken: String?
    @State private var localMtpModelPath: String
    @State private var localEnableMtp: Bool
    @State private var localContextSize: Int
    @State private var localPower: Double
    @State private var localHost: String
    @State private var localPort: Int
    @State private var localKvSpace: Int
    @State private var localSsdStreaming: Bool
    @State private var localKvDiskPath: String?

    // Interface group preferences (Log view font) — UI prefs, not ServerConfig
    @AppStorage("logFontFamily") private var logFontFamily = ""
    @AppStorage("logFontSize") private var logFontSize = 12

    init() {
        let config = AppDelegate.sharedServerManager.config
        _localModelPath = State(initialValue: config.modelPath)
        _localHfToken = State(initialValue: config.hfToken)
        _localMtpModelPath = State(initialValue: config.mtpModelPath)
        _localEnableMtp = State(initialValue: config.enableMtp)
        _localContextSize = State(initialValue: config.contextSize)
        _localPower = State(initialValue: Double(config.power))
        _localHost = State(initialValue: config.host)
        _localPort = State(initialValue: config.port)
        _localKvSpace = State(initialValue: config.kvSpace)
        _localSsdStreaming = State(initialValue: config.ssdStreaming)
        _localKvDiskPath = State(initialValue: config.kvDiskPath)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedGroup) {
                ForEach(SettingsGroup.allCases) { group in
                    Label(group.label, systemImage: group.systemImage)
                        .tag(group)
                }
            }
            .padding(.all, 4)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            Form {
                switch selectedGroup {
                case .model:
                    modelSection
                case .mtp:
                    mtpSection
                case .server:
                    serverSection
                case .advanced:
                    advancedSection
                case .ds4:
                    ds4Section
                case .interface:
                    interfaceSection
                }

                if saveError != nil || showSaved {
                    Section {
                        if let error = saveError {
                            Text(error)
                                .foregroundStyle(.red)
                        } else if showSaved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 680, minHeight: 480)
        .sheet(isPresented: $showModelsDirPicker) {
            FolderPicker(completion: { url in
                showModelsDirPicker = false
                if let url {
                    PathResolver.setCustomModelsDirectory(url)
                    modelManager.refresh()
                    debouncedPersist()
                }
            }, title: "Select Models Directory", prompt: "Choose")
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                showFolderPicker = false
                if let url {
                    projectImportManager.importFrom(url: url)
                }
            }
        }
        .alert("Import Error", isPresented: .init(
            get: { projectImportManager.alertMessage != nil },
            set: { if !$0 { projectImportManager.alertMessage = nil } }
        )) {
            Text(projectImportManager.alertMessage ?? "")
        }
    }

    // MARK: - Sections

    private var modelSection: some View {
        Section {
            ModelPickerView(path: $localModelPath)
                .environment(modelManager)

            LabeledContent {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button(action: openModelsDirectoryPicker) {
                        if PathResolver.hasCustomModelsDirectory {
                            Text(PathResolver.modelsDir.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("~/.ds4-launcher/models (default)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help("Click to change the base directory containing GGUF model files")

                    if !PathResolver.hasCustomModelsDirectory {
                        Button("Reset to Default") {
                            PathResolver.resetModelsDirectory()
                            modelManager.refresh()
                            debouncedPersist()
                        }
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    }
                }
            } label: {
                rowLabel("Models Directory", caption: "Base location of GGUF model files (shared by Model and MTP)")
            }

            LabeledContent {
                SecureField("Token", text: Binding(
                    get: { localHfToken ?? "" },
                    set: { localHfToken = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .onChange(of: localHfToken) { debouncedPersist() }
            } label: {
                rowLabel("HuggingFace Token", caption: "Required for gated models")
            }
        } header: {
            Text("Model")
        }
    }

    private var mtpSection: some View {
        Section {
            MtpModelPickerView(path: $localMtpModelPath)
                .environment(modelManager)

            LabeledContent {
                Text(PathResolver.modelsDir.lastPathComponent.isEmpty ? "(default)" : PathResolver.modelsDir.lastPathComponent)
                    .foregroundStyle(.secondary)
            } label: {
                rowLabel("MTP Model Location", caption: "Same directory as Models Directory")
            }

            LabeledContent {
                Toggle("", isOn: $localEnableMtp)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: localEnableMtp) { debouncedPersist() }
            } label: {
                rowLabel("Enable MTP", caption: "Use multi-token prediction for faster inference")
            }
        } header: {
            Text("MTP (Multi-Token Predict)")
        }
    }

    private var serverSection: some View {
        Section {
            LabeledContent {
                TextField("Context", value: $localContextSize, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onChange(of: localContextSize) { debouncedPersist() }
            } label: {
                rowLabel("Context Size", caption: "Maximum context length (tokens)")
            }

            LabeledContent {
                HStack {
                    if hostCustomMode {
                        TextField("Custom host", text: $localHost)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 150)
                            .onChange(of: localHost) { debouncedPersist() }
                    } else {
                        Text("0.0.0.0")
                            .foregroundStyle(DesignTokens.typeSecondary)
                    }

                    Button(action: { hostCustomMode.toggle() }) {
                        Image(systemName: hostCustomMode ? "checkmark" : "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.typeSecondary)
                }
            } label: {
                rowLabel("Host", caption: "Bind address")
            }

            LabeledContent {
                TextField("Port", value: $localPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onChange(of: localPort) {
                        localPort = clampPort(localPort)
                        debouncedPersist()
                    }
            } label: {
                rowLabel("Port", caption: "Server port (0–65535)")
            }
        } header: {
            Text("Server")
        }
    }

    private var advancedSection: some View {
        Section {
            LabeledContent {
                HStack {
                    Slider(value: $localPower, in: 0...100)
                        .frame(maxWidth: 200)
                        .onChange(of: localPower) { debouncedPersist() }
                    Text("\(Int(localPower))%")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.typeSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            } label: {
                rowLabel("Power", caption: "Compute power (0–100%)")
            }

            LabeledContent {
                Toggle("", isOn: $localSsdStreaming)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: localSsdStreaming) { debouncedPersist() }
            } label: {
                rowLabel("SSD Streaming", caption: "Enable SSD-based KV cache offloading")
            }

            if localSsdStreaming {
                LabeledContent {
                    TextField("KV disk path", text: Binding(get: { localKvDiskPath ?? "" }, set: { localKvDiskPath = $0.isEmpty ? nil : $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                        .onChange(of: localKvDiskPath) { debouncedPersist() }
                } label: {
                    rowLabel("KV Disk Path", caption: "Directory for KV disk offload")
                }

                LabeledContent {
                    TextField("Space", value: $localKvSpace, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onChange(of: localKvSpace) { debouncedPersist() }
                } label: {
                    rowLabel("KV Disk Space (MB)", caption: "KV disk space allocation")
                }
            }
        } header: {
            Text("Advanced")
        }
    }

    private var ds4Section: some View {
        Section {
            ImportStatusView(manager: projectImportManager) {
                showFolderPicker = true
            }
        } header: {
            Text("DS4 Build")
        }
    }

    private var interfaceSection: some View {
        Section {
            LabeledContent {
                Picker("Log font family", selection: $logFontFamily) {
                    ForEach(monospacedFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            } label: {
                rowLabel("Font Family", caption: "Monospace font for the Log view")
            }

            LabeledContent {
                Stepper(value: $logFontSize, in: 9...20) {
                    Text("\(logFontSize) pt")
                }
            } label: {
                rowLabel("Font Size", caption: "Log view font size (9–20pt)")
            }
        } header: {
            Text("Interface")
        }
    }

    private var monospacedFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
    }

    private func rowLabel(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openModelsDirectoryPicker() {
        showModelsDirPicker = true
    }

    // MARK: - Actions

    private func persistConfig() {
        saveError = nil
        var config = AppDelegate.sharedServerManager.config
        config.modelPath = localModelPath
        config.hfToken = localHfToken
        config.mtpModelPath = localMtpModelPath
        config.enableMtp = localEnableMtp
        config.contextSize = localContextSize
        config.power = Int(localPower)
        config.host = localHost
        config.port = clampPort(localPort)
        config.kvSpace = localKvSpace
        config.ssdStreaming = localSsdStreaming
        config.kvDiskPath = localKvDiskPath

        do {
            try JSONEncoder().encode(config).write(to: PathResolver.configFile)
            AppDelegate.sharedServerManager.config = config
            showSaved = true
            savedStatusTask?.cancel()
            savedStatusTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showSaved = false
                    }
                }
            }
        } catch {
            saveError = "Failed to save config: \(error.localizedDescription)"
        }
    }

    private func debouncedPersist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            await MainActor.run { persistConfig() }
        }
    }

    private func clampPort(_ value: Int) -> Int {
        return min(max(value, 0), 65535)
    }
}

// MARK: - DS4 Build Import Status

private struct ImportStatusView: View {
    let manager: ProjectImportManager
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
            if let path = manager.importPath {
                LabeledContent {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.typeSecondary)
                        .lineLimit(1)
                } label: {
                    Text("Project Path")
                }

                if let date = manager.lastImportDate {
                    Text("Last imported: \(date, style: .date) \(date, style: .time)")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.typeSecondary)
                }
            }

            Group {
                if manager.isImporting {
                    HStack(spacing: DesignTokens.Spacing.s2) {
                        ProgressView()
                            .scaleEffect(0.8)
                        if let msg = manager.statusMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.typeSecondary)
                        }
                    }
                } else if let msg = manager.statusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.typeSecondary)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: manager.statusMessage)

            HStack(spacing: DesignTokens.Spacing.s2) {
                if manager.importPath != nil {
                    Button("Refresh") {
                        manager.refresh()
                    }
                    .controlSize(.regular)
                    .disabled(manager.isImporting)

                    Button("Change") {
                        manager.changePath()
                        onImport()
                    }
                    .controlSize(.regular)
                    .disabled(manager.isImporting)
                } else {
                    Button("Import Build") {
                        onImport()
                    }
                    .controlSize(.regular)
                    .disabled(manager.isImporting)
                }
            }
        }
    }
}
