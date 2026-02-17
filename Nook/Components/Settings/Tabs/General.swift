//
//  General.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import SwiftUI

struct SettingsGeneralTab: View {
    @Environment(\.nookSettings) var nookSettings


    var body: some View {
        @Bindable var settings = nookSettings
        HStack{
            MemberCard()
            Form {
                Toggle("Warn before quitting Nook",isOn: $settings.askBeforeQuit)
                Toggle("Automatically update Nook", isOn: .constant(true))
                    .disabled(true)
                Toggle("Nook's Ad Blocker", isOn: .constant(false))
                    .disabled(true)
                
                Section(header: Text("Search")) {
                    Picker(
                        "Default search engine",
                        selection: $settings
                            .searchEngine
                    ) {
                        ForEach(SearchProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                }

                Section(header: Text("Site Search")) {
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
                        }
                    }
                    .onDelete { indexSet in
                        nookSettings.siteSearchEntries.remove(atOffsets: indexSet)
                    }

                    Button("Reset to Defaults") {
                        nookSettings.siteSearchEntries = SiteSearchEntry.defaultSites
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
