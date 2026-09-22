// Licensed under GPL-3.0. See LICENSE.
//
//  SocialMedia.swift
//  Nook
//
//  Created by Claude on 15/09/2026.
//

import SwiftUI
import NookDesign
import NookSettings

public struct SettingsSocialMediaTab: View {
    @Environment(NookSettingsService.self) var nookSettings
    @State private var newSite = ""
    @State private var showingAddSite = false

    public init() {}

    public var body: some View {
        @Bindable var settings = nookSettings
        Form {
            // Same rows as Site Search in General.
            Section {
                ForEach(settings.mediaDownloadSites, id: \.self) { site in
                    LabeledContent {
                        Button {
                            settings.mediaDownloadSites.removeAll { $0 == site }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    } label: {
                        Text(site)
                    }
                }

                Button {
                    showingAddSite = true
                } label: {
                    Label("Add Site", systemImage: "plus")
                }
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
        .alert("Add Site", isPresented: $showingAddSite) {
            TextField("Add a site (e.g. instagram.com)", text: $newSite)
            Button("Add", action: add)
                .disabled(SiteRoutingRule.normalizeDomain(newSite).isEmpty)
            Button("Cancel", role: .cancel) { newSite = "" }
        }
    }

    private func add() {
        let domain = SiteRoutingRule.normalizeDomain(newSite)
        guard !domain.isEmpty, !nookSettings.mediaDownloadSites.contains(domain) else { return }
        nookSettings.mediaDownloadSites.append(domain)
        newSite = ""
    }
}
