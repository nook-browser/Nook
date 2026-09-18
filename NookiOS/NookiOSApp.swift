// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  NookiOSApp.swift
//  NookiOS
//

import SwiftUI
import NookUI

@main
struct NookiOSApp: App {
    @StateObject private var model = BrowserModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .nookEnvironment(model)
        }
    }
}

extension View {
    /// Everything the shared rows, menus and settings bodies read. Sheets do not
    /// inherit these, so the sheet contents apply the same modifier.
    func nookEnvironment(_ model: BrowserModel) -> some View {
        self
            .environmentObject(model)
            .environment(model.tabs)
            .environment(model.window)
            .environment(model.windowRegistry)
            .environment(model.settings)
            .environment(\.nookSettings, model.settings)
            .environment(\.tabActions, model)
            .environment(\.contentBlocker, model.blocker)
            .environment(\.siteRouting, model.siteRouting)
    }
}
