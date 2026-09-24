// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarAIChat.swift
//  Nook
//
//  AI chat panel for sidebar — view-only layer delegating to AIService
//

import SwiftUI
import AppKit
import NookDesign
import NookWeb
import NookUI

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
    var id = UUID()
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

    private let streamingBubbleID = "streaming"

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
                            if aiService.streamingText.isEmpty {
                                loadingView
                            } else {
                                MessageBubble(message: ChatMessage(role: .assistant, content: aiService.streamingText, timestamp: .now))
                                    .id(streamingBubbleID)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .onChange(of: aiService.streamingText) {
                    proxy.scrollTo(streamingBubbleID, anchor: .bottom)
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
                withAnimation(NookDesign.Motion.standard) {
                    windowState.isSidebarAIChatVisible = false
                }
            }
            .nookGlassControls(in: Circle())

            if !aiService.messages.isEmpty {
                Text("Ask Nook")
                    .font(NookDesign.Font.title)
                    .foregroundStyle(.primary)
                    .transition(.blur.animation(NookDesign.Motion.standard))
            }

            Spacer()

            HStack(spacing: 0) {
                Button("Settings", systemImage: "gearshape") {
                    showSettings()
                }
                Divider().padding(.vertical, NookDesign.Spacing.sm)
                Button("Clear Messages", systemImage: "trash") {
                    showClearMessagesDialog()
                }
                .disabled(aiService.messages.isEmpty)
            }
            .frame(height: NookDesign.Size.glassControl)
            .nookGlassControls(in: Capsule())
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Input Area

    private var inputAreaView: some View {
        VStack(spacing: 8) {
            TextField("Ask about this page...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(NookDesign.Font.body)
                .foregroundStyle(.primary)
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
                        .font(NookDesign.Font.titleLarge)
                        .foregroundStyle(messageText.isEmpty ? HierarchicalShapeStyle.tertiary : .primary)
                }
                .buttonStyle(.plain)
                .disabled(messageText.isEmpty || aiService.isLoading || !aiService.hasApiKey)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .nookControlGlass(in: NookDesign.Radius.shape(NookDesign.Radius.lg))
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

            if configService.activeProviderType != .appleIntelligence {
                Button(action: { showAddModelPopover = true }) {
                    Label("Add Model...", systemImage: "plus.circle")
                }
            }

            Button(action: { showSettings() }) {
                Label("Manage Models...", systemImage: "gearshape")
            }
        }
        .popover(isPresented: $showAddModelPopover, arrowEdge: .top) {
            VStack(spacing: 8) {
                Text("Add Model by ID")
                    .font(NookDesign.Font.secondary)
                TextField("Model ID (e.g. gpt-4o)", text: $newModelId)
                    .textFieldStyle(.roundedBorder)
                    .font(NookDesign.Font.secondary)
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
            withAnimation(NookDesign.Motion.standard) {
                var config = configService.generationConfig
                config.webSearchEnabled.toggle()
                configService.generationConfig = config
            }
        }) {
            Image(systemName: configService.generationConfig.webSearchEnabled ? "globe.americas.fill" : "globe")
                .font(NookDesign.Font.body)
                .foregroundStyle(configService.generationConfig.webSearchEnabled ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    NookDesign.Radius.shape(NookDesign.Radius.sm)
                        .fill(configService.generationConfig.webSearchEnabled ? .green.opacity(0.15) : NookDesign.Surface.fill)
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
                .font(NookDesign.Font.display)
                .foregroundStyle(.tertiary)

            Text("API Key Required")
                .font(NookDesign.Font.label)
                .foregroundStyle(.primary)

            Text("Add your API key to start chatting")
                .font(NookDesign.Font.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showSettings() }) {
                Text("Add API Key")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .nookControlGlass(in: Capsule())
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
                .font(NookDesign.Font.display)
                .foregroundStyle(webSearchEnabled && supportsWebSearch ? AnyShapeStyle(.green.opacity(0.6)) : AnyShapeStyle(.tertiary))

            Text("Ask Nook")
                .font(NookDesign.Font.label)
                .foregroundStyle(.primary)

            if webSearchEnabled && supportsWebSearch {
                VStack(spacing: 6) {
                    Text("Questions about this page, or just curious? I'm here.")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.green.opacity(0.7))
                        Text("Web search enabled")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.green.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.12))
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                }
            } else {
                Text("Questions about this page, or just curious? I'm here.")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
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
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.purple.opacity(0.8))
                } else {
                    Text("Thinking...")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                }
                if configService.generationConfig.webSearchEnabled && !aiService.isExecutingTools {
                    Text("Searching the web...")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.tertiary)
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

    private func showSettings() {
        browserManager.openSettings(tab: .ai)
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
                                    withAnimation(NookDesign.Motion.standard) {
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
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) var openURL
    @State private var isHovered: Bool = false
    @State private var showCopied: Bool = false

    /// The person's own messages carry the space's accent; private windows keep the neutral one.
    private var accent: Color {
        windowState.isIncognito ? SpaceGradient.incognito.primaryColor : gradientColorManager.accentColor
    }

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
                                    .font(NookDesign.Font.caption)
                                Text("Web Search")
                                    .font(NookDesign.Font.caption)
                                if !message.citations.isEmpty {
                                    Text("• \(message.citations.count) \(message.citations.count == 1 ? "source" : "sources")")
                                        .font(NookDesign.Font.caption)
                                }
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.15))
                            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
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
                                    .font(NookDesign.Font.caption)
                                    .foregroundStyle(.secondary)
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
                    .nookControlGlass(in: NookDesign.Radius.shape(NookDesign.Radius.lg))
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
                                    .font(NookDesign.Font.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    // Raised, not glass: it sits on the bubble's glass
                                    .background(
                                        NookDesign.Radius.shape(NookDesign.Radius.md)
                                            .fill(NookDesign.Surface.raised)
                                    )
                                    .overlay(
                                        NookDesign.Radius.shape(NookDesign.Radius.md)
                                            .strokeBorder(NookDesign.Surface.hairline, lineWidth: NookDesign.Size.hairlineWidth)
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                } else {
                    Text(message.content)
                        .font(NookDesign.Font.bodyRegular)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .nookControlGlass(tint: accent, in: NookDesign.Radius.shape(NookDesign.Radius.lg))
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
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
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }

    private func paragraphView(_ text: String) -> some View {
        Text(parseInlineMarkdown(text))
            .font(NookDesign.Font.bodyRegular)
            .lineSpacing(4)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bulletView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(NookDesign.Font.body)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(parseInlineMarkdown(text))
                .font(NookDesign.Font.bodyRegular)
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func numberedView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(NookDesign.Font.body)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(parseInlineMarkdown(text))
                .font(NookDesign.Font.bodyRegular)
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func codeBlockView(_ code: String, language: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !language.isEmpty {
                Text(language)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(NookDesign.Surface.fill)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
            }
            Text(code)
                .font(NookDesign.Font.secondary.monospaced())
                .foregroundStyle(.primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NookDesign.Surface.fillPressed)
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        }
    }

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
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
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.domain)
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(isHovered ? .primary : .secondary)
                        .lineLimit(1)

                    if let title = citation.title, !title.isEmpty {
                        Text(title)
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                NookDesign.Radius.shape(NookDesign.Radius.sm)
                    .fill(isHovered ? NookDesign.Surface.fillPressed : NookDesign.Surface.fill)
            )
            .overlay(
                NookDesign.Radius.shape(NookDesign.Radius.sm)
                    .stroke(isHovered ? NookDesign.Surface.hairline : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
                isHovered = hovering
            }
        }
    }
}
