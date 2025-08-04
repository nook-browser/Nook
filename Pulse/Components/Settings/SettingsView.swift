//
//  SettingsView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        ZStack {
            WindowBackgroundView()
            VStack(alignment: .leading, spacing: 16) {
                SettingsTabBar()
                    .frame(height: 32)
                Picker(
                    "Background Material",
                    selection: $browserManager.settingsManager.currentMaterialRaw
                ) {
                    ForEach(materials, id: \.value.rawValue) { material in
                        Text(material.name).tag(material.value.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Divider()
                Picker(
                    "Search Engine",
                    selection: $browserManager.settingsManager.searchEngine
                ) {
                    ForEach(SearchProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                Toggle(isOn: $browserManager.settingsManager.isLiquidGlassEnabled) {
                    Text("Liquid Glass")
                }
                Spacer()
            }
            .padding(8)
        }
        .frame(minWidth: 520, minHeight: 360)
        
    }
}
