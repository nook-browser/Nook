// Licensed under GPL-3.0. See LICENSE.
//
//  General.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import SwiftUI
import NookDesign
import NookSettings
import NookSync
import NookWeb

public struct SettingsGeneralTab: View {
    @Environment(TabsController.self) private var tabs
    @Environment(NookSettingsService.self) var nookSettings
    @State private var showingAddSite = false
    @State private var showingAddEngine = false
    @State private var showingDeleteSyncData = false

    private var syncStatusText: String {
        guard nookSettings.syncEnabled, let engine = tabs.syncEngine else { return "Off" }
        switch engine.status {
        case .off: return "Off"
        case .noAccount: return "No iCloud account"
        case .syncing: return "Syncing…"
        case .synced: return "Synced"
        case .quotaExceeded: return "iCloud storage is full"
        case .error(let message): return message
        }
    }

    public init() {}

    /// The provider list, shared by both platforms' spellings of the row.
    @ViewBuilder
    private func searchEnginePicker(_ settings: NookSettingsService) -> some View {
        @Bindable var settings = settings
        Picker("Default search engine", selection: $settings.searchEngineId) {
            ForEach(SearchProvider.allCases) { provider in
                Text(provider.displayName).tag(provider.rawValue)
            }
            ForEach(nookSettings.customSearchEngines) { engine in
                Text(engine.name).tag(engine.id.uuidString)
            }
        }
    }

    public var body: some View {
        @Bindable var settings = nookSettings
        Form {
            #if os(macOS)
            // Quitting and Sparkle updates are both macOS-only concepts.
            Section {
                Toggle("Warn before quitting Nook", isOn: $settings.askBeforeQuit)
                Toggle("Automatically update Nook", isOn: .constant(true))
                    .disabled(true)
            }

            Section {
                Toggle("Keep videos playing in the sidebar", isOn: $settings.autoPictureInPicture)
            } footer: {
                Text("Leaving a tab with a playing video moves it into a small window above the sidebar media controls.")
            }
            #endif

            Section {
                Toggle("Sync spaces and pinned tabs with iCloud", isOn: Binding(
                    get: { nookSettings.syncEnabled },
                    set: { enabled in
                        nookSettings.syncEnabled = enabled
                        if enabled {
                            tabs.syncEngine?.start()
                        } else {
                            tabs.syncEngine?.stop(discardState: false)
                        }
                    }
                ))
                LabeledContent("Status") {
                    Text(syncStatusText)
                        .foregroundStyle(.secondary)
                }
                Button("Delete iCloud Data…", role: .destructive) {
                    showingDeleteSyncData = true
                }
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text("Favorites, pinned tabs and spaces stay the same on every Mac signed into your iCloud account. Regular tabs stay on the Mac they were opened on.")
            }
            .confirmationDialog(
                "Delete all Nook data from iCloud?",
                isPresented: $showingDeleteSyncData
            ) {
                Button("Delete iCloud Data", role: .destructive) {
                    nookSettings.syncEnabled = false
                    Task { await tabs.syncEngine?.deleteCloudData() }
                }
            } message: {
                Text("Sync turns off and every synced space and tab is removed from your iCloud account. Nothing on this Mac is deleted.")
            }

            Section {
                Picker("Tab Management", selection: Binding(
                    get: { nookSettings.tabManagementMode },
                    set: { nookSettings.tabManagementMode = $0 }
                )) {
                    ForEach(TabManagementMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("On Startup", selection: Binding(
                    get: { nookSettings.startupLoadMode },
                    set: { nookSettings.startupLoadMode = $0 }
                )) {
                    ForEach(StartupLoadMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Button("Unload All Inactive Tabs") {
                    tabs.unloadAllHidden()
                }
            } header: {
                Text("Performance")
            } footer: {
                VStack(alignment: .leading, spacing: NookDesign.Spacing.xs) {
                    Label(
                        nookSettings.tabManagementMode.description,
                        systemImage: nookSettings.tabManagementMode.icon
                    )
                    Label(nookSettings.startupLoadMode.description, systemImage: "power")
                }
            }

            Section {
                #if os(macOS)
                LabeledContent("Default search engine") {
                    HStack(spacing: NookDesign.Spacing.md) {
                        searchEnginePicker(settings)
                            .labelsHidden()

                        Button {
                            showingAddEngine = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                #else
                // A picker inside a LabeledContent's trailing slot gets squeezed
                // to "G...gle" at phone width. The Form's own picker row does not,
                // so the add button takes a row of its own.
                searchEnginePicker(settings)
                Button("Add Search Engine…") { showingAddEngine = true }
                #endif

                if let selected = nookSettings.customSearchEngines.first(where: { $0.id.uuidString == nookSettings.searchEngineId }) {
                    LabeledContent {
                        Button("Remove") {
                            nookSettings.customSearchEngines.removeAll { $0.id == selected.id }
                            nookSettings.searchEngineId = SearchProvider.google.rawValue
                        }
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                    } label: {
                        Text(selected.name)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Search")
            }

            Section {
                ForEach(nookSettings.siteSearchEntries) { entry in
                    LabeledContent {
                        HStack(spacing: NookDesign.Spacing.md) {
                            Text(entry.domain)
                                .foregroundStyle(.secondary)
                            Button {
                                nookSettings.siteSearchEntries.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    } label: {
                        Label {
                            Text(entry.name)
                        } icon: {
                            Circle()
                                .fill(entry.color)
                                .frame(
                                    width: NookDesign.Size.statusDot,
                                    height: NookDesign.Size.statusDot
                                )
                        }
                    }
                }

                Button {
                    showingAddSite = true
                } label: {
                    Label("Add Site", systemImage: "plus")
                }

                Button("Reset to Defaults") {
                    nookSettings.siteSearchEntries = SiteSearchEntry.defaultSites
                }
            } header: {
                Text("Site Search")
            } footer: {
                Text("Type a prefix in the command palette and press Tab to search a site directly.")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSite) {
            SiteSearchEntryEditor(entry: nil) { newEntry in
                nookSettings.siteSearchEntries.append(newEntry)
            }
        }
        .sheet(isPresented: $showingAddEngine) {
            CustomSearchEngineEditor { newEngine in
                nookSettings.customSearchEngines.append(newEngine)
            }
        }
    }
}

// MARK: - Custom Search Engine Editor

struct CustomSearchEngineEditor: View {
    let onSave: (CustomSearchEngine) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var urlTemplate: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.xl) {
            Text("Add Custom Search Engine")
                .font(NookDesign.Font.heading)

            Form {
                Section {
                    TextField("Name (e.g. Startpage)", text: $name)
                    TextField("URL Template (use %@ for query)", text: $urlTemplate)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    let engine = CustomSearchEngine(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        urlTemplate: urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onSave(engine)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || urlTemplate.isEmpty)
            }
        }
        .padding(NookDesign.Spacing.xxl)
        .frame(width: NookDesign.Size.sheetSmallWidth)
    }
}
