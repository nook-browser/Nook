// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
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

    var body: some View {
        Button("More", systemImage: "ellipsis") {
            windowState.isExtensionLibraryVisible.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.iconButton, radius: NookDesign.Radius.sm))
        .foregroundStyle(Color.primary)
        // The overlay in WindowView hangs off this frame.
        .anchorPreference(key: ExtensionLibraryAnchorKey.self, value: .bounds) { $0 }
    }
}
