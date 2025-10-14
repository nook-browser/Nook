//
//  SettingsTabBar.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import SwiftUI

struct SettingsTabBar: View {
    @Environment(\.nookSettings) private var settings

    var body: some View {
        ZStack {
            BlurEffectView(
                material: settings.currentMaterial,
                state: .active
            )
            HStack {
                MacButtonsView()
                    .frame(width: 70, height: 32)
                Spacer()
                Text(settings.currentSettingsTab.name)
                    .font(.headline)
                Spacer()
            }

        }
        .backgroundDraggable()
    }
}
