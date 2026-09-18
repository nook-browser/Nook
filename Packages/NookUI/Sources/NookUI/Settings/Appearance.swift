// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  Appearance.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import NookSettings
import SwiftUI

public struct SettingsAppearanceTab: View {
    @Environment(NookSettingsService.self) var nookSettings


    public init() {}

    public var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            // Every row here is about the Mac window: a sidebar side, the
            // floating URL bar, and a hover preview. None has a touch meaning.
            #if os(macOS)
            Section("Layout") {
                Picker("Sidebar Position", selection: $settings.sidebarPosition) {
                    ForEach(SidebarPosition.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                Toggle("Show URL bar in the web view", isOn: $settings.topBarAddressView)
                Toggle("Preview link URL on hover", isOn: $settings.showLinkStatusBar)
            }
            #endif
        }
        .formStyle(.grouped)
    }
}
