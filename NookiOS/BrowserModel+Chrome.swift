// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserModel+Chrome.swift
//  NookiOS
//
//  Which sheet and which dialog the chrome is showing. The Mac routes these
//  through DialogManager and a settings window; the phone has one scene, so a
//  sheet and a dialog are each a single optional on the model.
//

import Foundation

/// A destination inside the settings sheet, so `openSpaceSettings()` can land on
/// Spaces rather than the sheet's root list.
enum SettingsRoute: String, Hashable, Identifiable {
    case general
    case appearance
    case spaces
    case adBlocker
    case airTrafficControl
    case youTube
    case socialMedia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .spaces: "Spaces"
        case .adBlocker: "Ad Blocker"
        case .airTrafficControl: "Air Traffic Control"
        case .youTube: "YouTube"
        case .socialMedia: "Social Media"
        }
    }
}

enum ChromeSheet: String, Identifiable {
    case tabs
    case settings

    var id: String { rawValue }
}

enum ChromeDialog: Identifiable {
    case editPinnedURL(url: URL, title: String, onSave: (URL) -> Void)
    case createSpace(onCreate: (String, String) -> Void)
    case deleteSpace(name: String, tabCount: Int, isLast: Bool, onDelete: () -> Void)

    var id: String {
        switch self {
        case .editPinnedURL: "editPinnedURL"
        case .createSpace: "createSpace"
        case .deleteSpace: "deleteSpace"
        }
    }
}

extension BrowserModel {
    func present(_ sheet: ChromeSheet) {
        self.sheet = sheet
    }

    func present(_ dialog: ChromeDialog) {
        self.dialog = dialog
    }

    func dismissDialog() {
        dialog = nil
    }

    /// Hands-off checks cannot tap the tabs button, so a Debug launch argument
    /// opens a sheet for screenshotting, optionally on one settings row:
    /// `-NookOpenSheet tabs`, or `-NookOpenSheet settings -NookSettingsRoute adBlocker`.
    func openDebugSheetIfRequested() {
        #if DEBUG
        guard let name = UserDefaults.standard.string(forKey: "NookOpenSheet"),
              let requested = ChromeSheet(rawValue: name) else { return }
        if let route = UserDefaults.standard.string(forKey: "NookSettingsRoute"),
           let destination = SettingsRoute(rawValue: route) {
            settingsPath = [destination]
        }
        present(requested)
        #endif
    }
}
