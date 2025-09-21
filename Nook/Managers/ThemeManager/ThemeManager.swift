//
//  ThemeManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 21/09/2025.
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

final class ThemeManager: ObservableObject {
    @AppStorage("appTheme") private var storedTheme: String = AppTheme.system.rawValue

    var theme: AppTheme {
        get { AppTheme(rawValue: storedTheme) ?? .system }
        set {
            storedTheme = newValue.rawValue
            applyAppearance(newValue)
            objectWillChange.send()
        }
    }

    init() {
        applyAppearance(theme)
    }

    func applyAppearance(_ theme: AppTheme) {
        switch theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
