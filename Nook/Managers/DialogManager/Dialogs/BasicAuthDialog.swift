//
//  BasicAuthDialog.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-06.
//

import SwiftUI
import Observation

@Observable
final class BasicAuthDialogModel {
    var username: String
    var password: String
    var rememberCredential: Bool
    let host: String

    init(host: String, username: String = "", password: String = "", rememberCredential: Bool = false) {
        self.host = host
        self.username = username
        self.password = password
        self.rememberCredential = rememberCredential
    }
}

struct BasicAuthDialog: DialogProtocol {
    @Bindable var model: BasicAuthDialogModel
    let onSubmit: (String, String, Bool) -> Void
    let onCancel: () -> Void

    init(model: BasicAuthDialogModel, onSubmit: @escaping (String, String, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.model = model
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    @ViewBuilder
    func header() -> some View {
        DialogHeader(
            icon: "lock.circle",
            title: "Authentication Required",
            subtitle: "The server \(model.host) is requesting credentials."
        )
    }

    @ViewBuilder
    func content() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("User name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                NookTextField(
                    text: $model.username,
                    placeholder: "Enter user name",
                    iconName: "person"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                SecureField("Enter password", text: $model.password)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Toggle(isOn: $model.rememberCredential) {
                Text("Remember for this site")
            }
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    func footer() -> some View {
        HStack(spacing: 12) {
            Spacer()
            NookButton.createButton(
                text: "Cancel",
                variant: .secondary,
                action: onCancel,
                keyboardShortcut: .escape
            )
            NookButton(
                text: "Sign In",
                iconName: "arrow.right.circle",
                variant: .primary,
                action: {
                    onSubmit(model.username, model.password, model.rememberCredential)
                },
                keyboardShortcut: .return
            )
            .disabled(model.username.isEmpty || model.password.isEmpty)
        }
        .padding(.top, 8)
    }
}
