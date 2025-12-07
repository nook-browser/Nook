//
//  Appearance.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import SwiftUI

struct SettingsAppearanceTab: View {
    @Environment(\.nookSettings) var nookSettings


    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Picker(
                "Background Material",
                selection: $settings
                    .currentMaterialRaw
            ) {
                ForEach(materials, id: \.value.rawValue) {
                    material in
                    Text(material.name).tag(
                        material.value.rawValue
                    )
                }
            }
            Toggle("Liquid Glass", isOn: .constant(true))
            Picker(
                "Sidebar Position",
                selection: $settings
                    .sidebarPosition
            ) {
                ForEach(SidebarPosition.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            Toggle("Show URL bar in the web view",isOn: $settings.topBarAddressView)
            Picker(
                "Favorites Appearance",
                selection: $settings.pinnedTabsLook
            ) {
                ForEach(PinnedTabsConfiguration.allCases) { config in
                    Text(config.name).tag(config)
                }
            }
            Toggle("Preview link URL on hover",
                isOn: $settings
                    .showLinkStatusBar
            )
        }
        .formStyle(.grouped)
    }
}
