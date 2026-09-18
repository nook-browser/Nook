// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  NookiOSApp.swift
//  NookiOS
//

import SwiftUI

@main
struct NookiOSApp: App {
    @StateObject private var model = BrowserModel()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
    }
}
