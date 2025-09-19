//
//  SpaceTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct SpaceTab: View {
    @ObservedObject var tab: Tab
    var action: () -> Void
    var onClose: () -> Void
    var onMute: () -> Void
    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    tab.favicon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(tab.isUnloaded ? 0.5 : 1.0)
                    
                    if tab.isUnloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .background(Color.gray)
                            .clipShape(Circle())
                            .offset(x: 6, y: -6)
                    }
                }
                Text(tab.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tab.isUnloaded ? AppColors.textSecondary : textTab)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()

                // Mute button (show when tab has audio content OR is muted)
                if tab.hasAudioContent || tab.isAudioMuted {
                    Button(action: {
                        onMute()
                    }) {
                        Image(systemName: tab.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(tab.isAudioMuted ? AppColors.textSecondary : textTab)
                            .padding(4)
                            .background(AppColors.controlBackgroundHover)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(tab.isAudioMuted ? "Unmute Audio" : "Mute Audio")
                    .transition(.scale.combined(with: .opacity))
                }

                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 12, height: 12)
                            .padding(6)
                            .background(isCloseHovering ? .white.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        isCloseHovering = hovering
                    }
                    // .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(
                backgroundColor
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            // Split view
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .right) } 
            label: { Label("Open in Split (Right)", systemImage: "rectangle.split.2x1") }
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .left) } 
            label: { Label("Open in Split (Left)", systemImage: "rectangle.split.2x1") }
            Divider()
            // Mute/Unmute option (show if tab has audio content OR is muted)
            if tab.hasAudioContent || tab.isAudioMuted {
                Button(action: onMute) {
                    Label(tab.isAudioMuted ? "Unmute Audio" : "Mute Audio", 
                          systemImage: tab.isAudioMuted ? "speaker.wave.2" : "speaker.slash")
                }
                
                Divider()
            }
            
            // Unload options
            Button(action: {
                browserManager.tabManager.unloadTab(tab)
            }) {
                Label("Unload Tab", systemImage: "arrow.down.circle")
            }
            .disabled(tab.isUnloaded)
            
            Button(action: {
                browserManager.tabManager.unloadAllInactiveTabs()
            }) {
                Label("Unload All Inactive Tabs", systemImage: "arrow.down.circle.fill")
            }
            
            Divider()
            
            Button(action: onClose) {
                Label("Close Tab", systemImage: "xmark.circle")
            }
        }
    }

    private var isCurrentTab: Bool {
        return browserManager.tabManager.currentTab?.id == tab.id
    }
    
    private var backgroundColor: Color {
        if isCurrentTab {
            return AppColors.activeTab.opacity(0.2)
        } else if isHovering {
            return AppColors.activeTab.opacity(0.1)
        } else {
            return Color.clear
        }
    }
    private var textTab: Color {
        if isCurrentTab {
            return Color.white
        } else {
            return Color.white
        }
    }

}
