//
//  SettingsTabBar.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import SwiftUI

struct SettingsTabBar: View {
    @EnvironmentObject var browserManager: BrowserManager
    var currentTab: SettingsTabs = .general

    var body: some View {
        ZStack {
            BlurEffectView(
                material: browserManager.settingsManager.currentMaterial,
                state: .active
            )
            HStack {
                MacButtonsView()
                    .frame(width: 70, height: 32)
                Spacer()
                Text(currentTab.name)
                    .font(.headline)
                Spacer()
            }

        }
        .backgroundDraggable()
    }
}
