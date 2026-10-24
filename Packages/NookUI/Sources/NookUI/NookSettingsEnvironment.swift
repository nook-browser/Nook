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
    // SwiftUI evaluates defaults while resolving environment values, including
    // during updates to trees that inject the real service. Reuse one instance;
    // constructing a service here repeatedly registers and reads all settings.
    @MainActor
    static let defaultValue = NookSettingsService()
}

extension EnvironmentValues {
    public var nookSettings: NookSettingsService {
        get { self[NookSettingsServiceKey.self] }
        set { self[NookSettingsServiceKey.self] = newValue }
    }
}
