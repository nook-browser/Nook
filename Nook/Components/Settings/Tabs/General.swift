//
//  General.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import SwiftUI

struct SettingsGeneralTab: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.nookSettings) var nookSettings
    @State private var showingAddSite = false
    @State private var showingAddEngine = false

    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section {
                Toggle("Warn before quitting Nook", isOn: $settings.askBeforeQuit)
                Toggle("Automatically update Nook", isOn: .constant(true))
                    .disabled(true)
            }

            Section("Performance") {
                Picker("Tab Management", selection: Binding(
                    get: { nookSettings.tabManagementMode },
                    set: { nookSettings.tabManagementMode = $0 }
                )) {
                    ForEach(TabManagementMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: nookSettings.tabManagementMode.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(nookSettings.tabManagementMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("On Startup", selection: Binding(
                    get: { nookSettings.startupLoadMode },
                    set: { nookSettings.startupLoadMode = $0 }
                )) {
                    ForEach(StartupLoadMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "power")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(nookSettings.startupLoadMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Unload All Inactive Tabs") {
                    tabManager.unloadAllInactiveTabs()
                }
            }

            Section(header: Text("Search")) {
                HStack {
                    Picker(
                        "Default search engine",
                        selection: $settings.searchEngineId
                    ) {
                        ForEach(SearchProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                        ForEach(nookSettings.customSearchEngines) { engine in
                            Text(engine.name).tag(engine.id.uuidString)
                        }
                    }

                    Button {
                        showingAddEngine = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let selected = nookSettings.customSearchEngines.first(where: { $0.id.uuidString == nookSettings.searchEngineId }) {
                    HStack {
                        Text(selected.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") {
                            nookSettings.customSearchEngines.removeAll { $0.id == selected.id }
                            nookSettings.searchEngineId = SearchProvider.google.rawValue
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                ForEach(nookSettings.siteSearchEntries) { entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 10, height: 10)
                        Text(entry.name)
                        Spacer()
                        Text(entry.domain)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Button {
                            nookSettings.siteSearchEntries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Search Engine")
                .font(.headline)

            Form {
                TextField("Name (e.g. Startpage)", text: $name)
                TextField("URL Template (use %@ for query)", text: $urlTemplate)
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
        .padding(20)
        .frame(width: 450)
    }
}
