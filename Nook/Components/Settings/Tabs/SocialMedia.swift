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

            Section {
                Toggle("Hide Reels", isOn: $settings.facebookHideReels)
                Toggle("Hide suggested posts", isOn: $settings.facebookHideSuggested)
            } header: {
                Text("Facebook")
            } footer: {
                Text("Hide Reels removes the Reels carousel from the news feed. Hide suggested posts removes posts from groups, pages, and people you don't follow, and People You May Know. Friends, followed pages, and your groups stay. Applies when Facebook next loads.")
            }
        }
        .formStyle(.grouped)
    }
}
