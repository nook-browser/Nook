// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SettingsDialog.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI
import NookDesign

struct SettingsDialog: DialogPresentable {
    @State private var autoSave: Bool
    @State private var notifications: Bool
    @State private var theme: String
    @State private var fontSize: Double

    let onSave: (Bool, Bool, String, Double) -> Void
    let onCancel: () -> Void

    init(
        autoSave: Bool,
        notifications: Bool,
        theme: String,
        fontSize: Double,
        onSave: @escaping (Bool, Bool, String, Double) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _autoSave = State(initialValue: autoSave)
        _notifications = State(initialValue: notifications)
        _theme = State(initialValue: theme)
        _fontSize = State(initialValue: fontSize)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "gear",
            title: "Settings",
            subtitle: "Customize your Nook experience"
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme")
                    .font(NookDesign.Font.body)
                Picker("Theme", selection: $theme) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Auto").tag("auto")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Font Size")
                    .font(NookDesign.Font.body)
                HStack {
                    Slider(value: $fontSize, in: 12...20, step: 1)
                    Text("\(Int(fontSize))")
                        .font(NookDesign.Font.secondary)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-save tabs", isOn: $autoSave)
                Toggle("Enable notifications", isOn: $notifications)
            }
        }
    }

    func dialogFooter() -> DialogFooter {
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
                    action: {
                        onSave(autoSave, notifications, theme, fontSize)
                    }
                )
            ]
        )
    }
}
