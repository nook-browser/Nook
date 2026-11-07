// Licensed under GPL-3.0. See LICENSE.
//
//  SiteSettingsButton.swift
//  Nook
//

import SwiftUI
import WebKit
import NookBlocker
import NookDesign
import NookSettings
import NookUI
import NookWeb

/// URL bar button that opens per-site settings for the current http(s) page.
struct SiteSettingsButton: View {
    let session: PageSession
    /// Keeps the button visible while its popover is open.
    @Binding var isPresented: Bool
    /// Owned by the URL bar so the button stays in the hierarchy while the alert is up.
    @Binding var confirmClear: Bool
    @EnvironmentObject private var browserManager: BrowserManager
    /// The registrable domain the clear removes, resolved when the popover opens.
    @State private var dataDomain: String?

    private var host: String? {
        guard ["http", "https"].contains(session.url.scheme?.lowercased()) else { return nil }
        return session.url.host()
    }

    var body: some View {
        if let host {
            Button("Site Settings", systemImage: "switch.2") { isPresented = true }
                .labelStyle(.iconOnly)
                .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.iconButton, radius: NookDesign.Radius.sm))
                .foregroundStyle(Color.primary)
                .help("Site Settings")
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    SiteSettingsPopover(session: session, host: host) {
                        isPresented = false
                        confirmClear = true
                    }
                    .id(host)
                    .environmentObject(browserManager)
                }
                .onChange(of: isPresented) { _, open in
                    guard open, let store = session.webView?.configuration.websiteDataStore else { return }
                    dataDomain = nil
                    Task { dataDomain = await CacheManager.siteDataDomain(host: host, in: store) }
                }
                .alert("Clear data for \(dataDomain ?? host)?", isPresented: $confirmClear) {
                    Button("Clear", role: .destructive) {
                        guard let store = session.webView?.configuration.websiteDataStore else { return }
                        Task {
                            await CacheManager.clearSiteData(host: host, in: store)
                            session.webView?.reload()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You'll be signed out of \(dataDomain ?? host) and its subdomains.")
                }
        }
    }
}

private struct SiteSettingsPopover: View {
    let session: PageSession
    let host: String
    let onClear: () -> Void
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(\.nookSettings) private var nookSettings
    @State private var zoomPercent = 100
    @State private var coveringRule: String?
    @State private var camera = SitePermissionPolicy.ask
    @State private var microphone = SitePermissionPolicy.ask

    private let width: CGFloat = 280

    private var blocksAds: Bool { coveringRule == nil }
    private var ruleIsParent: Bool { coveringRule.map { $0 != host.lowercased() } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.lg) {
            Text(host).font(NookDesign.Font.secondary.weight(.semibold)).lineLimit(1)

            HStack {
                Text("Zoom")
                Spacer()
                Text("\(zoomPercent)%").foregroundStyle(.secondary)
                if zoomPercent != 100 {
                    Button("Reset") {
                        if let webView = session.webView { browserManager.zoomManager.resetZoom(for: webView) }
                        zoomPercent = 100
                    }
                }
            }

            VStack(alignment: .leading, spacing: NookDesign.Spacing.xs) {
                Toggle("Block ads and trackers", isOn: Binding(get: { blocksAds }, set: setBlocksAds))
                    .disabled(ruleIsParent)
                if let rule = coveringRule, ruleIsParent {
                    Text("Allowed by a rule for \(rule) in Settings > Ad Blocker.")
                        .font(NookDesign.Font.micro).foregroundStyle(.secondary)
                }
            }

            policyPicker("Camera", .camera, $camera)
            policyPicker("Microphone", .microphone, $microphone)

            Button("Clear Cookies and Site Data", role: .destructive, action: onClear)
        }
        .font(NookDesign.Font.secondary)
        .padding(NookDesign.Spacing.xl)
        .frame(width: width)
        .onAppear {
            zoomPercent = Int(((session.webView?.pageZoom ?? 1) * 100).rounded())
            coveringRule = AllowlistRule.covering(host, in: nookSettings.adBlockerWhitelist)
            camera = nookSettings.permission(.camera, for: host)
            microphone = nookSettings.permission(.microphone, for: host)
        }
    }

    private func setBlocksAds(_ on: Bool) {
        browserManager.contentBlockerManager.allowDomain(coveringRule ?? host.lowercased(), allowed: !on)
        coveringRule = AllowlistRule.covering(host, in: nookSettings.adBlockerWhitelist)
    }

    private func policyPicker(_ title: String, _ permission: SitePermission, _ value: Binding<SitePermissionPolicy>) -> some View {
        Picker(title, selection: Binding(get: { value.wrappedValue }, set: {
            value.wrappedValue = $0
            nookSettings.setPermission(permission, to: $0, for: host)
        })) {
            ForEach(SitePermissionPolicy.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.menu)
    }
}
