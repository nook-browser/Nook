// Licensed under GPL-3.0. See LICENSE.
//
//  Advanced.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            #if DEBUG
            Section {
                Toggle("Show Update Notification", isOn: $settings.debugToggleUpdateNotification)
            } header: {
                Text("Debug Options")
            } footer: {
                Text("Force display the sidebar update notification for appearance debugging.")
            }
            #endif
        }
        .formStyle(.grouped)
    }
}
