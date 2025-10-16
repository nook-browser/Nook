//
//  TweaksSettingsView.swift
//  Nook
//
//  Settings view for managing website customizations (Tweaks).
//

import SwiftUI
import SwiftData

struct TweaksSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @StateObject private var tweakManager = TweakManager.shared
    @State private var showingCreateDialog = false
    @State private var showingImportDialog = false
    @State private var selectedTweak: TweakEntity?
    @State private var searchText = ""

    private var filteredTweaks: [TweakEntity] {
        if searchText.isEmpty {
            return tweakManager.availableTweaks
        } else {
            return tweakManager.availableTweaks.filter { tweak in
                tweak.name.localizedCaseInsensitiveContains(searchText) ||
                tweak.urlPattern.localizedCaseInsensitiveContains(searchText) ||
                tweak.tweakDescription?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Website Tweaks")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Customize appearance and behavior of websites")
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Global enable toggle
                Toggle("Enable Tweaks", isOn: Binding(
                    get: { tweakManager.isEnabled },
                    set: { enabled in
                        tweakManager.isEnabled = enabled
                        UserDefaults.standard.set(enabled, forKey: "settings.enableTweaks")
                        if !enabled {
                            Task {
                                await tweakManager.clearAllAppliedTweaks()
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)
            }

            Divider().opacity(0.4)

            // Actions toolbar
            HStack {
                Button(action: { showingCreateDialog = true }) {
                    Label("New Tweak", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button(action: { showingImportDialog = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Button(action: exportTweaks) {
                    Label("Export All", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(tweakManager.availableTweaks.isEmpty)

                Spacer()

                // Search
                TextField("Search tweaks...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }

            Divider().opacity(0.4)

            // Tweaks list
            if filteredTweaks.isEmpty {
                SettingsPlaceholderView(
                    title: searchText.isEmpty ? "No Tweaks Yet" : "No Matching Tweaks",
                    subtitle: searchText.isEmpty
                        ? "Create your first tweak to customize website appearance and behavior"
                        : "Try adjusting your search terms",
                    icon: "paintbrush"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredTweaks, id: \.id) { tweak in
                            TweakRowView(
                                tweak: tweak,
                                onEdit: { selectedTweak = tweak },
                                onToggle: { tweakManager.toggleTweak(tweak) },
                                onDuplicate: { _ in
                                    if let duplicated = tweakManager.duplicateTweak(tweak) {
                                        selectedTweak = duplicated
                                    }
                                },
                                onDelete: { tweakManager.deleteTweak(tweak) }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding()
        .sheet(isPresented: $showingCreateDialog) {
            TweakEditorView(
                tweak: nil,
                onSave: { tweak in
                    // Tweak is already created and saved in the editor
                    showingCreateDialog = false
                },
                onCancel: {
                    showingCreateDialog = false
                }
            )
        }
        .sheet(item: $selectedTweak) { tweak in
            TweakEditorView(
                tweak: tweak,
                onSave: { editedTweak in
                    selectedTweak = nil
                },
                onCancel: {
                    selectedTweak = nil
                }
            )
        }
        .sheet(isPresented: $showingImportDialog) {
            TweakImportView(
                onImport: { importedCount in
                    showingImportDialog = false
                },
                onCancel: {
                    showingImportDialog = false
                }
            )
        }
        .onAppear {
            tweakManager.attach(browserManager: browserManager)
        }
    }

    private func exportTweaks() {
        let panel = NSSavePanel()
        panel.title = "Export Tweaks"
        panel.message = "Choose where to save your tweaks"
        panel.nameFieldStringValue = "nook-tweaks.json"
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let tweaksData = tweakManager.exportTweaks()
                let jsonData = try JSONSerialization.data(withJSONObject: tweaksData, options: .prettyPrinted)
                try jsonData.write(to: url)
                print("🎨 Exported \(tweaksData.count) tweaks to \(url.path)")
            } catch {
                print("🎨 Failed to export tweaks: \(error)")
                // TODO: Show error dialog
            }
        }
    }
}

// MARK: - Tweak Row View
struct TweakRowView: View {
    let tweak: TweakEntity
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDuplicate: (TweakEntity) -> Void
    let onDelete: () -> Void
    @StateObject private var tweakManager = TweakManager.shared

    private var statusIcon: String {
        tweak.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
    }

    private var statusColor: Color {
        tweak.isEnabled ? .green : .orange
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.system(size: 16))

            // Tweak info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tweak.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(tweak.urlPattern)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(Capsule())
                }

                if let description = tweak.tweakDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Rules summary
                let rules = tweakManager.getRules(for: tweak)
                HStack(spacing: 8) {
                    Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Show rule types as badges
                    let ruleTypes = Set(rules.map { $0.type })
                    ForEach(Array(ruleTypes.prefix(3)), id: \.self) { type in
                        Text(type.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }

                    if ruleTypes.count > 3 {
                        Text("+\(ruleTypes.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(tweak.lastModifiedDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Controls
            HStack(spacing: 8) {
                // Enable/disable toggle
                Toggle("", isOn: Binding(
                    get: { tweak.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(tweak.isEnabled ? "Disable tweak" : "Enable tweak")

                // Actions menu
                Menu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(action: {
                        if let duplicated = TweakManager.shared.duplicateTweak(tweak) {
                            onDuplicate(duplicated)
                        }
                    }) {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .help("More options")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1))
                )
        )
    }
}

// MARK: - Tweak Import View
struct TweakImportView: View {
    let onImport: (Int) -> Void
    let onCancel: () -> Void
    @State private var importedFile: URL?
    @State private var importError: String?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Import Tweaks")
                .font(.title)
                .fontWeight(.bold)

            Text("Select a JSON file containing exported tweaks to import them into Nook.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            // File selection
            VStack(spacing: 12) {
                Button("Choose File...") {
                    let panel = NSOpenPanel()
                    panel.title = "Select Tweaks File"
                    panel.message = "Choose a JSON file containing exported tweaks"
                    panel.allowedContentTypes = [.json]
                    panel.allowsMultipleSelection = false

                    if panel.runModal() == .OK, let url = panel.url {
                        importedFile = url
                        importError = nil
                    }
                }
                .buttonStyle(.borderedProminent)

                if let file = importedFile {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.blue)
                        Text(file.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Error display
            if let error = importError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Import") {
                    performImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(importedFile == nil || isImporting)
            }
        }
        .frame(width: 400, height: 300)
        .padding()
    }

    private func performImport() {
        guard let file = importedFile else { return }

        isImporting = true
        importError = nil

        Task {
            do {
                let data = try Data(contentsOf: file)
                let tweaksArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

                await MainActor.run {
                    let importedCount = TweakManager.shared.importTweaks(from: tweaksArray)
                    if importedCount > 0 {
                        onImport(importedCount)
                    } else {
                        importError = "No valid tweaks found in the selected file"
                    }
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importError = "Failed to read the selected file: \(error.localizedDescription)"
                    isImporting = false
                }
            }
        }
    }
}

#Preview {
    TweaksSettingsView()
        .environmentObject(BrowserManager())
        .frame(width: 800, height: 600)
}