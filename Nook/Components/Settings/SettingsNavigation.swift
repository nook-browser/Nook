// Licensed under GPL-3.0. See LICENSE.

import Observation

/// Selection for one browser window's Settings panel.
@MainActor @Observable
final class SettingsNavigation {
    var currentSettingsTab: SettingsTabs

    init(initialTab: SettingsTabs) {
        currentSettingsTab = initialTab
    }
}
