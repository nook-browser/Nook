// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  NookSettingsEnvironment.swift
//  Nook
//
//  The SwiftUI glue NookSettings cannot carry: the settings service lives in a
//  Foundation-only package, so the environment key and the SwiftUI-typed
//  conveniences over its value types stay here.
//

import NookSettings
import SwiftUI

// MARK: - Environment Key

private struct NookSettingsServiceKey: EnvironmentKey {
    @MainActor
    static var defaultValue: NookSettingsService {
        // This should never be called since we always inject from NookApp
        // But EnvironmentKey protocol requires a default value
        return NookSettingsService()
    }
}

extension EnvironmentValues {
    var nookSettings: NookSettingsService {
        get { self[NookSettingsServiceKey.self] }
        set { self[NookSettingsServiceKey.self] = newValue }
    }
}
