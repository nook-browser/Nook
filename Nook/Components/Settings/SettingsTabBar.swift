//
//  SettingsTabBar.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import SwiftUI

struct SettingsTabBar: View {
    @Environment(BrowserManager.self) private var browserManager

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
                Text(browserManager.settingsManager.currentSettingsTab.name)
                    .font(.headline)
                Spacer()
            }

        }
        .backgroundDraggable()
    }
}
