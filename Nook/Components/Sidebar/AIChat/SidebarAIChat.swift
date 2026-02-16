//
//  SidebarAIChat.swift
//  Nook
//
//  AI chat panel for sidebar — view-only layer delegating to AIService
//

import SwiftUI
import AppKit

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date
    var citations: [URLCitation] = []
    var usedWebSearch: Bool = false

    enum Role {
        case user
        case assistant
    }
}

struct URLCitation: Identifiable, Equatable, Codable {
    let id = UUID()
    let url: String
    let title: String?
    let content: String?
    let startIndex: Int
    let endIndex: Int

    var displayTitle: String {
        title ?? url
    }

    var domain: String {
        if let urlObj = URL(string: url),
           let host = urlObj.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return url
    }
}

struct SidebarAIChat: View {
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings
    @Environment(AIService.self) var aiService
    @Environment(AIConfigService.self) var configService

    @State private var messageText: String = ""
    @State private var showAddModelPopover: Bool = false
    @State private var newModelId: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !aiService.hasApiKey {
                            apiKeyRequiredView
                        } else if aiService.messages.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(aiService.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if aiService.isLoading {
                            loadingView
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .onChange(of: aiService.messages.count) { _, _ in
                    if let last = aiService.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(stops: [.init(color: .black.opacity(0.2), location: 0.4), .init(color: .black, location: 1.0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                }.ignoresSafeArea()
            }
        }
        .safeAreaInset(edge: .top, content: {
            headerView
        })
        .safeAreaInset(edge: .bottom) {
            inputAreaView
        }
        .safeAreaPadding(.top, 8)
        .safeAreaPadding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isTextFieldFocused = true

            if configService.activeProviderType == .ollama {
                Task { await configService.fetchOllamaModels() }
            }
        }
        .onChange(of: configService.config.activeProviderId) { _, _ in
            if configService.activeProviderType == .ollama {
                Task { await configService.fetchOllamaModels() }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            Button("Close", systemImage: "xmark") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    windowState.isSidebarAIChatVisible = false
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NavButtonStyle())
            .foregroundStyle(Color.primary)

            if !aiService.messages.isEmpty {
                Text("Ask Nook")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .transition(.blur.animation(.smooth))
            }

            Spacer()

            Button("Settings", systemImage: "gearshape") {
                showSettingsDialog()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NavButtonStyle())
            .foregroundStyle(Color.primary)

            Button("Clear Messages", systemImage: "trash") {
                showClearMessagesDialog()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NavButtonStyle())
            .foregroundStyle(Color.primary)
            .disabled(aiService.messages.isEmpty)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Input Area

    private var inputAreaView: some View {
        VStack(spacing: 8) {
            TextField("Ask about this page...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1...4)
                .focused($isTextFieldFocused)
                .onSubmit { sendMessage() }

            HStack(spacing: 8) {
                // Dynamic model selector
                modelSelectorMenu

                // Web search toggle
                if let providerType = configService.activeProviderType,
                   providerType == .gemini || providerType == .openRouter {
                    webSearchToggle
                }

                Spacer()

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(messageText.isEmpty ? .white.opacity(0.3) : .white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .disabled(messageText.isEmpty || aiService.isLoading || !aiService.hasApiKey)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal, 8)
    }

    // MARK: - Model Selector

    private var modelSelectorMenu: some View {
        Menu(configService.activeModel?.displayName ?? "Add Model") {
            let models = configService.modelsForActiveProvider()
            ForEach(models) { model in
                Button(action: { configService.setActiveModel(model.id) }) {
                    HStack {
                        Text(model.displayName)
                        if configService.config.activeModelId == model.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            // Show fetched dynamic models if available
            if !configService.ollamaModels.isEmpty && configService.activeProviderType == .ollama {
                Divider()
                ForEach(configService.ollamaModels) { model in
                    Button(action: {
                        configService.addModel(model)
                        configService.setActiveModel(model.id)
                    }) {
                        HStack {
                            Text(model.displayName)
                            if configService.config.activeModelId == model.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button(action: { showAddModelPopover = true }) {
                Label("Add Model...", systemImage: "plus.circle")
            }

            Button(action: { showSettingsDialog() }) {
                Label("Manage Models...", systemImage: "gearshape")
            }
        }
        .popover(isPresented: $showAddModelPopover, arrowEdge: .top) {
            VStack(spacing: 8) {
                Text("Add Model by ID")
                    .font(.system(size: 12, weight: .semibold))
                TextField("Model ID (e.g. gpt-4o)", text: $newModelId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 200)
                HStack {
                    Button("Cancel") {
                        newModelId = ""
                        showAddModelPopover = false
                    }
                    .controlSize(.small)
                    Button("Add") {
                        guard !newModelId.isEmpty,
                              let providerId = configService.config.activeProviderId else { return }
                        configService.addModelById(newModelId, displayName: nil, providerId: providerId)
                        configService.setActiveModel(newModelId)
                        newModelId = ""
                        showAddModelPopover = false
                    }
                    .controlSize(.small)
                    .disabled(newModelId.isEmpty || configService.config.activeProviderId == nil)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Web Search Toggle

    private var webSearchToggle: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                var config = configService.generationConfig
                config.webSearchEnabled.toggle()
                configService.generationConfig = config
            }
        }) {
            Image(systemName: configService.generationConfig.webSearchEnabled ? "globe.americas.fill" : "globe")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(configService.generationConfig.webSearchEnabled ? .green : .white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(configService.generationConfig.webSearchEnabled ? .green.opacity(0.15) : .white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .frame(height: 28)
        .frame(width: 36)
    }

    // MARK: - Empty/Loading States

    private var apiKeyRequiredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.3))

            Text("API Key Required")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

            Text("Add your API key to start chatting")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Button(action: { showSettingsDialog() }) {
                Text("Add API Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            let webSearchEnabled = configService.generationConfig.webSearchEnabled
            let supportsWebSearch = configService.activeProviderType == .openRouter || configService.activeProviderType == .gemini

            Image(systemName: webSearchEnabled && supportsWebSearch ? "globe" : "sparkle")
                .font(.system(size: 32))
                .foregroundStyle(webSearchEnabled && supportsWebSearch ? .green.opacity(0.6) : .white.opacity(0.3))

            Text("Ask Nook")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

            if webSearchEnabled && supportsWebSearch {
                VStack(spacing: 6) {
                    Text("Questions about this page, or just curious? I'm here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green.opacity(0.7))
                        Text("Web search enabled")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                Text("Questions about this page, or just curious? I'm here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            VStack(alignment: .leading, spacing: 2) {
                if let toolName = aiService.currentToolName {
                    Text("Using \(toolName)...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.purple.opacity(0.8))
                } else {
                    Text("Thinking...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                if configService.generationConfig.webSearchEnabled && !aiService.isExecutingTools {
                    Text("Searching the web...")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.isEmpty, aiService.hasApiKey else { return }
        let text = messageText
        messageText = ""
        Task {
            await aiService.sendMessage(text, windowState: windowState)
        }
    }

    private func showSettingsDialog() {
        // Open the settings window to the AI tab
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func showClearMessagesDialog() {
        browserManager.dialogManager.showDialog {
            StandardDialog(
                header: {
                    DialogHeader(
                        icon: "trash.fill",
                        title: "Clear Chat History?",
                        subtitle: "This will delete all messages in this conversation"
                    )
                },
                content: {
                    EmptyView()
                },
                footer: {
                    DialogFooter(
                        rightButtons: [
                            DialogButton(
                                text: "Cancel",
                                variant: .secondary,
                                action: {
                                    browserManager.dialogManager.closeDialog()
                                }
                            ),
                            DialogButton(
                                text: "Clear",
                                iconName: "trash",
                                variant: .primary,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        aiService.clearMessages()
                                    }
                                    browserManager.dialogManager.closeDialog()
                                }
                            )
                        ]
                    )
                }
            )
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) var openURL
    @State private var isHovered: Bool = false
    @State private var showCopied: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    VStack(alignment: .leading, spacing: 0) {
                        if message.usedWebSearch {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.system(size: 10, weight: .medium))
                                Text("Web Search")
                                    .font(.system(size: 10, weight: .medium))
                                if !message.citations.isEmpty {
                                    Text("• \(message.citations.count) \(message.citations.count == 1 ? "source" : "sources")")
                                        .font(.system(size: 9, weight: .regular))
                                }
                            }
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(parseMarkdown(message.content).enumerated()), id: \.offset) { _, block in
                                block
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.top, message.usedWebSearch ? 6 : 10)
                        .padding(.bottom, message.citations.isEmpty ? 10 : 6)

                        if !message.citations.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Divider()
                                    .padding(.horizontal, 12)

                                Text("Sources")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.horizontal, 12)

                                VStack(spacing: 4) {
                                    ForEach(message.citations) { citation in
                                        CitationView(citation: citation)
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                            .padding(.bottom, 10)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.12))
                    )
                    .overlay(alignment: .topTrailing) {
                        if isHovered {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                                showCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showCopied = false
                                }
                            }) {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(.black.opacity(0.5))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.white.opacity(0.15), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                } else {
                    Text(message.content)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.black)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.9))
                        )
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func parseMarkdown(_ content: String) -> [AnyView] {
        var views: [AnyView] = []
        let lines = content.components(separatedBy: .newlines)
        var i = 0
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        var codeBlockLanguage: String = ""

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                if inCodeBlock {
                    let code = codeBlockContent.joined(separator: "\n")
                    views.append(AnyView(codeBlockView(code, language: codeBlockLanguage)))
                    codeBlockContent = []
                    codeBlockLanguage = ""
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    codeBlockLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                i += 1
                continue
            }

            if inCodeBlock {
                codeBlockContent.append(line)
                i += 1
                continue
            }

            if line.hasPrefix("### ") {
                views.append(AnyView(headerView(String(line.dropFirst(4)), level: 3)))
            } else if line.hasPrefix("## ") {
                views.append(AnyView(headerView(String(line.dropFirst(3)), level: 2)))
            } else if line.hasPrefix("# ") {
                views.append(AnyView(headerView(String(line.dropFirst(2)), level: 1)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                views.append(AnyView(bulletView(String(line.dropFirst(2)))))
            } else if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                let text = line.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                views.append(AnyView(numberedView(text)))
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                views.append(AnyView(paragraphView(line)))
            }

            i += 1
        }

        return views
    }

    private func headerView(_ text: String, level: Int) -> some View {
        let fontSize: CGFloat = level == 1 ? 17 : level == 2 ? 15 : 14
        let weight: Font.Weight = level == 1 ? .bold : level == 2 ? .semibold : .medium

        return Text(parseInlineMarkdown(text))
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(.white.opacity(0.95))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }

    private func paragraphView(_ text: String) -> some View {
        Text(parseInlineMarkdown(text))
            .font(.system(size: 13, weight: .regular))
            .lineSpacing(4)
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bulletView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 1)
            Text(parseInlineMarkdown(text))
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func numberedView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 1)
            Text(parseInlineMarkdown(text))
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func codeBlockView(_ code: String, language: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !language.isEmpty {
                Text(language)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        do {
            var attributed = try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            attributed.foregroundColor = .white.opacity(0.9)
            return attributed
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Citation View

struct CitationView: View {
    let citation: URLCitation
    @Environment(\.openURL) var openURL
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if let url = URL(string: citation.url) {
                openURL(url)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.domain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(isHovered ? 0.9 : 0.7))
                        .lineLimit(1)

                    if let title = citation.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 0.6 : 0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(isHovered ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(isHovered ? 0.2 : 0.0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
