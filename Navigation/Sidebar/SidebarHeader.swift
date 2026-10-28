// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarHeader.swift
//  Nook
//
//  Created by Aether on 15/11/2025.
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

/// Header section of the sidebar: the URL bar. Back, forward and reload sit in the title row
/// above it; the space name sits under the favorites.
struct SidebarHeader: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    let isSidebarHovered: Bool

    var body: some View {
        if !nookSettings.topBarAddressView {
            URLBarView(isSidebarHovered: isSidebarHovered)
                .padding(.horizontal, NookDesign.Spacing.sidebarInset)
        }
    }
}
