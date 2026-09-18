// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  AI.swift
//  Nook
//
//  AI settings — flat Form layout matching other settings tabs
//

import NookSettings
import SwiftUI
import NookDesign

struct SettingsAITab: View {
    @Environment(\.nookSettings) var nookSettings
    @Environment(AIConfigService.self) var configService
    @Environment(MCPManager.self) var mcpManager
    @Environment(TabOrganizerManager.self) var tabOrganizerManager

    @State private var openRouterSearch: String = ""
    @State private var testingConnection: Bool = false
    @State private var connectionTestResult: String?
    @State private var newMCPServerName: String = ""
    @State private var newMCPServerCommand: String = ""
    @State private var newMCPServerArgs: String = ""
    @State private var showDownloadConfirmation: Bool = false
    @State private var showAddMCPServer: Bool = false
    @State private var showAddCustomProvider: Bool = false
    @State private var customProviderName: String = ""
    @State private var customProviderURL: String = ""
    @State private var customProviderKey: String = ""
    @State private var addModelId: String = ""
    @State private var showFetchedModels: Bool = false

    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            // MARK: - Tab Organizer
            Section {
                Toggle(isOn: Binding(
                    get: { nookSettings.tabOrganizerEnabled },
                    set: { newValue in
                        if newValue && !nookSettings.tabOrganizerModelDownloaded {
                            showDownloadConfirmation = true
                        } else {
                            nookSettings.tabOrganizerEnabled = newValue
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                        Text("Tab Organizer")
                            .font(NookDesign.Font.body)
                        Text("Uses a small on-device AI model to group, rename, sort, and deduplicate tabs")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if nookSettings.tabOrganizerEnabled {
                    if case .downloading(let progress) = tabOrganizerManager.engine.status {
                        HStack(spacing: NookDesign.Spacing.md) {
                            ProgressView(value: progress)
                                .frame(maxWidth: .infinity)
                            Text("\(Int(progress * 100))%")
                                .font(NookDesign.Font.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text("Downloading model (~350 MB)...")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                    } else if case .loading = tabOrganizerManager.engine.status {
                        HStack(spacing: NookDesign.Spacing.md) {
                            ProgressView().controlSize(.small)
                            Text("Loading model...")
                                .font(NookDesign.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if case .error(let message) = tabOrganizerManager.engine.status {
                        HStack(spacing: NookDesign.Spacing.md) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(NookDesign.Font.secondary)
                            Text(message)
                                .font(NookDesign.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Retry Download") {
                            Task { try? await tabOrganizerManager.engine.ensureDownloaded() }
                        }
                        .font(NookDesign.Font.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if nookSettings.tabOrganizerModelDownloaded {
                        HStack(spacing: NookDesign.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(NookDesign.Font.secondary)
                            Text("Model ready")
                                .font(NookDesign.Font.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Delete Model") {
                                tabOrganizerManager.engine.unload()
                                // TODO: delete cached model files
                                nookSettings.tabOrganizerModelDownloaded = false
                                nookSettings.tabOrganizerEnabled = false
                            }
                            .font(NookDesign.Font.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Tab Organizer")
            } footer: {
                if nookSettings.tabOrganizerEnabled {
                    Text("Right-click a space or press \u{2318}\u{21E7}\u{2325}O to organize tabs")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .alert("Download AI Model?", isPresented: $showDownloadConfirmation) {
                Button("Download") {
                    nookSettings.tabOrganizerEnabled = true
                    Task {
                        do {
                            try await tabOrganizerManager.engine.ensureDownloaded()
                            nookSettings.tabOrganizerModelDownloaded = true
                        } catch {
                            nookSettings.tabOrganizerEnabled = false
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Tab Organizer requires a one-time download of a small AI model (~350 MB). The model runs entirely on your device — no data is sent to any server.")
            }

            // MARK: - Providers
            Section("Providers") {
                ForEach(configService.providers) { provider in
                    providerRow(provider)
                }

                if showAddCustomProvider {
                    VStack(alignment: .leading, spacing: NookDesign.Spacing.md) {
                        TextField("Provider Name", text: $customProviderName)
                        TextField("Base URL (e.g., http://localhost:1234/v1)", text: $customProviderURL)
                        SecureField("API Key (optional)", text: $customProviderKey)
                        HStack {
                            Button("Cancel") {
                                showAddCustomProvider = false
                                customProviderName = ""
                                customProviderURL = ""
                                customProviderKey = ""
                            }
                            Button("Add") {
                                configService.addCustomProvider(
                                    name: customProviderName,
                                    baseURL: customProviderURL,
                                    apiKey: customProviderKey
                                )
                                showAddCustomProvider = false
                                customProviderName = ""
                                customProviderURL = ""
                                customProviderKey = ""
                            }
                            .disabled(customProviderName.isEmpty || customProviderURL.isEmpty)
                        }
                    }
                } else {
                    Button(action: { showAddCustomProvider = true }) {
                        Label("Add Custom Provider", systemImage: "plus.circle")
                    }
                }
            }

            // MARK: - Models
            Section("Models") {
                if configService.models.isEmpty {
                    Text("No models added. Add a model by ID or fetch from a provider.")
                        .foregroundStyle(.secondary)
                        .font(NookDesign.Font.secondary)
                }

                ForEach(configService.models) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                            Text(model.displayName)
                                .font(NookDesign.Font.secondary)
                            Text(model.id)
                                .font(NookDesign.Font.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        if configService.config.activeModelId == model.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(NookDesign.Font.body)
                        }

                        Button(action: { configService.setActiveModel(model.id) }) {
                            Text(configService.config.activeModelId == model.id ? "Active" : "Use")
                                .font(NookDesign.Font.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(configService.config.activeModelId == model.id)

                        Button(action: {
                            configService.removeModel(model.id, providerId: model.providerId)
                        }) {
                            Image(systemName: "trash")
                                .font(NookDesign.Font.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                // Add by ID
                HStack {
                    TextField("Add model by ID (e.g., gpt-4o)", text: $addModelId)
                        .textFieldStyle(.roundedBorder)
                        .font(NookDesign.Font.secondary)
                    Button("Add") {
                        guard !addModelId.isEmpty,
                              let providerId = configService.config.activeProviderId else { return }
                        configService.addModelById(addModelId, displayName: nil, providerId: providerId)
                        addModelId = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(addModelId.isEmpty || configService.config.activeProviderId == nil)
                }

                // Fetch from provider
                if configService.activeProviderType == .openRouter {
                    DisclosureGroup("Fetch from OpenRouter", isExpanded: $showFetchedModels) {
                        HStack {
                            TextField("Search models...", text: $openRouterSearch)
                                .textFieldStyle(.roundedBorder)
                                .font(NookDesign.Font.secondary)
                            Button("Fetch") {
                                Task {
                                    await configService.fetchOpenRouterModels(search: openRouterSearch.isEmpty ? nil : openRouterSearch)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(configService.isFetchingModels)
                        }

                        if configService.isFetchingModels {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("Loading models...")
                                    .font(NookDesign.Font.secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(configService.openRouterModels.prefix(50)) { model in
                            fetchedModelRow(model)
                        }
                    }
                }

                if configService.activeProviderType == .ollama {
                    DisclosureGroup("Fetch from Ollama", isExpanded: $showFetchedModels) {
                        Button("Refresh") {
                            Task { await configService.fetchOllamaModels() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(configService.isFetchingModels)

                        if configService.isFetchingModels {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("Loading models...")
                                    .font(NookDesign.Font.secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(configService.ollamaModels) { model in
                            fetchedModelRow(model)
                        }
                    }
                }
            }

            // MARK: - Generation
            Section("Generation") {
                // Temperature
                VStack(alignment: .leading, spacing: NookDesign.Spacing.xs) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.1f", configService.generationConfig.temperature))
                            .font(NookDesign.Font.secondary.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { configService.generationConfig.temperature },
                            set: {
                                var config = configService.generationConfig
                                config.temperature = $0
                                configService.generationConfig = config
                            }
                        ),
                        in: 0...2,
                        step: 0.1
                    )
                    Text("Lower = more focused, Higher = more creative")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                }

                // Max tokens
                HStack {
                    Text("Max Output Tokens")
                    Spacer()
                    TextField("4096", value: Binding(
                        get: { configService.generationConfig.maxTokens },
                        set: {
                            var config = configService.generationConfig
                            config.maxTokens = $0
                            configService.generationConfig = config
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: NookDesign.Size.fieldNarrow)
                }

                // System prompt
                VStack(alignment: .leading, spacing: NookDesign.Spacing.xs) {
                    HStack {
                        Text("System Prompt")
                        Spacer()
                        Button("Reset to Default") {
                            var config = configService.generationConfig
                            config.systemPrompt = AIGenerationConfig.defaultSystemPrompt
                            configService.generationConfig = config
                        }
                        .font(NookDesign.Font.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    TextEditor(text: Binding(
                        get: { configService.generationConfig.systemPrompt },
                        set: {
                            var config = configService.generationConfig
                            config.systemPrompt = $0
                            configService.generationConfig = config
                        }
                    ))
                    .font(NookDesign.Font.secondary)
                    .frame(height: NookDesign.Size.textEditorHeight)
                    .border(.quaternary)
                }

                // Streaming
                Toggle("Enable Streaming", isOn: Binding(
                    get: { configService.generationConfig.streamingEnabled },
                    set: {
                        var config = configService.generationConfig
                        config.streamingEnabled = $0
                        configService.generationConfig = config
                    }
                ))

                // Web search
                Toggle("Web Search", isOn: Binding(
                    get: { configService.generationConfig.webSearchEnabled },
                    set: {
                        var config = configService.generationConfig
                        config.webSearchEnabled = $0
                        configService.generationConfig = config
                    }
                ))

                if configService.generationConfig.webSearchEnabled {
                    Picker("Engine", selection: Binding(
                        get: { configService.generationConfig.webSearchEngine },
                        set: {
                            var config = configService.generationConfig
                            config.webSearchEngine = $0
                            configService.generationConfig = config
                        }
                    )) {
                        Text("Auto").tag("auto")
                        Text("Native").tag("native")
                        Text("Exa").tag("exa")
                    }
                    .pickerStyle(.segmented)

                    Picker("Context Size", selection: Binding(
                        get: { configService.generationConfig.webSearchContextSize },
                        set: {
                            var config = configService.generationConfig
                            config.webSearchContextSize = $0
                            configService.generationConfig = config
                        }
                    )) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                    .pickerStyle(.segmented)

                    Picker("Max Results", selection: Binding(
                        get: { configService.generationConfig.webSearchMaxResults },
                        set: {
                            var config = configService.generationConfig
                            config.webSearchMaxResults = $0
                            configService.generationConfig = config
                        }
                    )) {
                        Text("3").tag(3)
                        Text("5").tag(5)
                        Text("10").tag(10)
                    }
                    .pickerStyle(.segmented)
                }
            }

            // MARK: - Browser Tools
            Section("Browser Tools") {
                Picker("Execution Mode", selection: Binding(
                    get: { configService.browserToolsConfig.executionMode },
                    set: {
                        var config = configService.browserToolsConfig
                        config.executionMode = $0
                        configService.browserToolsConfig = config
                    }
                )) {
                    ForEach(BrowserToolExecutionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(Array(BrowserToolsConfig.allToolNames.sorted()), id: \.self) { toolName in
                    Toggle(isOn: Binding(
                        get: { configService.browserToolsConfig.enabledTools.contains(toolName) },
                        set: { enabled in
                            var config = configService.browserToolsConfig
                            if enabled {
                                config.enabledTools.insert(toolName)
                            } else {
                                config.enabledTools.remove(toolName)
                            }
                            configService.browserToolsConfig = config
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(toolName)
                                .font(NookDesign.Font.secondary)
                            if let tool = BrowserTools.toolsByName[toolName] {
                                Text(tool.description)
                                    .font(NookDesign.Font.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // MARK: - MCP Servers
            Section("MCP Servers") {
                if configService.mcpServers.isEmpty && !showAddMCPServer {
                    VStack(spacing: NookDesign.Spacing.md) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(NookDesign.Font.titleLarge)
                            .foregroundStyle(.secondary)
                        Text("No MCP servers configured")
                            .font(NookDesign.Font.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NookDesign.Spacing.lg)
                }

                ForEach(configService.mcpServers) { server in
                    mcpServerRow(server)
                }

                if showAddMCPServer {
                    addMCPServerForm
                } else {
                    Button(action: { showAddMCPServer = true }) {
                        Label("Add Server", systemImage: "plus.circle")
                    }
                }
            }

            // MARK: - Browser Control
            Section {
                Toggle(isOn: $settings.browserControlServerEnabled) {
                    VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                        Text("Allow agents to control this browser")
                            .font(NookDesign.Font.body)
                        Text("Serves MCP on 127.0.0.1:47823 so a coding agent can drive Nook")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // The setting lives in NookSettings, which cannot reach the server; start and
                // stop it from here so the toggle still takes effect without a relaunch.
                .onChange(of: settings.browserControlServerEnabled) {
                    DevMCPServer.shared.applyEnabledSetting($1)
                }
            } header: {
                Text("Browser Control")
            } footer: {
                Text("A client must send the token from Application Support/com.gstudios.nook/dev-mcp-token. Any program on this Mac can read that file, and with it run JavaScript in your tabs and read pages you are signed in to. Leave this off unless you are driving Nook from an agent.")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Provider Row

    @ViewBuilder
    private func providerRow(_ provider: AIProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                    HStack(spacing: NookDesign.Spacing.sm) {
                        Text(provider.displayName)
                            .font(NookDesign.Font.label)

                        if configService.config.activeProviderId == provider.id {
                            Text("Active")
                                .font(NookDesign.Font.caption)
                                .foregroundStyle(.green)
                                .padding(.horizontal, NookDesign.Spacing.sm)
                                .padding(.vertical, NookDesign.Spacing.xxs)
                                .background(NookDesign.Radius.shape(NookDesign.Radius.xs).fill(.green.opacity(0.15)))
                        }
                    }

                    Text(provider.providerType.displayName)
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { provider.isEnabled },
                    set: { newValue in
                        var updated = provider
                        updated.isEnabled = newValue
                        configService.updateProvider(updated)
                    }
                ))

                if configService.config.activeProviderId != provider.id {
                    Button("Use") {
                        configService.setActiveProvider(provider.id)
                    }
                    .font(NookDesign.Font.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if provider.providerType.requiresAPIKey {
                HStack(spacing: NookDesign.Spacing.md) {
                    SecureField("API Key", text: Binding(
                        get: { provider.apiKey },
                        set: { newValue in
                            // Update provider config and API key separately
                            configService.updateProvider(provider, apiKey: newValue)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(NookDesign.Font.secondary)

                    if !provider.apiKey.isEmpty {
                        Button("Test") {
                            testConnection(provider)
                        }
                        .font(NookDesign.Font.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(testingConnection)
                    }
                }
            }

            if provider.providerType == .ollama || provider.providerType == .openAICompatible {
                TextField("Base URL", text: Binding(
                    get: { provider.baseURL },
                    set: { newValue in
                        var updated = provider
                        updated.baseURL = newValue
                        configService.updateProvider(updated)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(NookDesign.Font.secondary)
            }

            if let result = connectionTestResult {
                Text(result)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(result.contains("Success") ? .green : .red)
            }
        }
    }

    // MARK: - Fetched Model Row

    @ViewBuilder
    private func fetchedModelRow(_ model: AIModelConfig) -> some View {
        let alreadyAdded = configService.models.contains { $0.id == model.id && $0.providerId == model.providerId }
        HStack {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(model.displayName)
                    .font(NookDesign.Font.secondary)
                Text(model.id)
                    .font(NookDesign.Font.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if alreadyAdded {
                Text("Added")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Add") {
                    configService.addModel(model)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - MCP Server Row

    @ViewBuilder
    private func mcpServerRow(_ server: MCPServerConfig) -> some View {
        let state = mcpManager.connectionState(for: server.id)
        VStack(alignment: .leading, spacing: NookDesign.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                    Text(server.name)
                        .font(NookDesign.Font.label)

                    switch server.transport {
                    case .stdio(let cmd, let args):
                        Text("\(cmd) \(args.joined(separator: " "))")
                            .font(NookDesign.Font.caption.monospaced())
                            .foregroundStyle(.secondary)
                    case .sse(let url):
                        Text(url)
                            .font(NookDesign.Font.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: NookDesign.Spacing.xs) {
                    Circle()
                        .fill(stateColor(state))
                        .frame(width: NookDesign.Size.statusDot, height: NookDesign.Size.statusDot)
                    Text(state.displayName)
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("", isOn: Binding(
                    get: { server.isEnabled },
                    set: { newValue in
                        var updated = server
                        updated.isEnabled = newValue
                        configService.updateMCPServer(updated)
                        if newValue {
                            mcpManager.connectServer(updated)
                        } else {
                            mcpManager.disconnectServer(server.id)
                        }
                    }
                ))

                Button(action: { mcpManager.reconnectServer(server) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(NookDesign.Font.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                    configService.removeMCPServer(server.id)
                    mcpManager.disconnectServer(server.id)
                }) {
                    Image(systemName: "trash")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }

            if state.isConnected {
                let tools = mcpManager.allTools.filter { $0.serverId == server.id }
                if !tools.isEmpty {
                    VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                        Text("Discovered Tools (\(tools.count))")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)

                        ForEach(tools) { tool in
                            HStack(spacing: NookDesign.Spacing.xs) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(NookDesign.Font.caption)
                                    .foregroundStyle(.secondary)
                                Text(tool.name)
                                    .font(NookDesign.Font.caption.monospaced())
                                Text("- \(tool.description)")
                                    .font(NookDesign.Font.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Add MCP Server Form

    @ViewBuilder
    private var addMCPServerForm: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.md) {
            TextField("Server Name", text: $newMCPServerName)
            TextField("Command (e.g., /usr/local/bin/mcp-server)", text: $newMCPServerCommand)
            TextField("Arguments (space-separated)", text: $newMCPServerArgs)

            HStack {
                Button("Cancel") {
                    showAddMCPServer = false
                    newMCPServerName = ""
                    newMCPServerCommand = ""
                    newMCPServerArgs = ""
                }
                Button("Add") {
                    let args = newMCPServerArgs.split(separator: " ").map(String.init)
                    let server = MCPServerConfig(
                        name: newMCPServerName,
                        transport: .stdio(command: newMCPServerCommand, args: args)
                    )
                    configService.addMCPServer(server)
                    mcpManager.connectServer(server)
                    showAddMCPServer = false
                    newMCPServerName = ""
                    newMCPServerCommand = ""
                    newMCPServerArgs = ""
                }
                .disabled(newMCPServerName.isEmpty || newMCPServerCommand.isEmpty)
            }
        }
    }

    // MARK: - Helpers

    private func testConnection(_ provider: AIProviderConfig) {
        testingConnection = true
        connectionTestResult = nil

        Task {
            do {
                switch provider.providerType {
                case .gemini:
                    let url = URL(string: "\(provider.baseURL)/models?key=\(provider.apiKey)")!
                    let (_, response) = try await URLSession.shared.data(from: url)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        connectionTestResult = "Success: Connection verified"
                    } else {
                        connectionTestResult = "Failed: Invalid response"
                    }
                case .openRouter:
                    var request = URLRequest(url: URL(string: "\(provider.baseURL)/models")!)
                    request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        connectionTestResult = "Success: Connection verified"
                    } else {
                        connectionTestResult = "Failed: Invalid response"
                    }
                case .ollama:
                    let (_, response) = try await URLSession.shared.data(from: URL(string: "\(provider.baseURL)/api/tags")!)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        connectionTestResult = "Success: Ollama is running"
                    } else {
                        connectionTestResult = "Failed: Ollama not responding"
                    }
                case .openAICompatible:
                    var request = URLRequest(url: URL(string: "\(provider.baseURL)/models")!)
                    if !provider.apiKey.isEmpty {
                        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        connectionTestResult = "Success: Connection verified"
                    } else {
                        connectionTestResult = "Failed: Invalid response"
                    }
                }
            } catch {
                connectionTestResult = "Failed: \(error.localizedDescription)"
            }
            testingConnection = false
        }
    }

    private func stateColor(_ state: MCPConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}
