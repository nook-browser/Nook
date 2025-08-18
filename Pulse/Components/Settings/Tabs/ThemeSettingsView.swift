//
//  ThemeSettingsView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(
                    title: "Background Material",
                    description: "Choose the visual style for your browser windows"
                ) {
                    SettingsOption(title: "Window Style") {
                        Picker("", selection: $browserManager.settingsManager.currentMaterialRaw) {
                            ForEach(materials, id: \.value.rawValue) { material in
                                Text(material.name).tag(material.value.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                }
                
                Divider()
                
                SettingsSection(title: "Visual Effects") {
                    SettingsOption(
                        title: "Liquid Glass Effect",
                        description: "Enable smooth glass-like visual effects"
                    ) {
                        Toggle("", isOn: $browserManager.settingsManager.isLiquidGlassEnabled)
                            .toggleStyle(SwitchToggleStyle())
                    }
                }
            }
            .padding(24)
        }
    }
}
