//
//  ProfilesSettingsView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import SwiftUI

struct ProfilesSettingsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Profiles Coming Soon", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("User profiles and customization options will be available in a future update.")
        }
    }
}
