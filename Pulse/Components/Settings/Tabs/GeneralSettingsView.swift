//
//  GeneralSettingsView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(title: "Search") {
                    SettingsOption(
                        title: "Default Search Engine",
                        description: "Choose your preferred search provider"
                    ) {
                        Picker("", selection: $browserManager.settingsManager.searchEngine) {
                            ForEach(SearchProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                }
            }
            .padding(24)
        }
    }
}
