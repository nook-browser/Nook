//
//  AI.swift
//  Nook
//
//  Created by Maciek Bagiński on 08/12/2025.
//

import SwiftUI

struct SettingsAITab: View {
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        @Bindable var settings = nookSettings
        HStack {
            Form {
                Toggle("Enable AI Features", isOn: $settings.showAIAssistant)
                if settings.showAIAssistant {
                    SecureField("API Key", text: $settings.geminiApiKey)
                    Section(header: Text("Models")) {
                        Picker(
                            "Default AI Model",
                            selection: $settings.geminiModel
                        ) {
                            ForEach(GeminiModel.allCases) { model in
                                VStack(alignment: .leading) {
                                    Text(model.displayName)
                                    Text(model.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
