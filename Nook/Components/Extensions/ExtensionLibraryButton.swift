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

    var body: some View {
        // Arc's site controls button; the panel springs out of it.
        Button("Site Controls", systemImage: "slider.horizontal.3") {
            withAnimation(.interpolatingSpring(Spring(response: 0.3, dampingRatio: 0.86))) {
                windowState.isExtensionLibraryVisible.toggle()
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.iconButton, radius: NookDesign.Radius.sm))
        .foregroundStyle(Color.primary)
        // The overlay in WindowView hangs off this frame.
        .anchorPreference(key: ExtensionLibraryAnchorKey.self, value: .bounds) { $0 }
    }
}
