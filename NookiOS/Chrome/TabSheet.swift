// Licensed under GPL-3.0. See LICENSE.
//
//  TabSheet.swift
//  NookiOS
//
//  The phone's tab surface: the macOS sidebar outline at phone width. It opens
//  medium, so the page stays visible behind it and the rows sit in thumb reach,
//  and pulls up to large for the whole outline.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookUI
import NookWeb

struct TabSheet: View {
    @EnvironmentObject private var model: BrowserModel
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var window
    @Environment(\.dismiss) private var dismiss

    @State private var detent: PresentationDetent = .medium
    @State private var showSettings = false

    private var spaceID: UUID? { window.spaceID }

    var body: some View {
        ScrollView {
            if let spaceID {
                LazyVStack(alignment: .leading, spacing: NookDesign.Spacing.lg) {
                    FavoritesGrid(spaceID: spaceID) { dismiss() }
                    TabSheetRows(spaceID: spaceID) { dismiss() }
                }
                .padding(NookDesign.Spacing.rowPadding)
            }
        }
        .safeAreaInset(edge: .top) {
            header
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // The default sheet material lets the page bleed through the rows at the
        // medium detent, where there is something behind to read.
        .presentationBackground(NookDesign.Surface.windowBackground)
        // Settings comes up over the sheet rather than replacing it, so closing
        // it puts you back in the outline.
        .sheet(isPresented: $showSettings) {
            SettingsSheet().nookEnvironment(model)
        }
    }

    private var header: some View {
        ZStack {
            // Centred regardless of the buttons flanking it.
            SpacesList()
                .frame(height: NookDesign.Spacing.xl)

            HStack {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: NookDesign.Size.iconButton)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Settings")

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: NookDesign.Size.iconButton)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        // Clears the sheet's own drag indicator, which draws at the same top edge.
        .padding(.top, NookDesign.Spacing.xxl)
        .padding(.bottom, NookDesign.Spacing.md)
        .background(.bar)
    }
}
