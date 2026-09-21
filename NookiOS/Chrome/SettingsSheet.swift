// Licensed under GPL-3.0. See LICENSE.
//
//  SettingsSheet.swift
//  NookiOS
//
//  The shared settings bodies in a NavigationStack. They are grouped Forms
//  already, so they read as Settings.app without a redesign. The Mac's AI,
//  Advanced, Extensions and Shortcuts tabs stay on the Mac.
//

import SwiftUI
import NookDesign
import NookUI

struct SettingsSheet: View {
    @EnvironmentObject private var model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $model.settingsPath) {
            List {
                Section {
                    row(.general)
                    row(.appearance)
                    row(.spaces)
                }
                Section {
                    row(.adBlocker)
                    row(.airTrafficControl)
                }
                Section("Tweaks") {
                    row(.youTube)
                    row(.socialMedia)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { route in
                body(for: route)
                    .navigationTitle(route.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ route: SettingsRoute) -> some View {
        NavigationLink(route.title, value: route)
    }

    @ViewBuilder
    private func body(for route: SettingsRoute) -> some View {
        switch route {
        case .general: SettingsGeneralTab()
        case .appearance: SettingsAppearanceTab()
        case .spaces: SpacesSettingsView()
        case .adBlocker: SettingsAdBlockerTab()
        case .airTrafficControl: AirTrafficControlSettingsView()
        case .youTube: SettingsYouTubeTab()
        case .socialMedia: SettingsSocialMediaTab()
        }
    }
}
