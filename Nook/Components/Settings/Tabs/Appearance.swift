//
//  Appearance.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import NookSettings
import SwiftUI

struct SettingsAppearanceTab: View {
    @Environment(\.nookSettings) var nookSettings


    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Layout") {
                Picker("Sidebar Position", selection: $settings.sidebarPosition) {
                    ForEach(SidebarPosition.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                Toggle("Show URL bar in the web view", isOn: $settings.topBarAddressView)
                Toggle("Preview link URL on hover", isOn: $settings.showLinkStatusBar)
            }
        }
        .formStyle(.grouped)
    }
}
