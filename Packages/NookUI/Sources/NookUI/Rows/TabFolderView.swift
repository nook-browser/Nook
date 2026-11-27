// Licensed under GPL-3.0. See LICENSE.
//
//  TabFolderView.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-24.
//

import NookTabsCore
import SwiftUI
import NookDesign
import NookWeb

/// A folder header row in the sidebar outline. Its children are separate rows below it.
public struct TabFolderView: View {
    let item: Item
    let spaceID: UUID
    /// True while a drag would drop into this folder.
    var isDropTarget: Bool = false

    @State private var isHovering: Bool = false
    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool

    @Environment(BrowserWindowState.self) private var windowState
    private let renameState = SidebarRenameState.shared

    @Environment(TabsController.self) private var tabs
    private var isOpen: Bool { tabs.isOpen(folder: item.id) }
    private var isRenaming: Bool { renameState.itemID == item.id }

    public init(
        item: Item,
        spaceID: UUID,
        isDropTarget: Bool = false
    ) {
        self.item = item
        self.spaceID = spaceID
        self.isDropTarget = isDropTarget
    }

    public var body: some View {
        Button(action: {
            withAnimation(NookDesign.Motion.spring) {
                tabs.toggleFolder(item.id)
            }
        }) {
            HStack(spacing: NookDesign.Spacing.md) {
                if let liveSymbol {
                    Image(systemName: liveSymbol)
                        .font(.system(size: NookDesign.Size.spaceIcon, weight: .medium))
                        .foregroundStyle(tabs.space(spaceID)?.accentColor ?? .secondary)
                        .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                } else {
                    ArcFolderIcon(isOpen: isOpen)
                        .frame(width: NookDesign.Size.essentialsFavicon, height: NookDesign.Size.essentialsFavicon)
                }

                if isRenaming {
                    TextField("", text: $draftName)
                        .font(NookDesign.Tab.font)
                        .foregroundStyle(.primary)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocorrectionDisabled()
                        .focused($nameFieldFocused)
                        .onAppear {
                            draftName = item.displayTitle
                            DispatchQueue.main.async { nameFieldFocused = true }
                        }
                        .onSubmit { commitRename() }
                        .onEscapeKey { cancelRename() }
                } else {
                    Text(item.displayTitle)
                        .font(NookDesign.Tab.font)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: NookDesign.Spacing.xs)

                if let status = tabs.liveStatus[item.id] {
                    Image(systemName: "exclamationmark.triangle")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                        .help(liveStatusHelp(status))
                }

                if isHovering && !isRenaming {
                    Menu {
                        folderMenu
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                    }
                    .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.rowButton, radius: NookDesign.Radius.sm))
                }
            }
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Tab.height)
            .frame(maxWidth: .infinity)
            .nookTabSurface(selected: isDropTarget, hovered: isHovering)
        }
        .buttonStyle(NookTabButtonStyle())
        .padding(.vertical, NookDesign.Tab.verticalInset)
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.hover(hovering)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            folderMenu
                .environment(windowState)
                .environment(tabs)
        }
        .onChange(of: nameFieldFocused) { _, focused in
            if isRenaming && !focused { commitRename() }
        }
    }

    private var folderMenu: some View {
        FolderContextMenu(itemID: item.id, onRename: startRenaming)
    }

    // MARK: - Live

    private var liveSymbol: String? {
        switch item.live {
        case nil: return nil
        case .githubIssues?: return "smallcircle.filled.circle"
        case .githubNotifications?: return "bell"
        case .asanaTasks?: return "checkmark.circle"
        case let source?: return source.feedURL != nil ? "dot.radiowaves.up.forward" : "arrow.triangle.pull"
        }
    }

    private func liveStatusHelp(_ status: TabsController.LiveFolderStatus) -> String {
        let signedOut = status == .signedOut
        switch item.live {
        case .githubIssues?: return signedOut ? "Sign in to GitHub" : "Couldn't load issues"
        case .githubNotifications?: return signedOut ? "Sign in to GitHub" : "Couldn't load notifications"
        case .asanaTasks?: return signedOut ? "Sign in to Asana" : "Couldn't load tasks"
        case let source? where source.feedURL != nil: return "Couldn't load feed"
        default: return signedOut ? "Sign in to GitHub" : "Couldn't load pull requests"
        }
    }

    // MARK: - Rename

    private func startRenaming() {
        draftName = item.displayTitle
        renameState.itemID = item.id
    }

    private func cancelRename() {
        draftName = ""
        renameState.itemID = nil
        nameFieldFocused = false
    }

    private func commitRename() {
        guard isRenaming else { return }
        let newName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty && newName != item.displayTitle {
            tabs.rename(item.id, newName)
        }
        cancelRename()
    }
}

/// Arc-style two-tone outlined folder icon whose front flap tilts open when expanded.
private struct ArcFolderIcon: View {
    let isOpen: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let stroke = Color.primary.opacity(0.88)
        let tabFill = Color.primary.opacity(0.35)
        let interiorFill = colorScheme == .dark ? Color.black.opacity(0.65) : Color.white.opacity(0.75)

        ZStack(alignment: .bottom) {
            FolderBackShape()
                .fill(tabFill)
            FolderBackShape()
                .stroke(stroke, lineWidth: 1.45)

            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(interiorFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .stroke(stroke, lineWidth: 1.45)
                )
                .frame(height: isOpen ? 10.5 : 11.5)
                .rotation3DEffect(
                    .degrees(isOpen ? 28 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .bottom,
                    perspective: 0.6
                )
                .offset(x: isOpen ? 0.8 : 0, y: 0)
        }
        .frame(width: 18, height: 15)
        .animation(NookDesign.Motion.spring, value: isOpen)
    }
}

private struct FolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 2.5))
        p.addQuadCurve(to: CGPoint(x: 2.2, y: 0.5), control: CGPoint(x: 0, y: 0.5))
        p.addLine(to: CGPoint(x: w * 0.38, y: 0.5))
        p.addQuadCurve(to: CGPoint(x: w * 0.48, y: 1.8), control: CGPoint(x: w * 0.44, y: 0.5))
        p.addLine(to: CGPoint(x: w * 0.52, y: 2.5))
        p.addLine(to: CGPoint(x: w - 2, y: 2.5))
        p.addQuadCurve(to: CGPoint(x: w, y: 4.5), control: CGPoint(x: w, y: 2.5))
        p.addLine(to: CGPoint(x: w, y: h - 2))
        p.addQuadCurve(to: CGPoint(x: w - 2, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 2, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - 2), control: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}
