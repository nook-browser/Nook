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

    @ObservationIgnored
    nonisolated(unsafe) private var loadTask: Task<ModelContainer, Error>?
    @ObservationIgnored
    nonisolated(unsafe) private var generationTask: Task<String, Error>?
    private var loadID: UUID?
    private var generationID: UUID?

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
        loadTask?.cancel()
        generationTask?.cancel()
        memoryPressureSource?.cancel()
        idleTimerTask?.cancel()
    }

    // MARK: - Public Interface

    /// Downloads the model if not already cached, then loads it into memory.
    /// After this call, the engine is ready for generation.
    func ensureDownloaded() async throws {
        try Task.checkCancellation()
        if modelContainer != nil { return }

        let task: Task<ModelContainer, Error>
        let id: UUID
        if let existing = loadTask, let existingID = loadID {
            task = existing
            id = existingID
        } else {
            id = UUID()
            loadID = id
            status = .loading
            idleTimerTask?.cancel()
            let configuration = ModelConfiguration(id: Self.modelID)
            let reportProgress: @MainActor @Sendable (Double) -> Void = { [weak self] fraction in
                guard let self, self.loadID == id,
                      self.loadTask?.isCancelled == false,
                      fraction < 1 else { return }
                self.status = .downloading(fraction)
            }
            task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let container = try await LLMModelFactory.shared.loadContainer(
                    configuration: configuration
                ) { progress in
                    let fraction = progress.fractionCompleted
                    Task { await reportProgress(fraction) }
                }
                try Task.checkCancellation()
                return container
            }
            loadTask = task
        }

        do {
            let container = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard !task.isCancelled else { throw CancellationError() }
            if loadID == id {
                loadTask = nil
                loadID = nil
                modelContainer = container
                status = .loaded
                resetIdleTimer()
            }
        } catch {
            if loadID == id {
                loadTask = nil
                loadID = nil
                status = (error is CancellationError || task.isCancelled)
                    ? .ready : .error(error.localizedDescription)
            }
            if error is CancellationError || task.isCancelled { throw CancellationError() }
            throw EngineError.loadFailed(error.localizedDescription)
        }
    }

    /// Generate one request at a time. Cancellation reaches MLX's token producer,
    /// and waits for its GPU work to finish before permitting another generation.
    func generate(systemPrompt: String, userPrompt: String, maxTokens: Int = 1024) async throws -> String {
        try Task.checkCancellation()
        guard generationTask == nil else { throw EngineError.alreadyGenerating }
        try await ensureDownloaded()
        try Task.checkCancellation()
        guard generationTask == nil else { throw EngineError.alreadyGenerating }
        guard let container = modelContainer else { throw EngineError.modelNotLoaded }

        idleTimerTask?.cancel()
        idleTimerTask = nil
        let id = UUID()
        generationID = id
        status = .generating
        let task = Task.detached(priority: .userInitiated) { [container] in
            try Task.checkCancellation()
            return try await container.perform { context in
                let input = try await context.processor.prepare(input: UserInput(chat: [
                    .system(systemPrompt), .user(userPrompt),
                ]))
                try Task.checkCancellation()
                let iterator = try TokenIterator(
                    input: input, model: context.model,
                    parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.1)
                )
                try Task.checkCancellation()
                let (stream, producer) = MLXLMCommon.generateTask(
                    promptTokenCount: input.text.tokens.size,
                    modelConfiguration: context.configuration,
                    tokenizer: context.tokenizer,
                    iterator: iterator
                )
                return try await withTaskCancellationHandler {
                    var output = ""
                    for await generation in stream {
                        if Task.isCancelled { break }
                        if let chunk = generation.chunk { output += chunk }
                    }
                    // MLX synchronizes its GPU stream before this task completes.
                    await producer.value
                    try Task.checkCancellation()
                    return output
                } onCancel: {
                    producer.cancel()
                }
            }
        }
        generationTask = task
        defer {
            if generationID == id {
                generationTask = nil
                generationID = nil
                if status == .generating { status = modelContainer == nil ? .ready : .loaded }
                if modelContainer != nil { resetIdleTimer() }
            }
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard !task.isCancelled else { throw CancellationError() }
            return result
        } catch {
            if error is CancellationError || task.isCancelled { throw CancellationError() }
            if generationID == id { status = .error(error.localizedDescription) }
            throw error
        }
    }

    /// Unload the model from memory, freeing resources.
    func unload() {
        loadTask?.cancel()
        generationTask?.cancel()
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
