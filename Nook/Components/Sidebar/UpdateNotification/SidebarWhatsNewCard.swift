// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarWhatsNewCard.swift
//  Nook
//
//  Created by Bain Gurley on 22/09/2026.
//

import SwiftUI
import NookDesign
import NookUI
import NookWeb

/// Shown once after an update, in the update notification's slot. The whole card opens the
/// release notes; the corner button dismisses it. Either way it is gone until the next version.
struct SidebarWhatsNewCard: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isHovering = false

    // One place to point at a designed page later.
    private static let notesBase = "https://github.com/nook-browser/Nook/releases/tag/v"

    var body: some View {
        // The update card owns this slot while an update is pending.
        if let version = browserManager.whatsNewVersion, browserManager.updateAvailability == nil {
            Button {
                if let url = URL(string: Self.notesBase + version) {
                    browserManager.tabs.open(url: url, in: windowState, placement: .newTab)
                }
                browserManager.whatsNewVersion = nil
            } label: {
                VStack(spacing: NookDesign.Spacing.xxs) {
                    Text("What's new in Nook \(version)")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.primary)
                    Text("See what changed")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, NookDesign.Spacing.lg)
                .padding(.vertical, NookDesign.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button {
                        browserManager.whatsNewVersion = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(NookDesign.Font.micro)
                            .foregroundStyle(.secondary)
                            .frame(width: NookDesign.Size.cornerButton, height: NookDesign.Size.cornerButton)
                    }
                    .buttonStyle(.plain)
                    .padding(NookDesign.Spacing.xs)
                }
            }
            .nookGlassEffect(in: NookDesign.Radius.shape(NookDesign.Radius.lg))
            .onHoverTracking { isHovering = $0 }
            .animation(NookDesign.Motion.quick, value: isHovering)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
