//
//  General.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import SwiftUI

struct SettingsGeneralTab: View {
    @Environment(\.nookSettings) var nookSettings
    @State private var showingAddSite = false

    var body: some View {
        @Bindable var settings = nookSettings
        HStack(alignment: .top) {
            MemberCard()
            Form {
                Toggle("Warn before quitting Nook", isOn: $settings.askBeforeQuit)
                Toggle("Automatically update Nook", isOn: .constant(true))
                    .disabled(true)
                Toggle("Nook's Ad Blocker", isOn: .constant(false))
                    .disabled(true)

                Section(header: Text("Search")) {
                    Picker(
                        "Default search engine",
                        selection: $settings.searchEngine
                    ) {
                        ForEach(SearchProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
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
        }
        .sheet(isPresented: $showingAddSite) {
            SiteSearchEntryEditor(entry: nil) { newEntry in
                nookSettings.siteSearchEntries.append(newEntry)
            }
        }
    }
}
