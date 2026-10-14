// Licensed under GPL-3.0. See LICENSE.
//
//  Developer.swift
//  Nook
//
//  Developer Mode and Browser Control.
//

import NookSettings
import SwiftUI
import NookDesign

struct SettingsDeveloperTab: View {
    @Environment(\.nookSettings) var nookSettings
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section {
                Toggle("Developer Mode", isOn: $settings.developerModeEnabled)
                    .onChange(of: settings.developerModeEnabled) { _, on in
                        browserManager.tabs.setDeveloperMode(on)
                        DevMCPServer.shared.applyEnabledSetting(on && settings.browserControlServerEnabled)
                    }
            } footer: {
                Text("Shows developer tools and lets you turn on Browser Control.")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.browserControlServerEnabled) {
                    VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                        Text("Allow agents to control this browser")
                            .font(NookDesign.Font.body)
                        Text("Serves MCP on 127.0.0.1:47823 so a coding agent can drive Nook")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!settings.developerModeEnabled)
                // The setting lives in NookSettings, which cannot reach the server; start and
                // stop it from here so the toggle still takes effect without a relaunch.
                .onChange(of: settings.browserControlServerEnabled) {
                    DevMCPServer.shared.applyEnabledSetting($1 && settings.developerModeEnabled)
                }
            } header: {
                Text("Browser Control")
            } footer: {
                Text("A client must send the token from Application Support/com.gstudios.nook/dev-mcp-token. Any program on this Mac can read that file, and with it run JavaScript in your tabs and read pages you are signed in to. Leave this off unless you are driving Nook from an agent.")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
