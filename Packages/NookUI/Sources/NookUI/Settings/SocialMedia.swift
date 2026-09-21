// Licensed under GPL-3.0. See LICENSE.
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
    @State private var newSite = ""

    public init() {}

    public var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section {
                if settings.mediaDownloadSites.isEmpty {
                    Text("No sites added.")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(settings.mediaDownloadSites, id: \.self) { site in
                        Text(site)
                    }
                    .onDelete { settings.mediaDownloadSites.remove(atOffsets: $0) }
                }
                TextField("Add a site (e.g. instagram.com)", text: $newSite)
                    .onSubmit(add)
            } header: {
                Text("Download Button")
            } footer: {
                Text("Shows a download button on photos and videos, and saves the largest size the page offers to Downloads. Subdomains are included.")
            }

            Section {
                Toggle("Hide Reels", isOn: $settings.facebookHideReels)
                Toggle("Hide suggested posts", isOn: $settings.facebookHideSuggested)
            } header: {
                Text("Facebook")
            } footer: {
                Text("Hide Reels removes the Reels carousel from the news feed. Hide suggested posts removes posts from groups, pages, and people you don't follow, and People You May Know. Friends, followed pages, and groups stay.")
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let domain = SiteRoutingRule.normalizeDomain(newSite)
        guard !domain.isEmpty, !nookSettings.mediaDownloadSites.contains(domain) else { return }
        nookSettings.mediaDownloadSites.append(domain)
        newSite = ""
    }
}
