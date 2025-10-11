//
//  SettingsDialog.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct SettingsDialog: DialogProtocol {
    @Binding var autoSave: Bool
    @Binding var notifications: Bool
    @Binding var theme: String
    @Binding var fontSize: Double
    let onSave: () -> Void
    let onCancel: () -> Void
    
    init(
        autoSave: Binding<Bool>,
        notifications: Binding<Bool>,
        theme: Binding<String>,
        fontSize: Binding<Double>,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._autoSave = autoSave
        self._notifications = notifications
        self._theme = theme
        self._fontSize = fontSize
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var header: AnyView {
        AnyView(
            DialogHeader(
                icon: "gear",
                title: "Settings",
                subtitle: "Customize your Nook experience"
            )
        )
    }
    
    var content: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.system(size: 14, weight: .medium))
                    Picker("Theme", selection: $theme) {
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                        Text("Auto").tag("auto")
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Font Size")
                        .font(.system(size: 14, weight: .medium))
                    HStack {
                        Slider(value: $fontSize, in: 12...20, step: 1)
                        Text("\(Int(fontSize))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-save tabs", isOn: $autoSave)
                    Toggle("Enable notifications", isOn: $notifications)
                }
            }
        )
    }
    
    var footer: AnyView {
        AnyView(
            DialogFooter(
                rightButtons: [
                    DialogButton(
                        text: "Cancel",
                        variant: .secondary,
                        action: onCancel
                    ),
                    DialogButton(
                        text: "Save Settings",
                        iconName: "checkmark",
                        variant: .primary,
                        action: onSave
                    )
                ]
            )
        )
    }
} 
