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
    var onUnload: (() -> Void)? = nil
    var onMute: () -> Void
    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @FocusState private var isTextFieldFocused: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var tabManager: TabManager
    @Environment(BrowserWindowState.self) private var windowState

    /// Fades the trailing edge of the title instead of truncating with an ellipsis.
    /// On hover the clear region grows so the text ends before the close button.
    private var titleFade: some View {
        HStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: NookDesign.Spacing.titleFade)
            Color.clear
                .frame(width: isHovering ? NookDesign.Size.row : 0)
        }
    }

    var body: some View {
        Button(action: {
            if isCurrentTab {
                tab.startRenaming()
                isTextFieldFocused = true
            } else {
                if tab.isRenaming {
                    tab.saveRename()
                }
                action()
            }
        }) {
            HStack(spacing: NookDesign.Spacing.md) {
                tab.favicon
                    .resizable()
                    .scaledToFit()
                    .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
                if tab.hasAudioContent || tab.hasPlayingAudio || tab.isAudioMuted {
                    Button(action: onMute) {
                        Image(systemName: tab.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(tab.isAudioMuted ? "Unmute" : "Mute")
                }
                
                if tab.isRenaming {
                    TextField("", text: $tab.editingName)
                        .font(NookDesign.Font.body)
                        .foregroundStyle(tab.isUnloaded ? AppColors.textSecondary : textTab)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            tab.saveRename()
                        }
                        .onExitCommand {
                            tab.cancelRename()
                        }
                        .focused($isTextFieldFocused)
                        .onAppear {
                            isTextFieldFocused = true
                        }
                } else {
                    // Hidden shrinkable copy sizes the row; the visible copy is laid out at
                    // full width and faded, so long titles never widen the row.
                    Text(tab.displayName)
                        .font(NookDesign.Font.body)
                        .lineLimit(1)
                        .hidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) {
                            Text(tab.displayName)
                                .font(NookDesign.Font.body)
                                .foregroundStyle(textTab)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .mask(titleFade)
                        .textSelection(.disabled) // Make text non-selectable
                }
            }
            .overlay(alignment: .trailing) {
                if isHovering {
                    // Space-pinned loaded tabs: show "-" to unload; unloaded: show "x" to remove
                    let useUnload = onUnload != nil && !tab.isUnloaded
                    Button(action: useUnload ? onUnload! : onClose) {
                        Image(systemName: useUnload ? "minus" : "xmark")
                            .font(NookDesign.Font.secondary)
                            .foregroundColor(textTab)
                            .frame(width: NookDesign.Size.rowButton, height: NookDesign.Size.rowButton)
                            .background(isCloseHovering ? NookDesign.Surface.fillPressed : Color.clear)
                            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHoverTracking { hovering in
                        isCloseHovering = hovering
                    }
                }
            }
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Size.row)
            .frame(minWidth: NookDesign.Spacing.zero, maxWidth: .infinity)
            .background(
                backgroundColor
            )
            .overlay {
                if tab.isRenaming {
                    NookDesign.Radius.shape(NookDesign.Radius.md)
                        .strokeBorder(browserManager.gradientColorManager.accentColor, lineWidth: 1)
                } else if isCurrentTab {
                    NookDesign.Radius.shape(NookDesign.Radius.md)
                        .strokeBorder(NookDesign.Surface.hairline, lineWidth: 1)
                }
            }
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .opacity(tab.isUnloaded ? NookDesign.Surface.unloadedOpacity : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
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
        .nookElevation(isActive ? .raised : .flat)
        .onAppear {
            tab.ensureFaviconLoaded()
        }
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
        let folders = tabManager.folders(for: spaceId)

        if !folders.isEmpty {
            Menu {
                ForEach(folders, id: \.id) { folder in
                    Button {
                        tabManager.moveTabToRegularFolder(tab: tab, folderId: folder.id)
                    } label: {
                        Label(folder.name, systemImage: "folder.fill")
                    }
                }
            } label: {
                Label("Add to Folder", systemImage: "folder.badge.plus")
            }
        }

        if !tab.isPinned && !tab.isSpacePinned {
            Button {
                tabManager.pinTab(tab)
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
            let picker = NSSharingServicePicker(items: [tab.url as NSURL])
            if let window = NSApp.keyWindow {
                let origin = NSPoint(x: window.frame.midX, y: window.frame.midY)
                picker.show(relativeTo: .zero, of: window.contentView ?? NSView(), preferredEdge: .minY)
                _ = origin
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Button {
            tab.startRenaming()
            isTextFieldFocused = true
        } label: {
            Label("Rename", systemImage: "character.cursor.ibeam")
        }

        if tab.displayNameOverride != nil {
            Button {
                tab.displayNameOverride = nil
            } label: {
                Label("Reset Tab Name", systemImage: "arrow.uturn.backward")
            }
        }

        if (tab.isPinned || tab.isSpacePinned), tab.hasNavigatedAwayFromPinnedURL {
            Button {
                tab.resetToPinnedURL()
            } label: {
                Label("Reset to Pinned URL", systemImage: "arrow.uturn.backward.circle")
            }
        }

        if (tab.isPinned || tab.isSpacePinned), tab.pinnedURL != nil {
            Button {
                browserManager.dialogManager.showDialog(
                    EditPinnedURLDialog(
                        tab: tab,
                        onSave: { newURL in
                            tab.pinnedURL = newURL
                            tab.loadURL(newURL)
                            browserManager.dialogManager.closeDialog()
                            tabManager.debouncedPersistSnapshot()
                        },
                        onCancel: {
                            browserManager.dialogManager.closeDialog()
                        }
                    )
                )
            } label: {
                Label("Edit Pinned URL", systemImage: "pencil.circle")
            }
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
        let spaces = tabManager.spaces
        Menu {
            ForEach(spaces, id: \.id) { space in
                Button {
                    tabManager.moveTab(tab.id, to: space.id)
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
        if space.icon.isEmojiIcon {
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
                tabManager.closeAllTabsBelow(tab)
            } label: {
                Label("Close All Below", systemImage: "arrow.down.to.line")
            }
        }

        let hasOtherTabs = (tabManager.tabsBySpace[tab.spaceId ?? UUID()]?.filter { $0.id != tab.id }.isEmpty == false)
        if hasOtherTabs && !tab.isPinned && !tab.isSpacePinned {
            Button {
                tabManager.closeOtherTabs(tab)
            } label: {
                Label("Close Others", systemImage: "xmark.circle")
            }
        }

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
    private var backgroundColor: Color {
        if isCurrentTab {
            return NookDesign.Surface.raised
        } else if isHovering {
            return NookDesign.Surface.fill
        } else {
            return Color.clear
        }
    }
    private var textTab: Color {
        .primary
    }

}
