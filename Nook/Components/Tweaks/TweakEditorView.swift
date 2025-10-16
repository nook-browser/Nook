//
//  TweakEditorView.swift
//  Nook
//
//  Live preview editor for creating and editing website tweaks.
//

import SwiftUI
import SwiftData

struct TweakEditorView: View {
    let tweak: TweakEntity?
    let onSave: (TweakEntity) -> Void
    let onCancel: () -> Void

    @StateObject private var tweakManager = TweakManager.shared
    @State private var name: String = ""
    @State private var urlPattern: String = ""
    @State private var description: String = ""
    @State private var selectedProfileId: UUID?
    @State private var rules: [TweakRuleEntity] = []
    @State private var showingRuleEditor = false
    @State private var editingRule: TweakRuleEntity?
    @State private var isPreviewMode = false
    @State private var previewURL: String = ""

    private var isEditing: Bool { tweak != nil }
    private var isCreating: Bool { tweak == nil }

    init(tweak: TweakEntity?, onSave: @escaping (TweakEntity) -> Void, onCancel: @escaping () -> Void) {
        self.tweak = tweak
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationView {
            // Left panel - Editor
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isCreating ? "New Tweak" : "Edit Tweak")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Customize website appearance and behavior")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    // Preview toggle
                    Button(action: { isPreviewMode.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: isPreviewMode ? "eye.slash" : "eye")
                            Text(isPreviewMode ? "Edit" : "Preview")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()

                Divider()

                // Editor content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Basic information
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Basic Information")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 12) {
                                // Name
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Name")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    TextField("Enter tweak name...", text: $name)
                                        .textFieldStyle(.roundedBorder)
                                }

                                // URL Pattern
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("URL Pattern")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    TextField("example.com or *.example.com", text: $urlPattern)
                                        .textFieldStyle(.roundedBorder)
                                    Text("Supports exact domains, wildcards (*.example.com), and full URL patterns")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                // Description
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Description")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    TextField("Optional description...", text: $description, axis: .vertical)
                                        .textFieldStyle(.roundedBorder)
                                        .lineLimit(3)
                                }

                                // Profile assignment
                                // TODO: Add profile selection when profiles are available
                            }
                        }

                        Divider()

                        // Rules section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Rules")
                                    .font(.headline)
                                Spacer()
                                Button(action: { showingRuleEditor = true }) {
                                    Label("Add Rule", systemImage: "plus")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }

                            if rules.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "list.bullet")
                                        .font(.system(size: 32))
                                        .foregroundColor(.secondary)
                                    Text("No Rules Yet")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Add rules to customize the website")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(rules, id: \.id) { rule in
                                        RuleRowView(
                                            rule: rule,
                                            onEdit: { editingRule = rule },
                                            onToggle: { tweakManager.toggleRule(rule) },
                                            onDelete: { tweakManager.deleteRule(rule) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .frame(minWidth: 400, maxWidth: 500)

            // Right panel - Preview
            VStack(spacing: 0) {
                // Preview header
                HStack {
                    Text("Live Preview")
                        .font(.headline)
                    Spacer()
                    if isPreviewMode {
                        TextField("URL for preview...", text: $previewURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }
                }
                .padding()

                Divider()

                // Preview content
                if isPreviewMode {
                    WebViewPreview(
                        url: previewURL.isEmpty ? nil : URL(string: previewURL),
                        tweak: buildCurrentTweak()
                    )
                } else {
                    // Rules configuration view
                    RulesConfigurationView(
                        rules: $rules,
                        onAddRule: { showingRuleEditor = true }
                    )
                }
            }
            .frame(minWidth: 400)
            .background(Color(.windowBackgroundColor))
        }
        .navigationTitle(isCreating ? "New Tweak" : "Edit Tweak")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveTweak()
                }
                .disabled(name.isEmpty || urlPattern.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            loadTweakData()
        }
        .sheet(isPresented: $showingRuleEditor) {
            RuleEditorView(
                rule: editingRule,
                onSave: { rule in
                    if editingRule != nil {
                        // Update existing rule
                        tweakManager.updateRule(rule)
                    } else {
                        // Add new rule
                        if let currentTweak = buildCurrentTweak() {
                            tweakManager.addRule(to: currentTweak, rule: rule)
                        }
                    }
                    refreshRules()
                    showingRuleEditor = false
                    editingRule = nil
                },
                onCancel: {
                    showingRuleEditor = false
                    editingRule = nil
                }
            )
        }
    }

    private func loadTweakData() {
        if let tweak = tweak {
            name = tweak.name
            urlPattern = tweak.urlPattern
            description = tweak.tweakDescription ?? ""
            selectedProfileId = tweak.profileId
            refreshRules()
        }

        // Set preview URL to current tab if available
        // TODO: Get current tab URL from browser manager
        previewURL = "https://example.com"
    }

    private func refreshRules() {
        if let currentTweak = buildCurrentTweak() {
            rules = tweakManager.getRules(for: currentTweak)
        }
    }

    private func buildCurrentTweak() -> TweakEntity? {
        if let existingTweak = tweak {
            return existingTweak
        } else if !name.isEmpty && !urlPattern.isEmpty {
            // Create temporary tweak for preview
            let tempTweak = TweakEntity(
                name: name,
                urlPattern: urlPattern,
                profileId: selectedProfileId,
                tweakDescription: description.isEmpty ? nil : description
            )
            return tempTweak
        }
        return nil
    }

    private func saveTweak() {
        guard !name.isEmpty && !urlPattern.isEmpty else { return }

        let savedTweak: TweakEntity
        if let existingTweak = tweak {
            // Update existing tweak
            existingTweak.name = name
            existingTweak.urlPattern = urlPattern
            existingTweak.tweakDescription = description.isEmpty ? nil : description
            existingTweak.profileId = selectedProfileId
            existingTweak.markAsModified()
            tweakManager.updateTweak(existingTweak)
            savedTweak = existingTweak
        } else {
            // Create new tweak
            if let newTweak = tweakManager.createTweak(
                name: name,
                urlPattern: urlPattern,
                profileId: selectedProfileId,
                description: description.isEmpty ? nil : description
            ) {
                savedTweak = newTweak
            } else {
                return // Handle creation failure
            }
        }

        onSave(savedTweak)
    }
}

