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
    @FocusState private var isTextFieldFocused: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState

    var body: some View {
        Button(action: {
            if isCurrentTab {
                // Only allow renaming if this tab is the current tab in THIS window
                print("🔄 [SpaceTab] Starting rename for tab '\(tab.name)' in window \(windowState.id)")
                tab.startRenaming()
                isTextFieldFocused = true
            } else {
                // For inactive tabs, end any active renaming and switch
                if tab.isRenaming {
                    tab.saveRename()
                }
                action()
            }
        }) {
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
                if tab.isRenaming {
                    TextField("", text: $tab.editingName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tab.isUnloaded ? AppColors.textSecondary : textTab)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            tab.saveRename()
                        }
                        .onExitCommand {
                            tab.cancelRename()
                        }
                        .onAppear {
                            // Select all text when editing starts
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                // Use a more reliable approach to select all text
                                if let textField = NSApp.keyWindow?.firstResponder as? NSTextView {
                                    textField.selectAll(nil)
                                }
                            }
                        }
                        .focused($isTextFieldFocused)
                } else {
                    Text(tab.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tab.isUnloaded ? AppColors.textSecondary : textTab)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.disabled) // Make text non-selectable
                }
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
        .background(
            // Invisible overlay to capture clicks outside when renaming
            Group {
                if tab.isRenaming {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            tab.saveRename()
                        }
                }
            }
        )
        .contextMenu {
            // Split view
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState) }
                label: { Label("Open in Split (Right)", systemImage: "rectangle.split.2x1") }
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState) }
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

    private var isActive: Bool {
        return browserManager.currentTab(for: windowState)?.id == tab.id
    }

    private var isCurrentTab: Bool {
        return browserManager.currentTab(for: windowState)?.id == tab.id
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
