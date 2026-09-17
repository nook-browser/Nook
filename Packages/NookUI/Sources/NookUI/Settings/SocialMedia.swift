//
//  SocialMedia.swift
//  Nook
//
//  Created by Claude on 15/09/2026.
//

import SwiftUI
import NookSettings

public struct SettingsSocialMediaTab: View {
    @Environment(NookSettingsService.self) var nookSettings

    public init() {}

    public var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section {
                Toggle("Instagram", isOn: $settings.instagramDownload)
                Toggle("Facebook", isOn: $settings.facebookDownload)
                Toggle("VSCO", isOn: $settings.vscoDownload)
            } header: {
                Text("Download Button")
            } footer: {
                Text("Shows a download button on photos and videos, and saves the largest size the page offers to Downloads.")
            }

            Section {
                Toggle("Hide Reels", isOn: $settings.facebookHideReels)
                Toggle("Hide suggested posts", isOn: $settings.facebookHideSuggested)
            } header: {
                Text("Facebook")
            } footer: {
                Text("Hide Reels removes the Reels carousel from the news feed. Hide suggested posts removes posts from groups, pages, and people you don't follow, and People You May Know. Friends, followed pages, and your groups stay.")
            }
        }
        .formStyle(.grouped)
    }
}
