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
    @State private var isSpeakerHovering: Bool = false
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    tab.favicon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tab.isUnloaded ? AppColors.textSecondary : textTab)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()

                // Mute button (show when tab has audio content OR is muted)
                if tab.hasAudioContent || tab.isAudioMuted {
                    Button(action: {
                        onMute()
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSpeakerHovering ? (isCurrentTab ? AppColors.controlBackgroundHoverLight : AppColors.controlBackgroundActive) : AppColors.controlBackgroundHoverLight.opacity(0))
                                .frame(width: 22, height: 22)
                                .animation(.easeInOut(duration: 0.05), value: isSpeakerHovering)
                            Image(systemName: tab.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .contentTransition(.symbolEffect(.replace))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(tab.isAudioMuted ? AppColors.textSecondary : textTab)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        isSpeakerHovering = hovering
                    }
                    .help(tab.isAudioMuted ? "Unmute Audio" : "Mute Audio")
                }

                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(textTab)
                            .padding(4)
                            .background(isCloseHovering ? (isCurrentTab ? AppColors.controlBackgroundHoverLight : AppColors.controlBackgroundActive) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        isCloseHovering = hovering
                    }
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
            withAnimation(.easeInOut(duration: 0.05)) {
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
        .shadow(color: tab.isActiveInSpace ? Color.gray : Color.clear, radius: tab.isActiveInSpace ? 1 : 0, y: 1)
    }

    private var isCurrentTab: Bool {
        return browserManager.tabManager.currentTab?.id == tab.id
    }
    
    private var backgroundColor: Color {
        if isCurrentTab {
            return AppColors.activeTab
        } else if isHovering {
            return AppColors.controlBackgroundHover
        } else {
            return Color.clear
        }
    }
    private var textTab: Color {
        if isCurrentTab {
            return Color.black
        } else {
            return AppColors.textSecondary
        }
    }

}