// MARK: - Rule Row View
struct RuleRowView: View {
    let rule: TweakRuleEntity
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Rule type icon
            Image(systemName: ruleTypeIcon)
                .foregroundColor(ruleTypeColor)
                .font(.system(size: 16))
                .frame(width: 24, height: 24)

            // Rule details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.type.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    // Priority badge
                    Text("Priority: \(rule.priority)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }

                if let selector = rule.selector, !selector.isEmpty {
                    Text("Selector: \(selector)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Value preview based on type
                if rule.type == .customCSS, let css = rule.getCustomCSS() {
                    Text("CSS: \(css.prefix(50))\(css.count > 50 ? "..." : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if rule.type == .customJavaScript, let js = rule.getCustomJavaScript() {
                    Text("JS: \(js.prefix(50))\(js.count > 50 ? "..." : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Controls
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.1))
                )
        )
    }

    private var ruleTypeIcon: String {
        switch rule.type {
        case .colorAdjustment: return "paintbrush"
        case .fontOverride: return "textformat"
        case .sizeTransform: return "arrow.up.left.and.arrow.down.right"
        case .caseTransform: return "textformat"
        case .elementHide: return "eye.slash"
        case .customCSS: return "doc.text"
        case .customJavaScript: return "doc.plaintext"
        }
    }

    private var ruleTypeColor: Color {
        switch rule.type {
        case .colorAdjustment: return .blue
        case .fontOverride: return .green
        case .sizeTransform: return .orange
        case .caseTransform: return .purple
        case .elementHide: return .red
        case .customCSS: return .cyan
        case .customJavaScript: return .indigo
        }
    }
}

// MARK: - Rules Configuration View
struct RulesConfigurationView: View {
    @Binding var rules: [TweakRuleEntity]
    let onAddRule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rules Configuration")
                .font(.headline)

            Text("Configure how this tweak will modify the target website. Each rule can be independently enabled or disabled.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rules, id: \.id) { rule in
                        RuleConfigurationCard(rule: rule)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Rule Configuration Card
struct RuleConfigurationCard: View {
    let rule: TweakRuleEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rule.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(rule.isEnabled ? "Active" : "Inactive")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(rule.isEnabled ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                    .foregroundColor(rule.isEnabled ? .green : .gray)
                    .clipShape(Capsule())
            }

            // Rule-specific configuration preview
            ruleConfigurationPreview
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1))
                )
        )
    }

    @ViewBuilder
    private var ruleConfigurationPreview: some View {
        switch rule.type {
        case .colorAdjustment:
            if let adjustment = rule.getColorAdjustment() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type: \(adjustment.type.displayName)")
                        .font(.caption)
                    Text("Amount: \(adjustment.amount, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .fontOverride:
            if let font = rule.getFontOverride() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Font: \(font.fontFamily)")
                        .font(.caption)
                    Text("Weight: \(font.weight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .sizeTransform:
            if let transform = rule.getSizeTransform() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scale: \(transform.scale, specifier: "%.2f")")
                        .font(.caption)
                    Text("Zoom: \(transform.zoom, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .caseTransform:
            if let caseType = rule.getCaseTransform() {
                Text("Transform: \(caseType.displayName)")
                    .font(.caption)
            }

        case .elementHide:
            if let selector = rule.getElementHideSelector() {
                Text("Hide elements: \(selector)")
                    .font(.caption)
                    .lineLimit(2)
            }

        case .customCSS:
            if let css = rule.getCustomCSS() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom CSS:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(css)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(10)
                }
            }

        case .customJavaScript:
            if let js = rule.getCustomJavaScript() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom JavaScript:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(js)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(10)
                }
            }
        }
    }
}

#Preview {
    TweakEditorView(
        tweak: nil,
        onSave: { _ in },
        onCancel: { }
    )
    .frame(width: 1000, height: 700)
}