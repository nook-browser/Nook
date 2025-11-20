//
//  SettingsTabBar.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import SwiftUI

struct SettingsTabBar: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        ZStack {
            BlurEffectView(
                material: nookSettings.currentMaterial,
                state: .active
            )
            HStack {
                MacButtonsView()
                    .frame(width: 70, height: 32)
                Spacer()
                Text(nookSettings.currentSettingsTab.name)
                    .font(.headline)
                Spacer()
            }

        }
        .backgroundDraggable()
    }
}
