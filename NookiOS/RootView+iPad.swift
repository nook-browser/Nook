// Licensed under GPL-3.0. See LICENSE.
//
//  RootView+iPad.swift
//  NookiOS
//
//  The regular-width layout: the outline the phone shows in a sheet, as a
//  permanent sidebar, with the page as detail. The bar moves to the sidebar's
//  foot, because on a tablet the bottom of the screen is not where the thumb is.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookUI
import NookWeb

struct RegularRootView: View {
    @EnvironmentObject private var model: BrowserModel
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var window

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ZStack {
                    SpacesList()
                        .frame(height: NookDesign.Spacing.xl)

                    HStack {
                        Button {
                            model.present(.settings)
                        } label: {
                            Image(systemName: "gearshape")
                                .frame(width: NookDesign.Size.iconButton)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Settings")

                        Spacer()
                    }
                }
                .padding(.horizontal, NookDesign.Spacing.rowPadding)
                .padding(.vertical, NookDesign.Spacing.md)

                ScrollView {
                    if let spaceID = window.spaceID {
                        // Selecting in the sidebar dismisses nothing: the
                        // outline stays on screen.
                        LazyVStack(alignment: .leading, spacing: NookDesign.Spacing.lg) {
                            FavoritesGrid(spaceID: spaceID) {}
                            TabSheetRows(spaceID: spaceID) {}
                        }
                        .padding(.horizontal, NookDesign.Spacing.rowPadding)
                    }
                }

                BottomBar(style: .sidebar, condensed: .constant(false))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        } detail: {
            if let session = model.selectedSession {
                WebViewContainer(webView: session.activeWebView, bottomInset: 0)
                    .ignoresSafeArea()
            } else {
                EmptyWebsiteView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
