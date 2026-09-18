// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  URLBarView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import AppKit
import NookDesign
import NookWeb
import NookUI

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    @State private var isHovering: Bool = false
    @State private var showCheckmark: Bool = false
    var isSidebarHovered: Bool

    var body: some View {
        let session = browserManager.tabs.selectedSession(in: windowState)
        ZStack {
            HStack(spacing: NookDesign.Spacing.sm) {
                    // URL text area — tappable to open command palette
                    Group {
                        if session != nil {
                            HStack(spacing: NookDesign.Spacing.xs) {
                                Image(systemName: isSecure(for: session) ? "lock.fill" : "globe")
                                    .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                                    .foregroundStyle(.secondary)
                                (Text(displayHost(for: session)).foregroundStyle(.primary) + Text(displayPath(for: session)).foregroundStyle(.tertiary))
                                    .font(NookDesign.Font.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        } else {
                            HStack(spacing: NookDesign.Spacing.xs) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                                    .foregroundStyle(textColor)
                                Text("Search or Enter URL...")
                                    .font(NookDesign.Font.secondary)
                                    .foregroundStyle(textColor)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let urlString = session?.url.absoluteString ?? ""
                        windowState.commandPalette?.open(prefill: urlString, navigateCurrentTab: true)
                    }

                    // Copy link button (show on hover when tab is selected)
                    if isHovering, let session {
                        Button("Copy Link", systemImage: showCheckmark ? "checkmark" : "link") {
                            copyURLToClipboard(session.url.absoluteString)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.rowButton, radius: NookDesign.Radius.sm))
                        .foregroundStyle(Color.primary)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .contentTransition(.symbolEffect(.replace))
                    }

                    // PiP button (show when video content is available or PiP is active)
                    if let session, (session.hasVideoContent || session.hasPiPActive) {
                        Button(action: {
                            session.requestPictureInPicture()
                        }) {
                            Image(systemName: session.hasPiPActive ? "pip.exit" : "pip.enter")
                                .font(NookDesign.Font.secondary)
                                .foregroundStyle(textColor.opacity(session.hasPiPActive ? 1.0 : 0.7))
                        }
                        .buttonStyle(.plain)
                        .help(session.hasPiPActive ? "Exit Picture in Picture" : "Enter Picture in Picture")
                    }
                    
                    // Pinned extension buttons + library button
                    if let extensionManager = browserManager.extensionManager {
                        let pinnedIDs = browserManager.nookSettings?.pinnedExtensionIDs ?? []
                        let pinnedExtensions = extensionManager.installedExtensions.filter { pinnedIDs.contains($0.id) }

                        if !pinnedExtensions.isEmpty {
                            ExtensionActionView(extensions: pinnedExtensions)
                                .environmentObject(browserManager)
                        }

                        ExtensionLibraryButton()
                            .environmentObject(browserManager)
                            .onAppear {
                                let installedIDs = extensionManager.installedExtensions
                                    .filter { $0.isEnabled }
                                    .map { $0.id }
                                browserManager.nookSettings?.migrateExtensionPinStateIfNeeded(installedExtensionIDs: installedIDs)
                            }
                    }
                }
                .padding(.horizontal, NookDesign.Spacing.rowPadding)
        }
        .frame(maxWidth: .infinity, minHeight: NookDesign.Size.urlBar, maxHeight: NookDesign.Size.urlBar)
        .background(
           backgroundColor
        )
        .overlay(alignment: .bottom) {
            PageLoadingProgressBar(session: session)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: NookDesign.Radius.md, bottomTrailingRadius: NookDesign.Radius.md, style: .continuous))
        }
        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        // Report the frame in the window space so we can overlay the mini palette above all content
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: URLBarFramePreferenceKey.self,
                    value: proxy.frame(in: .named("WindowSpace"))
                )
            }
        )
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
                isHovering = hovering
            }
        }
        
    }
    
    private var backgroundColor: Color {
        isHovering ? NookDesign.Surface.fillPressed : NookDesign.Surface.fill
    }
    private var textColor: Color {
        .secondary
    }
    
    private func displayURL(for session: PageSession?) -> String {
        guard let session else { return "" }
        return formatURL(session.url)
    }

    private func isSecure(for session: PageSession?) -> Bool { session?.url.scheme == "https" }
    private func displayHost(for session: PageSession?) -> String { session?.url.host ?? displayURL(for: session) }
    private func displayPath(for session: PageSession?) -> String {
        guard let url = session?.url, url.host != nil else { return "" }
        let path = url.path
        return path == "/" ? "" : path
    }


        private func formatURL(_ url: URL) -> String {
            guard let host = url.host else {
                return url.absoluteString
            }
            
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            
            return cleanHost
        }
    
    private func copyURLToClipboard(_ urlString: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        
        // Show checkmark icon briefly
        withAnimation(NookDesign.Motion.standard) {
            showCheckmark = true
        }
        
        // Show toast notification
        windowState.isShowingCopyURLToast = true
        
        // Reset checkmark after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(NookDesign.Motion.standard) {
                showCheckmark = false
            }
        }
        
        // Hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            windowState.isShowingCopyURLToast = false
        }
    }
}
