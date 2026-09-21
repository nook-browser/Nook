// Licensed under GPL-3.0. See LICENSE.
//
//  MediaControlsView.swift
//  Nook
//
//  Created by apelreflex on 13/10/2025.
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

/// Reactive title display that re-renders when the tab's name changes.
/// Observation tracks the session's title.
private struct MediaControlsTabTitle: View {
    let tab: PageSession

    var body: some View {
        Text(tab.title)
            .font(NookDesign.Font.secondary)
            .foregroundStyle(Color.white)
            .padding(.top, 4)
            .lineLimit(1)
            .truncationMode(.tail)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
    }
}

struct MediaControlsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasActiveMedia: Bool = false
    @State private var activeMediaTab: PageSession?
    @State private var isHovering: Bool = false
    @State private var overrideIsPlaying: Bool? = nil
    @State private var overrideIsMuted: Bool? = nil
    @State private var mediaControlsManager: MediaControlsManager?
    @State private var updateTask: Task<Void, Never>?

    // Width thresholds for collapsing behavior
    private var effectiveWidth: CGFloat {
        windowState.sidebarWidth - 16 // Account for horizontal padding
    }

    private var shouldShowFavicon: Bool {
        effectiveWidth >= 200
    }

    private var shouldShowPreviousButton: Bool {
        effectiveWidth >= 150
    }

    // Check if media is currently playing (derived from Tab state)
    private var isPlaying: Bool {
        if let overrideIsPlaying {
            return overrideIsPlaying
        }
        return activeMediaTab?.hasPlayingAudio == true || activeMediaTab?.hasPlayingVideo == true
    }

    private var isMuted: Bool {
        if let overrideIsMuted {
            return overrideIsMuted
        }
        return activeMediaTab?.isAudioMuted == true
    }

    /// The video showing above carries its own controls, so the bar stands down while it is up.
    /// Read here rather than by the sidebar so this view's own body tracks the change.
    private var isVideoShowing: Bool {
        windowState.sidebarPiPController?.isShowing == true
    }

    var body: some View {
        Group {
            if hasActiveMedia, !isVideoShowing, let tab = activeMediaTab {
                VStack(spacing: 8) {
                    // Tab name (shows on hover)
                    if isHovering {
                        MediaControlsTabTitle(tab: tab)
                    }
                    HStack(spacing: 0) {
                        // Tab favicon (collapses first)
                        if shouldShowFavicon {
                            tab.favicon
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }

                        if shouldShowFavicon {
                            Spacer()
                        }

                        // Previous button (collapses second)
                        if shouldShowPreviousButton {
                            Button("Previous", systemImage: "backward.end.fill") {
                                Task {
                                    guard let manager = mediaControlsManager else { return }
                                    await manager.previous(tab: tab)
                                    await MainActor.run {
                                        updateMediaState()
                                    }
                                }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(NookIconButtonStyle(size: 24))
                            .foregroundStyle(Color.white)
                            .help("Previous")
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }

                        if shouldShowPreviousButton || shouldShowFavicon {
                            Spacer()
                        }

                        // Play/Pause button
                        Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                            Task {
                                guard let manager = mediaControlsManager else { return }
                                let newState = await manager.playPause(tab: tab)
                                await MainActor.run {
                                    if let newState {
                                        overrideIsPlaying = newState
                                    }
                                    updateMediaState()
                                }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(NookIconButtonStyle(size: 24))
                        .foregroundStyle(Color.white)
                        .help(isPlaying ? "Pause" : "Play")

                        Spacer()

                        // Next button
                        Button("Next", systemImage: "forward.end.fill") {
                            Task {
                                guard let manager = mediaControlsManager else { return }
                                await manager.next(tab: tab)
                                await MainActor.run {
                                    updateMediaState()
                                }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(NookIconButtonStyle(size: 24))
                        .foregroundStyle(Color.white)
                        .help("Next")

                        Spacer()

                        // Mute toggle
                        Button(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "speaker.slash.fill": "speaker.wave.2.fill") {
                            Task {
                                guard let manager = mediaControlsManager else { return }
                                let newMutedState = await manager.toggleMute(tab: tab)
                                await MainActor.run {
                                    if let newMutedState {
                                        overrideIsMuted = newMutedState
                                    }
                                    updateMediaState()
                                }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(NookIconButtonStyle(size: 24))
                        .foregroundStyle(Color.white)
                        .help(isMuted ? "Unmute" : "Mute")

                        // Bring the video itself back into the sidebar above this bar.
                        if tab.hasVideoContent || tab.hasPlayingVideo {
                            Spacer()

                            Button("Maximize", systemImage: "arrow.up.left.and.arrow.down.right") {
                                maximize(tab)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(NookIconButtonStyle(size: 24))
                            .foregroundStyle(Color.white)
                            .help("Show video in the sidebar")
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    NookDesign.Radius.shape(NookDesign.Radius.md)
                        .fill(Color.black)
                )
                .overlay(
                    NookDesign.Radius.shape(NookDesign.Radius.md)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .onHoverTracking { hovering in
                    withAnimation(NookDesign.Motion.quick) {
                        isHovering = hovering
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(NookDesign.Motion.standard, value: hasActiveMedia)
        .animation(NookDesign.Motion.standard, value: shouldShowFavicon)
        .animation(NookDesign.Motion.standard, value: shouldShowPreviousButton)
        .onAppear {
            if mediaControlsManager == nil {
                let manager = MediaControlsManager(browserManager: browserManager, windowState: windowState)
                manager.windowRegistry = windowRegistry
                mediaControlsManager = manager
            }
            updateMediaState()
        }
        // Trigger when pages open or close, or any page starts or stops playing
        .onChange(of: browserManager.tabs.sessions.count) { _, _ in
            updateMediaState()
        }
        .onChange(of: browserManager.tabs.sessions.contains { $0.hasPlayingAudio || $0.hasPlayingVideo }) { _, _ in
            updateMediaState()
        }
        // Trigger when user switches tabs
        .onChange(of: windowState.selectedItemID) { _, _ in
            updateMediaState()
        }
        // Minimising hands the bar a different page than it was last showing.
        .onChange(of: windowState.sidebarPiPController?.itemID) { _, _ in
            updateMediaState()
        }
        // Trigger when app becomes active (user switches back to app)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                updateMediaState()
            }
        }
        // Trigger when sidebar width changes to update collapsing behavior
        .onChange(of: windowState.sidebarWidth) { _, _ in
            // SwiftUI automatically recomputes shouldShowFavicon and shouldShowPreviousButton
            // when windowState.sidebarWidth changes, so no explicit update needed
        }
    }

    /// The counterpart of the video's minimise button. Falls back to system picture-in-picture
    /// on a page whose video cannot be measured, exactly as leaving the tab does.
    private func maximize(_ tab: PageSession) {
        guard let controller = windowState.sidebarPiPController else { return }
        guard let webView = browserManager.getWebView(for: tab.itemID, in: windowState.id)
            ?? tab.assignedWebView
        else { return }
        withAnimation(NookDesign.Motion.standard) {
            controller.enter(session: tab, webView: webView) {
                PiPManager.shared.requestPiP(for: tab, webView: webView)
            }
        }
    }

    private func updateMediaState() {
        // Cancel any previous update task to debounce rapid calls
        updateTask?.cancel()

        updateTask = Task { @MainActor in
            // Small delay to debounce rapid successive calls
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            // Check if cancelled during sleep
            if Task.isCancelled { return }

            // Lazy initialization - create manager if it doesn't exist
            if mediaControlsManager == nil {
                let manager = MediaControlsManager(browserManager: browserManager, windowState: windowState)
                manager.windowRegistry = windowRegistry
                mediaControlsManager = manager
            }

            guard let manager = mediaControlsManager else {
                return
            }
            // A page the sidebar video was just minimised from wins over the manager's own
            // search, which matches on "is playing" and so skips a paused video and leaves the
            // previously played one showing.
            let foundTab = windowState.sidebarPiPController?.barSession ?? manager.findActiveMediaTab()

            var resolvedTab: PageSession? = foundTab

            if resolvedTab == nil, let current = activeMediaTab,
               let refreshed = browserManager.tabs.session(for: current.itemID) {
                let isCurrentWindowTab = windowState.selectedItemID == refreshed.itemID
                if !isCurrentWindowTab {
                    resolvedTab = refreshed
                }
            }

            // IMPORTANT: Media controls only show for BACKGROUND tabs with playing media
            // This is by design - if the user can see the video/player, they don't need sidebar controls
            if let candidate = resolvedTab,
               windowState.selectedItemID == candidate.itemID {
                resolvedTab = nil
            }

            let hasMedia = resolvedTab != nil

            if hasActiveMedia != hasMedia {
                hasActiveMedia = hasMedia
            }

            if activeMediaTab?.itemID != resolvedTab?.itemID {
                activeMediaTab = resolvedTab
            }

            // Actively sync title from the webview to catch YouTube SPA title changes
            // that KVO may have missed or that happened after the last state update
            if let resolvedTab {
                await manager.refreshTitle(for: resolvedTab)
            }

            if let resolvedTab {
                let liveState = resolvedTab.hasPlayingAudio || resolvedTab.hasPlayingVideo
                if let override = overrideIsPlaying, override == liveState {
                    overrideIsPlaying = nil
                }
                let liveMute = resolvedTab.isAudioMuted
                if let overrideMute = overrideIsMuted, overrideMute == liveMute {
                    overrideIsMuted = nil
                }
            } else {
                overrideIsPlaying = nil
                overrideIsMuted = nil
            }
        }
    }
}
