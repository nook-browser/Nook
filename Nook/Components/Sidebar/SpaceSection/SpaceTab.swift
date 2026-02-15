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
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
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
                        .frame(width: 18, height: 18)
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
                if tab.hasAudioContent || tab.hasPlayingAudio || tab.isAudioMuted {
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
            Options()
        }
        .shadow(color: isActive ? shadowColor : Color.clear, radius: isActive ? 2 : 0, y: 1.5)
    }
    
    @ViewBuilder
    func Options() -> some View {
        Group {
            addToMenuSection
            Divider()
            editMenuSection
            Divider()
            actionsMenuSection
            Divider()
            closeMenuSection
        }
    }

    @ViewBuilder
    private var addToMenuSection: some View {
        let spaceId = tab.spaceId ?? UUID()
        let folders = browserManager.tabManager.folders(for: spaceId)

        Menu {
            ForEach(folders, id: \.id) { folder in
                Button {
                    // TODO: Add tab to folder
                } label: {
                    Label(folder.name, systemImage: "folder.fill")
                }
            }
        } label: {
            Label("Add to Folder", systemImage: "folder.badge.plus")
        }

        if !tab.isPinned && !tab.isSpacePinned {
            Button {
                browserManager.tabManager.pinTab(tab)
            } label: {
                Label("Add to Favorites", systemImage: "star.fill")
            }
        }
    }

    @ViewBuilder
    private var editMenuSection: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tab.url.absoluteString, forType: .string)
        } label: {
            Label("Copy Link", systemImage: "link")
        }

        Button {
            // TODO: Implement share
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(true)

        Button {
            tab.startRenaming()
            isTextFieldFocused = true
        } label: {
            Label("Rename", systemImage: "character.cursor.ibeam")
        }
    }

    @ViewBuilder
    private var actionsMenuSection: some View {
        splitMenu
        duplicateButton
        moveToSpaceMenu
    }

    @ViewBuilder
    private var splitMenu: some View {
        Menu {
            Button {
                browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState)
            } label: {
                Label("Right", systemImage: "rectangle.righthalf.filled")
            }

            Button {
                browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState)
            } label: {
                Label("Left", systemImage: "rectangle.lefthalf.filled")
            }
        } label: {
            Label("Open in Split", systemImage: "rectangle.split.2x1")
        }
    }

    @ViewBuilder
    private var duplicateButton: some View {
        Button {
            browserManager.duplicateCurrentTab()
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
    }

    @ViewBuilder
    private var moveToSpaceMenu: some View {
        let spaces = browserManager.tabManager.spaces
        Menu {
            ForEach(spaces, id: \.id) { space in
                Button {
                    browserManager.tabManager.moveTab(tab.id, to: space.id)
                } label: {
                    spaceLabel(for: space)
                }
                .disabled(space.id == tab.spaceId)
            }
        } label: {
            Label("Move to Space", systemImage: "square.grid.2x2")
        }
    }

    @ViewBuilder
    private func spaceLabel(for space: Space) -> some View {
        if space.icon.unicodeScalars.first?.properties.isEmoji == true {
            Label {
                Text(space.name)
            } icon: {
                Text(space.icon)
            }
        } else {
            Label(space.name, systemImage: space.icon)
        }
    }

    @ViewBuilder
    private var closeMenuSection: some View {
        if !tab.isPinned && !tab.isSpacePinned && tab.spaceId != nil {
            Button {
                browserManager.tabManager.closeAllTabsBelow(tab)
            } label: {
                Label("Close All Below", systemImage: "arrow.down.to.line")
            }
        }

        Button {
            // TODO: Implement close all except this
        } label: {
            Label("Close Others", systemImage: "xmark.circle")
        }
        .disabled(true)

        Button(role: .destructive) {
            onClose()
        } label: {
            Label("Close", systemImage: "xmark")
        }
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
