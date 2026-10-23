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

/// Address bar below the unified navigation row. Workspace controls live in the footer.
struct SidebarHeader: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    let isSidebarHovered: Bool

    var body: some View {
        VStack(spacing: NookDesign.Spacing.sectionGap) {
            if !nookSettings.topBarAddressView {
                urlBar
            }
        }
    }

    private var urlBar: some View {
        URLBarView(isSidebarHovered: isSidebarHovered)
            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
    }
}
