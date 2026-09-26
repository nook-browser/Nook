// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionLibraryButton.swift
//  Nook
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

struct ExtensionLibraryButton: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isShowingMoreMenu = false
    /// The popover's own dismissal fires for the same click that hits this button, so a
    /// plain toggle would dismiss and immediately reopen. The dismissal stamps this; the
    /// action ignores one click that just closed the library.
    @State private var lastDismissal: Date?

    var body: some View {
        Button("More", systemImage: "ellipsis") {
            if let lastDismissal, Date().timeIntervalSince(lastDismissal) < 0.3 {
                self.lastDismissal = nil
                return
            }
            windowState.isExtensionLibraryVisible.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.iconButton, radius: NookDesign.Radius.sm))
        .foregroundStyle(Color.primary)
        .popover(isPresented: Binding(
            get: { windowState.isExtensionLibraryVisible },
            set: { isPresented in
                if !isPresented {
                    lastDismissal = Date()
                    isShowingMoreMenu = false
                }
                windowState.isExtensionLibraryVisible = isPresented
            }
        ), arrowEdge: .top) {
            if let settings = browserManager.nookSettings {
                HStack(alignment: .top, spacing: 6) {
                    ExtensionLibraryView(
                        browserManager: browserManager,
                        windowState: windowState,
                        settings: settings,
                        onDismiss: dismissPopover,
                        onShowMoreMenu: { isShowingMoreMenu.toggle() }
                    )

                    if isShowingMoreMenu {
                        MoreMenuView(
                            browserManager: browserManager,
                            windowState: windowState,
                            onDismiss: { isShowingMoreMenu = false }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                    }
                }
                .fixedSize()
                .animation(NookDesign.Motion.quick, value: isShowingMoreMenu)
            }
        }
        .onChange(of: windowState.selectedItemID) { _, _ in dismissPopover() }
    }

    private func dismissPopover() {
        windowState.isExtensionLibraryVisible = false
        isShowingMoreMenu = false
    }
}
