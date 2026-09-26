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
    @State private var showingRecommendedSites = false
    @State private var selectedRecommendedSites: Set<String> = []

    private static let recommendedSites = [
        RecommendedSite(name: "Instagram", domain: "instagram.com"),
        RecommendedSite(name: "Facebook", domain: "facebook.com"),
        RecommendedSite(name: "VSCO", domain: "vsco.co"),
    ]

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
                        .accessibilityLabel("Remove \(site)")
                    } label: {
                        Text(site)
                    }
                }

                if settings.mediaDownloadSites.isEmpty {
                    Text("No sites added")
                        .foregroundStyle(.secondary)
                }

                if Self.recommendedSites.contains(where: { !isAdded($0.domain) }) {
                    Button {
                        selectedRecommendedSites.removeAll()
                        showingRecommendedSites = true
                    } label: {
                        Label("Add recommended sites…", systemImage: "plus")
                    }
                }

                Button {
                    showingAddSite = true
                } label: {
                    Label("Add custom site…", systemImage: "plus")
                }
            } header: {
                Text("Media downloads")
            } footer: {
                Text(settings.mediaDownloadSites.isEmpty
                     ? "Add a site to show a download button on its photos and videos. Downloads use the largest available file. Subdomains are included."
                     : "Shows a download button on photos and videos from these sites. Downloads use the largest available file. Subdomains are included.")
            }

            Section {
                Toggle(isOn: $settings.facebookHideReels) {
                    VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                        Text("Hide Reels")
                        Text("Removes the Reels carousel from the news feed.")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $settings.facebookHideSuggested) {
                    VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                        Text("Hide suggested posts")
                        Text("Removes suggested posts and People You May Know. Friends and followed pages and groups stay.")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Facebook")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingRecommendedSites) {
            recommendedSitesPicker
        }
        .alert("Add custom site", isPresented: $showingAddSite) {
            TextField("Domain (e.g. example.com)", text: $newSite)
            Button("Add", action: add)
                .disabled(SiteRoutingRule.normalizeDomain(newSite).isEmpty || isAdded(SiteRoutingRule.normalizeDomain(newSite)))
            Button("Cancel", role: .cancel) { newSite = "" }
        }
    }

    private func add() {
        let domain = SiteRoutingRule.normalizeDomain(newSite)
        guard !domain.isEmpty, !isAdded(domain) else { return }
        nookSettings.mediaDownloadSites.append(domain)
        newSite = ""
    }

    private var recommendedSitesPicker: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.lg) {
            Text("Recommended sites")
                .font(NookDesign.Font.heading)

            Form {
                Section {
                    ForEach(Self.recommendedSites) { site in
                        Toggle(isOn: Binding(
                            get: { isAdded(site.domain) || selectedRecommendedSites.contains(site.domain) },
                            set: { selected in
                                if selected {
                                    selectedRecommendedSites.insert(site.domain)
                                } else {
                                    selectedRecommendedSites.remove(site.domain)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                                Text(site.name)
                                Text(isAdded(site.domain) ? "Added" : site.domain)
                                    .font(NookDesign.Font.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isAdded(site.domain))
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { showingRecommendedSites = false }
                Spacer()
                Button("Add selected") { addRecommended(selectedRecommendedSites) }
                    .disabled(selectedRecommendedSites.isEmpty)
                Button("Add all") {
                    addRecommended(Set(Self.recommendedSites.map(\.domain)))
                }
            }
        }
        .padding(NookDesign.Spacing.xl)
        #if os(macOS)
        .frame(width: 460, height: 330)
        #endif
    }

    private func isAdded(_ domain: String) -> Bool {
        nookSettings.mediaDownloadSites.contains { SiteRoutingRule.normalizeDomain($0) == domain }
    }

    private func addRecommended(_ domains: Set<String>) {
        var sites = nookSettings.mediaDownloadSites
        var existing = Set(sites.map(SiteRoutingRule.normalizeDomain))
        for site in Self.recommendedSites where domains.contains(site.domain) && !existing.contains(site.domain) {
            sites.append(site.domain)
            existing.insert(site.domain)
        }
        nookSettings.mediaDownloadSites = sites
        selectedRecommendedSites.removeAll()
        showingRecommendedSites = false
    }

    private struct RecommendedSite: Identifiable {
        let name: String
        let domain: String
        var id: String { domain }
    }
}
