// Licensed under GPL-3.0. See LICENSE.
//
//  SpaceTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb

/// One tab row in the sidebar outline.
public struct SpaceTab: View {
    let item: Item
    var menuContext: TabMenuContext = .sidebar

    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @State private var draftName: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.tabActions) private var actions
    private let renameState = SidebarRenameState.shared

    @Environment(TabsController.self) private var tabs
    private var session: PageSession? { tabs.session(for: item.id) }
    private var isRenaming: Bool { renameState.itemID == item.id }
    private var isUnloaded: Bool { session?.isUnloaded ?? true }


    public init(
        item: Item,
        menuContext: TabMenuContext = .sidebar
    ) {
        self.item = item
        self.menuContext = menuContext
    }

    public var body: some View {
        let title = tabs.title(for: item)
        Button(action: {
            if isCurrentTab {
                startRename(title)
            } else {
                if isRenaming { commitRename() }
                tabs.select(item.id, in: windowState)
            }
        }) {
            HStack(spacing: NookDesign.Spacing.md) {
                ItemFavicon(item: item, session: session)
                    .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
                if let session, session.hasAudioContent || session.hasPlayingAudio || session.isAudioMuted {
                    Button(action: { session.toggleMute() }) {
                        Image(systemName: session.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(session.isAudioMuted ? "Unmute" : "Mute")
                }

                if isRenaming {
                    TextField("", text: $draftName)
                        .font(NookDesign.Font.body)
                        .foregroundStyle(isUnloaded ? .secondary : .primary)
                        .textFieldStyle(.plain)
                        .onSubmit { commitRename() }
                        .onEscapeKey { renameState.itemID = nil }
                        .focused($isTextFieldFocused)
                        .onAppear {
                            if draftName.isEmpty { draftName = title }
                            isTextFieldFocused = true
                        }
                } else {
                    // Hidden shrinkable copy sizes the row; the visible copy is laid out at
                    // full width and faded, so long titles never widen the row.
                    Text(title)
                        .font(NookDesign.Font.body)
                        .lineLimit(1)
                        .hidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) {
                            Text(title)
                                .font(NookDesign.Font.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .id(title)
                                .transition(.blurReplace)
                        }
                        // Only a rename animates; a page changing its own title swaps without motion.
                        .animation(NookDesign.Motion.spring, value: item.customTitle)
                        // On hover the text ends before the close button.
                        .nookTrailingFade(reserving: isHovering ? NookDesign.Size.row : 0)
                        .textSelection(.disabled)
                }

                if tabs.hasLeftHome(item.id) {
                    // Shows the page moved away from the pinned URL and resets to it. Shifts left
                    // while the hover close button covers the trailing edge.
                    Button { tabs.resetToHome(item.id) } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: NookDesign.Size.cornerButton, height: NookDesign.Size.cornerButton)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset to Pinned URL")
                    .padding(.trailing, isHovering ? NookDesign.Size.rowButton : 0)
                }
            }
            .overlay(alignment: .trailing) {
                if isHovering {
                    // Synced loaded tabs: "-" unloads the page; unloaded synced tabs: "x" removes the item;
                    // tabs section: "x" closes.
                    let useUnload = tabs.isSynced(item.id) && !isUnloaded
                    Button(action: {
                        if useUnload { tabs.unload(item.id) } else { tabs.remove(item.id) }
                    }) {
                        Image(systemName: useUnload ? "minus" : "xmark")
                            .font(NookDesign.Font.secondary)
                            .foregroundColor(.primary)
                            .frame(width: NookDesign.Size.rowButton, height: NookDesign.Size.rowButton)
                            .background(isCloseHovering ? NookDesign.Surface.fillPressed : Color.clear)
                            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(useUnload ? "Unload" : "Close")
                    .onHoverTracking { hovering in
                        isCloseHovering = hovering
                    }
                }
            }
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Size.row)
            .frame(minWidth: 0, maxWidth: .infinity)
            .background(backgroundColor)
            .overlay {
                if isRenaming {
                    NookDesign.Radius.shape(NookDesign.Radius.md)
                        .strokeBorder(accentColor, lineWidth: NookDesign.Size.hairlineWidth)
                }
            }
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .nookRowSelection(isCurrentTab)
            .opacity(isUnloaded ? NookDesign.Surface.unloadedOpacity : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
                isHovering = hovering
            }
            // Read by the middle-click handler in AppDelegate. Only clear the slot if
            // it still points at this row, so the enter of the next row wins the race
            // against the exit of this one.
            if hovering {
                windowState.hoveredItemID = item.id
            } else if windowState.hoveredItemID == item.id {
                windowState.hoveredItemID = nil
            }
        }
        .onChange(of: isTextFieldFocused) { _, focused in
            if isRenaming && !focused { commitRename() }
        }
        .onChange(of: isRenaming) { _, renaming in
            if renaming { draftName = title }
        }
        .contextMenu {
            TabContextMenu(itemID: item.id, context: menuContext)
                .environment(windowState)
                .environment(tabs)
                .environment(\.tabActions, actions)
        }
        .nookElevation(isCurrentTab ? .raised : .flat)
    }

    private var accentColor: Color { actions?.accentColor ?? .accentColor }

    private var isCurrentTab: Bool {
        tabs.selectedItemID(in: windowState) == item.id
    }

    private var backgroundColor: Color {
        if isCurrentTab {
            return Color.clear
        } else if isHovering {
            return NookDesign.Surface.fill
        } else {
            return Color.clear
        }
    }

    private func startRename(_ title: String) {
        draftName = title
        renameState.itemID = item.id
        isTextFieldFocused = true
    }

    /// Empty input clears the custom title.
    private func commitRename() {
        guard isRenaming else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        renameState.itemID = nil
        isTextFieldFocused = false
        if name != tabs.title(for: item) || name.isEmpty {
            tabs.rename(item.id, name.isEmpty ? nil : name)
        }
    }
}
