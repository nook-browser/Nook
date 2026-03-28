//
//  LocalLLMEngine.swift
//  Nook
//
//  MLX model lifecycle manager for local LLM inference.
//  Handles model download, loading, text generation, idle unloading, and memory pressure response.
//

import Foundation
import MLXLMCommon
import MLXLLM
import OSLog

// MARK: - LocalLLMEngine

@MainActor
@Observable
final class LocalLLMEngine {

    // MARK: - Types

    enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case loading
        case loaded
        case generating
        case error(String)

        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.notDownloaded, .notDownloaded),
                 (.ready, .ready),
                 (.loading, .loading),
                 (.loaded, .loaded),
                 (.generating, .generating):
                return true
            case (.downloading(let a), .downloading(let b)):
                return a == b
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    enum EngineError: LocalizedError {
        case modelNotLoaded
        case alreadyGenerating
        case loadFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Model is not loaded. Call ensureDownloaded() first."
            case .alreadyGenerating:
                return "A generation request is already in progress."
            case .loadFailed(let reason):
                return "Failed to load model: \(reason)"
            }
        }
    }

    // MARK: - Properties

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "LocalLLMEngine")

    /// The HuggingFace model ID to use.
    static let modelID = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

    /// Current engine status, observable for UI binding.
    private(set) var status: Status = .notDownloaded

    /// Idle timeout before auto-unloading the model (in seconds). Default: 5 minutes.
    var idleTimeout: TimeInterval = 300

    /// The loaded model container, if any.
    private var modelContainer: ModelContainer?

    /// Timer task for idle unloading.
    /// `@ObservationIgnored` prevents the @Observable macro from synthesizing tracked storage,
    /// which would conflict with the `nonisolated(unsafe)` needed for deinit access.
    @ObservationIgnored
    nonisolated(unsafe) private var idleTimerTask: Task<Void, Never>?

    /// Memory pressure source for responding to system memory warnings.
    @ObservationIgnored
    nonisolated(unsafe) private var memoryPressureSource: DispatchSourceMemoryPressure?

    // MARK: - Init / Deinit

    init() {
        setupMemoryPressureMonitor()
    }

    deinit {
        memoryPressureSource?.cancel()
        idleTimerTask?.cancel()
    }

    // MARK: - Public Interface

    /// Downloads the model if not already cached, then loads it into memory.
    /// After this call, the engine is ready for generation.
    func ensureDownloaded() async throws {
        // If already loaded or loading, nothing to do.
        if status == .loaded || status == .loading || status == .generating {
            return
        }

        status = .loading
        Self.log.info("Loading model: \(Self.modelID)")

        do {
            let configuration = ModelConfiguration(id: Self.modelID)

            // Use Task.detached to avoid blocking the main actor during heavy I/O.
            let container = try await Task.detached(priority: .userInitiated) {
                try await LLMModelFactory.shared.loadContainer(
                    configuration: configuration
                ) { progress in
                    let fractionCompleted = progress.fractionCompleted
                    Task { @MainActor in
                        // Only show downloading status if we're actually downloading (not already loaded).
                        if fractionCompleted < 1.0 {
                            self.status = .downloading(fractionCompleted)
                        }
                    }
                }
            }.value

            self.modelContainer = container
            self.status = .loaded
            Self.log.info("Model loaded successfully")
            resetIdleTimer()
        } catch {
            let message = error.localizedDescription
            self.status = .error(message)
            Self.log.error("Failed to load model: \(message)")
            throw EngineError.loadFailed(message)
        }
    }

    /// Generate text from a system prompt and user prompt using the loaded model.
    ///
    /// - Parameters:
    ///   - systemPrompt: The system instruction for the model.
    ///   - userPrompt: The user query or input.
    ///   - maxTokens: Maximum number of tokens to generate (default: 1024).
    /// - Returns: The generated text as a String.
    func generate(systemPrompt: String, userPrompt: String, maxTokens: Int = 1024) async throws -> String {
        guard let container = modelContainer, status == .loaded || status == .generating else {
            // Attempt auto-load if not loaded yet.
            if modelContainer == nil {
                try await ensureDownloaded()
                return try await generate(systemPrompt: systemPrompt, userPrompt: userPrompt, maxTokens: maxTokens)
            }
            throw EngineError.modelNotLoaded
        }

        status = .generating
        Self.log.info("Starting generation (maxTokens: \(maxTokens))")

        defer {
            if status == .generating {
                status = .loaded
            }
            resetIdleTimer()
        }

        do {
            let result = try await Task.detached(priority: .userInitiated) { [container] in
                // Build chat messages
                let chat: [Chat.Message] = [
                    .system(systemPrompt),
                    .user(userPrompt),
                ]
                let userInput = UserInput(chat: chat)

                // Prepare input through the model's processor
                let input = try await container.prepare(input: userInput)

                // Configure generation parameters
                let parameters = GenerateParameters(
                    maxTokens: maxTokens,
                    temperature: 0.1
                )

                // Generate tokens via the AsyncStream API
                let stream = try await container.generate(
                    input: input,
                    parameters: parameters
                )

                // Collect all chunks into the output string
                var output = ""
                for await generation in stream {
                    if let chunk = generation.chunk {
                        output += chunk
                    }
                }

                return output
            }.value

            Self.log.info("Generation complete (\(result.count) characters)")
            return result
        } catch {
            let message = error.localizedDescription
            status = .error(message)
            Self.log.error("Generation failed: \(message)")
            throw error
        }
    }

    /// Unload the model from memory, freeing resources.
    func unload() {
        idleTimerTask?.cancel()
        idleTimerTask = nil
        modelContainer = nil

        if status != .notDownloaded {
            status = .ready
        }

        Self.log.info("Model unloaded")
    }

    // MARK: - Idle Timer

    private func resetIdleTimer() {
        idleTimerTask?.cancel()
        idleTimerTask = Task { [weak self, idleTimeout] in
            do {
                try await Task.sleep(for: .seconds(idleTimeout))
                guard let self, !Task.isCancelled else { return }
                Self.log.info("Idle timeout reached, unloading model")
                self.unload()
            } catch {
                // Task was cancelled, nothing to do.
            }
        }
    }

    // MARK: - Memory Pressure

    private func setupMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let event = source.data
                if event.contains(.critical) {
                    Self.log.warning("Critical memory pressure — unloading model")
                    self.unload()
                } else if event.contains(.warning) {
                    // Only unload on warning if we're idle (not actively generating).
                    if self.status == .loaded {
                        Self.log.warning("Memory pressure warning — unloading idle model")
                        self.unload()
                    }
                }
            }
        }
        source.resume()
        memoryPressureSource = source
    }
}
