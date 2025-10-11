//
//  SpaceTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct SpaceTab: View {
    var tab: Tab
    var action: () -> Void
    var onClose: () -> Void
    var onMute: () -> Void
    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @State private var isSpeakerHovering: Bool = false
    @FocusState private var isTextFieldFocused: Bool
    @Environment(BrowserManager.self) private var browserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        @Bindable var tab = tab
        Button(action: {
            if isCurrentTab {
                print("🔄 [SpaceTab] Starting rename for tab '\(tab.name)' in window \(windowState.id)")
                tab.startRenaming()
                isTextFieldFocused = true
            } else {
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
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                
                if tab.isRenaming {
                    TextField("", text: $tab.editingName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tab.isUnloaded ? AppColors.textSecondary : textTab)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            tab.saveRename()
                        }
                        .onExitCommand {
                            tab.cancelRename()
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                if let textField = NSApp.keyWindow?.firstResponder as? NSTextView {
                                    textField.selectAll(nil)
                                }
                            }
                        }
                        .focused($isTextFieldFocused)
                } else {
                    Text(tab.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textTab)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.disabled) // Make text non-selectable
                }
                Spacer()



                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(textTab)
                            .frame(width: 24,height: 24)
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
            .frame(height: 36)
            .frame(minWidth: 0, maxWidth: .infinity)
            .background(
                backgroundColor
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.05)) {
                isHovering = hovering
            }
        }
        .background(
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
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState) }
            label: { Label("Open in Split (Right)", systemImage: "rectangle.split.2x1") }
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState) }
            label: { Label("Open in Split (Left)", systemImage: "rectangle.split.2x1") }
            
            Button { browserManager.duplicateCurrentTab() }
            label: { Label("Duplicate Tab", systemImage: "doc.on.doc") }
            
            Divider()
            if !tab.isPinned && !tab.isSpacePinned {
                Button(action: {
                    browserManager.tabManager.pinTab(tab)
                }) {
                    Label("Pin to Favorites", systemImage: "pin")
                }
                Divider()
            }
            if tab.hasAudioContent || tab.isAudioMuted {
                Button(action: onMute) {
                    Label(tab.isAudioMuted ? "Unmute Audio" : "Mute Audio",
                          systemImage: tab.isAudioMuted ? "speaker.wave.2" : "speaker.slash")
                }

                Divider()
            }
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

            if !tab.isPinned && !tab.isSpacePinned && tab.spaceId != nil {
                Button(action: {
                    browserManager.tabManager.closeAllTabsBelow(tab)
                }) {
                    Label("Close All Tabs Below", systemImage: "xmark.square.fill")
                }
                .help("Close all tabs that appear below this one in the sidebar")

                Divider()
            }

            Button(action: onClose) {
                Label("Close Tab", systemImage: "xmark.circle")
            }
        }
        .shadow(color: isActive ? shadowColor : Color.clear, radius: isActive ? 1 : 0, y: 2)
    }

    private var isActive: Bool {
        return browserManager.currentTab(for: windowState)?.id == tab.id
    }
    
    private var isCurrentTab: Bool {
        return browserManager.currentTab(for: windowState)?.id == tab.id
    }
    private var shadowColor: Color {
        return colorScheme == .dark ? Color.clear : Color.black.opacity(0.15)
    }

    private var backgroundColor: Color {
        if isCurrentTab {
            return colorScheme == .dark ? AppColors.spaceTabActiveLight : AppColors.spaceTabActiveDark
        } else if isHovering {
            return colorScheme == .dark ? AppColors.spaceTabHoverLight : AppColors.spaceTabHoverDark
        } else {
            return Color.clear
        }
    }
    private var textTab: Color {
        return colorScheme == .dark ? AppColors.spaceTabTextLight : AppColors.spaceTabTextDark
    }

}
