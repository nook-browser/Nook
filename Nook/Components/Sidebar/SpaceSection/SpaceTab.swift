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
    var menuContext: TabMenuContext = .regular
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
            TabContextMenu(tab: tab, context: menuContext)
        }
        .nookElevation(isActive ? .raised : .flat)
        .onAppear {
            tab.ensureFaviconLoaded()
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
