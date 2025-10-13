//
//  MediaControlsView.swift
//  Nook
//
//  Created by apelreflex on 13/10/2025.
//

import SwiftUI

struct MediaControlsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasActiveMedia: Bool = false
    @State private var activeMediaTab: Tab?
    @State private var isHovering: Bool = false
    @State private var overrideIsPlaying: Bool? = nil
    @State private var overrideIsMuted: Bool? = nil

    // Create manager directly from environment
    private var mediaControlsManager: MediaControlsManager {
        MediaControlsManager(browserManager: browserManager, windowState: windowState)
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

    var body: some View {
        let _ = print("[MediaControlsView] body rendered - hasActiveMedia: \(hasActiveMedia)")

        Group {
            if hasActiveMedia, let tab = activeMediaTab {
                VStack(spacing: 8) {
                    // Tab name (shows on hover)
                    if isHovering {
                        Text(tab.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white)
                            .padding(.top, 4)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                    }
                    HStack(spacing: 0) {
                        // Tab favicon
                        tab.favicon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Spacer()

                        // Previous button
                        Button("Previous", systemImage: "backward.fill") {
                            Task {
                                await mediaControlsManager.previous(tab: tab)
                                await MainActor.run {
                                    updateMediaState()
                                }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(NavButtonStyle())
                        .foregroundStyle(Color.white)
                        .help("Previous")

                        Spacer()

                        // Play/Pause button
                        Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                            Task {
                                let newState = await mediaControlsManager.playPause(tab: tab)
                                await MainActor.run {
                                    if let newState {
                                        overrideIsPlaying = newState
                                    }
                                    updateMediaState()
                                }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(NavButtonStyle())
                        .foregroundStyle(Color.white)
                        .help(isPlaying ? "Pause" : "Play")

                        Spacer()

                        // Next button
                        Button("Next", systemImage: "forward.fill") {
                            Task {
                                await mediaControlsManager.next(tab: tab)
                                await MainActor.run {
                                    updateMediaState()
                                }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(NavButtonStyle())
                        .foregroundStyle(Color.white)
                        .help("Next")

                        Spacer()

                        // Mute toggle
                        Button(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "speaker.slash.fill": "speaker.wave.2.fill") {
                            Task {
                                let newMutedState = await mediaControlsManager.toggleMute(tab: tab)
                                await MainActor.run {
                                    if let newMutedState {
                                        overrideIsMuted = newMutedState
                                    }
                                    updateMediaState()
                                }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(NavButtonStyle())
                        .foregroundStyle(Color.white)
                        .help(isMuted ? "Unmute" : "Mute")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovering = hovering
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: hasActiveMedia)
        .onAppear {
            updateMediaState()
        }
        // Trigger when spaces change (tabs added/removed)
        .onChange(of: browserManager.tabManager.spaces) { _, _ in
            updateMediaState()
        }
        // Trigger when user switches tabs
        .onChange(of: windowState.currentTabId) { _, _ in
            updateMediaState()
        }
        // Trigger when app becomes active (user switches back to app)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                updateMediaState()
            }
        }
        // Slower fallback timer (10 seconds) - catches edge cases where events don't fire
        // Tab's JavaScript already checks every 5 seconds, so this is just a safety net
        .onReceive(Timer.publish(every: 10.0, on: .main, in: .common).autoconnect()) { _ in
            updateMediaState()
        }
    }

    private func updateMediaState() {
        print("🎬 [MediaControlsView] updateMediaState() called")

        let manager = mediaControlsManager
        let foundTab = manager.findActiveMediaTab()

        var resolvedTab: Tab? = foundTab

        if resolvedTab == nil, let current = activeMediaTab,
           let refreshed = browserManager.tabManager.allTabs().first(where: { $0.id == current.id }) {
            let isCurrentWindowTab = windowState.currentTabId == refreshed.id
            if !isCurrentWindowTab {
                resolvedTab = refreshed
            }
        }

        if let candidate = resolvedTab,
           windowState.currentTabId == candidate.id {
            print("🎬 [MediaControlsView] Active tab is visible in this window, clearing media controls")
            resolvedTab = nil
        }

        let hasMedia = resolvedTab != nil

        print("🎬 [MediaControlsView] hasMedia: \(hasMedia), current hasActiveMedia: \(hasActiveMedia)")

        if hasActiveMedia != hasMedia {
            print("🎬 [MediaControlsView] Updating hasActiveMedia: \(hasActiveMedia) -> \(hasMedia)")
            hasActiveMedia = hasMedia
        }

        if activeMediaTab?.id != resolvedTab?.id {
            print("🎬 [MediaControlsView] Updating activeMediaTab: \(activeMediaTab?.url.absoluteString ?? "nil") -> \(resolvedTab?.url.absoluteString ?? "nil")")
            activeMediaTab = resolvedTab
        } else if let resolvedTab {
            // Refresh reference to keep metadata in sync
            activeMediaTab = resolvedTab
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
