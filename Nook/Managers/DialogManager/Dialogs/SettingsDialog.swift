//
//  SettingsDialog.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct SettingsDialog: View {
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

    var body: some View {
        StandardDialog(
            header: { header },
            content: { content },
            footer: { footer }
        )
    }

    @ViewBuilder
    private var header: some View {
        DialogHeader(
            icon: "gear",
            title: "Settings",
            subtitle: "Customize your Nook experience"
        )
    }

    @ViewBuilder
    private var content: some View {
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
    }

    @ViewBuilder
    private var footer: some View {
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
