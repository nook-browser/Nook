// Licensed under GPL-3.0. See LICENSE.
//
//  NookSettingsEnvironment.swift
//  NookUI
//
//  The SwiftUI glue NookSettings cannot carry: the settings service lives in a
//  Foundation-only package, so the environment key lives here, where the shared
//  settings bodies and both platforms' app targets all reach one key.
//

import NookSettings
import SwiftUI

private struct NookSettingsServiceKey: EnvironmentKey {
    @MainActor
    static var defaultValue: NookSettingsService {
        // Never reached in either app: both targets inject the real service at
        // the root. EnvironmentKey requires a default, so this is it.
        return NookSettingsService()
    }
}

extension EnvironmentValues {
    public var nookSettings: NookSettingsService {
        get { self[NookSettingsServiceKey.self] }
        set { self[NookSettingsServiceKey.self] = newValue }
    }
}
