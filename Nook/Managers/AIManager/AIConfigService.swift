//
//  AIConfigService.swift
//  Nook
//
//  Manages AI configuration persistence via JSON file
//

import Foundation
import OSLog

@MainActor
@Observable
class AIConfigService {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "AIConfig")

    private(set) var config: AIConfiguration
    private let configURL: URL

    // Convenience accessors
    var providers: [AIProviderConfig] { config.providers }
    var models: [AIModelConfig] { config.models }
    var generationConfig: AIGenerationConfig {
        get { config.generationConfig }
        set {
            config.generationConfig = newValue
            save()
        }
    }
    var mcpServers: [MCPServerConfig] {
        get { config.mcpServers }
        set {
            config.mcpServers = newValue
            save()
        }
    }
    var browserToolsConfig: BrowserToolsConfig {
        get { config.browserToolsConfig }
        set {
            config.browserToolsConfig = newValue
            save()
        }
    }

    var activeProvider: AIProviderConfig? {
        config.providers.first { $0.id == config.activeProviderId }
    }

    var activeModel: AIModelConfig? {
        config.models.first { $0.id == config.activeModelId }
    }

    var activeProviderType: AIProviderType? {
        activeProvider?.providerType
    }

    // Dynamic model lists (fetched from APIs)
    var openRouterModels: [AIModelConfig] = []
    var ollamaModels: [AIModelConfig] = []
    var isFetchingModels: Bool = false

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let nookDir = appSupport.appendingPathComponent("Nook")
        self.configURL = nookDir.appendingPathComponent("ai_config.json")

        // Load or create default config
        if let loaded = AIConfigService.load(from: configURL) {
            self.config = loaded
        } else {
            self.config = AIConfigService.createDefaultConfig()
        }

        // Migrate from UserDefaults if this is a fresh config
        migrateFromUserDefaultsIfNeeded()
    }

    // MARK: - Persistence

    func save() {
        do {
            let dir = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            Self.log.error("Failed to save AI config: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> AIConfiguration? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AIConfiguration.self, from: data)
    }

    // MARK: - Provider Management

    func setActiveProvider(_ providerId: String) {
        config.activeProviderId = providerId
        // Auto-select first model for this provider
        if let firstModel = config.models.first(where: { $0.providerId == providerId }) {
            config.activeModelId = firstModel.id
        }
        save()
    }

    func setActiveModel(_ modelId: String) {
        config.activeModelId = modelId
        save()
    }

    func updateProvider(_ provider: AIProviderConfig) {
        if let index = config.providers.firstIndex(where: { $0.id == provider.id }) {
            config.providers[index] = provider
        } else {
            config.providers.append(provider)
        }
        save()
    }

    func removeProvider(_ providerId: String) {
        config.providers.removeAll { $0.id == providerId }
        config.models.removeAll { $0.providerId == providerId }
        if config.activeProviderId == providerId {
            config.activeProviderId = config.providers.first?.id
            config.activeModelId = nil
        }
        save()
    }

    func addCustomProvider(name: String, baseURL: String, apiKey: String = "") {
        let provider = AIProviderConfig(
            displayName: name,
            providerType: .openAICompatible,
            apiKey: apiKey,
            baseURL: baseURL
        )
        config.providers.append(provider)
        save()
    }

    // MARK: - Model Management

    func addModel(_ model: AIModelConfig) {
        if !config.models.contains(where: { $0.id == model.id && $0.providerId == model.providerId }) {
            config.models.append(model)
            save()
        }
    }

    func addModelById(_ modelId: String, displayName: String?, providerId: String) {
        let name = displayName ?? modelId
        let model = AIModelConfig(
            id: modelId,
            displayName: name,
            providerId: providerId,
            isCustom: true,
            capabilities: AIModelCapabilities(toolCalling: true, streaming: true, webSearch: true)
        )
        addModel(model)
    }

    func removeModel(_ modelId: String, providerId: String) {
        config.models.removeAll { $0.id == modelId && $0.providerId == providerId }
        if config.activeModelId == modelId {
            config.activeModelId = config.models.first(where: { $0.providerId == providerId })?.id
        }
        save()
    }

    func modelsForProvider(_ providerId: String) -> [AIModelConfig] {
        config.models.filter { $0.providerId == providerId }
    }

    func modelsForActiveProvider() -> [AIModelConfig] {
        guard let providerId = config.activeProviderId else { return [] }
        return modelsForProvider(providerId)
    }

    // MARK: - MCP Server Management

    func addMCPServer(_ server: MCPServerConfig) {
        config.mcpServers.append(server)
        save()
    }

    func updateMCPServer(_ server: MCPServerConfig) {
        if let index = config.mcpServers.firstIndex(where: { $0.id == server.id }) {
            config.mcpServers[index] = server
            save()
        }
    }

    func removeMCPServer(_ serverId: String) {
        config.mcpServers.removeAll { $0.id == serverId }
        save()
    }

    // MARK: - Fetch Dynamic Models

    func fetchOpenRouterModels(search: String? = nil) async {
        isFetchingModels = true
        defer { isFetchingModels = false }

        guard let provider = config.providers.first(where: { $0.providerType == .openRouter }),
              !provider.apiKey.isEmpty else { return }

        do {
            var urlString = "https://openrouter.ai/api/v1/models"
            if let search = search, !search.isEmpty {
                urlString += "?search=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search)"
            }
            guard let url = URL(string: urlString) else { return }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let modelsArray = json?["data"] as? [[String: Any]] else { return }

            var fetched: [AIModelConfig] = []
            for modelDict in modelsArray {
                guard let modelId = modelDict["id"] as? String,
                      let name = modelDict["name"] as? String else { continue }

                let contextLength = modelDict["context_length"] as? Int ?? 128_000
                let topProvider = modelDict["top_provider"] as? [String: Any]
                let maxOutput = topProvider?["max_completion_tokens"] as? Int ?? 4096

                let model = AIModelConfig(
                    id: modelId,
                    displayName: name,
                    providerId: provider.id,
                    capabilities: AIModelCapabilities(
                        toolCalling: true,
                        streaming: true,
                        webSearch: true,
                        contextWindow: contextLength,
                        maxOutput: maxOutput
                    )
                )
                fetched.append(model)
            }

            openRouterModels = fetched
        } catch {
            Self.log.error("Failed to fetch OpenRouter models: \(error.localizedDescription)")
        }
    }

    func fetchOllamaModels() async {
        isFetchingModels = true
        defer { isFetchingModels = false }

        guard let provider = config.providers.first(where: { $0.providerType == .ollama }) else { return }

        do {
            let url = URL(string: "\(provider.baseURL)/api/tags")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                ollamaModels = []
                return
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let modelsArray = json?["models"] as? [[String: Any]] else {
                ollamaModels = []
                return
            }

            var fetched: [AIModelConfig] = []
            for modelDict in modelsArray {
                guard let name = modelDict["name"] as? String else { continue }
                let model = AIModelConfig(
                    id: name,
                    displayName: name,
                    providerId: provider.id,
                    capabilities: AIModelCapabilities(
                        toolCalling: true,
                        streaming: true,
                        webSearch: false
                    )
                )
                fetched.append(model)
            }

            ollamaModels = fetched.sorted { $0.displayName < $1.displayName }
        } catch {
            Self.log.error("Failed to fetch Ollama models: \(error.localizedDescription)")
            ollamaModels = []
        }
    }

    // MARK: - Default Configuration

    private static func createDefaultConfig() -> AIConfiguration {
        let geminiProvider = AIProviderConfig(
            id: "gemini",
            displayName: "Google Gemini",
            providerType: .gemini
        )
        let openRouterProvider = AIProviderConfig(
            id: "openrouter",
            displayName: "OpenRouter",
            providerType: .openRouter
        )
        let ollamaProvider = AIProviderConfig(
            id: "ollama",
            displayName: "Ollama (Local)",
            providerType: .ollama,
            baseURL: "http://localhost:11434"
        )

        return AIConfiguration(
            providers: [geminiProvider, openRouterProvider, ollamaProvider],
            models: [],
            activeProviderId: nil,
            activeModelId: nil,
            generationConfig: AIGenerationConfig(),
            mcpServers: [],
            browserToolsConfig: BrowserToolsConfig()
        )
    }

    // MARK: - Migration from UserDefaults

    private func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "ai_config_migrated_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        // Migrate API keys
        if let geminiKey = defaults.string(forKey: "settings.geminiApiKey"), !geminiKey.isEmpty {
            if let idx = config.providers.firstIndex(where: { $0.id == "gemini" }) {
                config.providers[idx].apiKey = geminiKey
            }
        }

        if let openRouterKey = defaults.string(forKey: "settings.openRouterApiKey"), !openRouterKey.isEmpty {
            if let idx = config.providers.firstIndex(where: { $0.id == "openrouter" }) {
                config.providers[idx].apiKey = openRouterKey
            }
        }

        if let ollamaEndpoint = defaults.string(forKey: "settings.ollamaEndpoint"), !ollamaEndpoint.isEmpty {
            if let idx = config.providers.firstIndex(where: { $0.id == "ollama" }) {
                config.providers[idx].baseURL = ollamaEndpoint
            }
        }

        // Migrate active provider
        if let providerRaw = defaults.string(forKey: "settings.aiProvider") {
            switch providerRaw {
            case "gemini":
                config.activeProviderId = "gemini"
                if let modelRaw = defaults.string(forKey: "settings.geminiModel") {
                    config.activeModelId = modelRaw
                }
            case "openrouter":
                config.activeProviderId = "openrouter"
                if let modelRaw = defaults.string(forKey: "settings.openRouterModel") {
                    config.activeModelId = modelRaw
                }
            case "ollama":
                config.activeProviderId = "ollama"
                if let modelRaw = defaults.string(forKey: "settings.ollamaModel"), !modelRaw.isEmpty {
                    config.activeModelId = modelRaw
                }
            default:
                break
            }
        }

        // Migrate web search settings
        config.generationConfig.webSearchEnabled = defaults.bool(forKey: "settings.webSearchEnabled")
        if let engine = defaults.string(forKey: "settings.webSearchEngine") {
            config.generationConfig.webSearchEngine = engine
        }
        let maxResults = defaults.integer(forKey: "settings.webSearchMaxResults")
        if maxResults > 0 {
            config.generationConfig.webSearchMaxResults = maxResults
        }
        if let contextSize = defaults.string(forKey: "settings.webSearchContextSize") {
            config.generationConfig.webSearchContextSize = contextSize
        }

        defaults.set(true, forKey: migrationKey)
        save()
        Self.log.info("Migrated AI configuration from UserDefaults")
    }
}
