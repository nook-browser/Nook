//
//  SpaceTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import NookTabsCore
import SwiftUI
import NookDesign

/// One tab row in the sidebar outline.
struct SpaceTab: View {
    let item: Item
    var menuContext: TabMenuContext = .sidebar

    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @State private var draftName: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    private let renameState = SidebarRenameState.shared

    private var tabs: TabsController { browserManager.tabs }
    private var session: PageSession? { tabs.session(for: item.id) }
    private var isRenaming: Bool { renameState.itemID == item.id }
    private var isUnloaded: Bool { session?.isUnloaded ?? true }

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
                        .onExitCommand { renameState.itemID = nil }
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
                        }
                        .mask(titleFade)
                        .textSelection(.disabled)
                }

                if tabs.hasLeftHome(item.id) {
                    // Shows the page moved away from the pinned URL and resets to it. Shifts left
                    // while the hover close button covers the trailing edge.
                    Button { tabs.resetToHome(item.id) } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(NookDesign.Font.secondary)
                            .foregroundStyle(.tertiary)
                            .frame(width: NookDesign.Size.rowButton, height: NookDesign.Size.rowButton)
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
                        .strokeBorder(browserManager.gradientColorManager.accentColor, lineWidth: NookDesign.Size.hairlineWidth)
                } else if isCurrentTab {
                    NookDesign.Radius.shape(NookDesign.Radius.md)
                        .strokeBorder(NookDesign.Surface.hairline, lineWidth: NookDesign.Size.hairlineWidth)
                }
            }
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .opacity(isUnloaded ? NookDesign.Surface.unloadedOpacity : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
                isHovering = hovering
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
                .environmentObject(browserManager)
                .environment(windowState)
        }
        .nookElevation(isCurrentTab ? .raised : .flat)
    }

    private var isCurrentTab: Bool {
        tabs.selectedItemID(in: windowState) == item.id
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
