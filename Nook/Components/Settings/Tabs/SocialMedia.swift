//
//  SocialMedia.swift
//  Nook
//
//  Created by Claude on 15/09/2026.
//

import SwiftUI

struct SettingsSocialMediaTab: View {
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section {
                Toggle("Download button", isOn: $settings.socialImageDownload)
            } footer: {
                Text("Shows a download button on photos and videos on Instagram, Facebook, and VSCO, and saves the largest size the page offers to Downloads. Applies when one of these pages next loads.")
            }
        }
        .formStyle(.grouped)
    }
}
