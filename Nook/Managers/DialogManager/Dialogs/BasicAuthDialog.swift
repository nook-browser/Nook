// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  BasicAuthDialog.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-06.
//

import SwiftUI
import NookDesign
import Observation

@Observable
final class BasicAuthDialogModel {
    var username: String
    var password: String
    var rememberCredential: Bool
    /// `scheme://host:port` of whoever is asking.
    let origin: String
    /// Text chosen by the server; shown labelled as such, never as the site's identity.
    let realm: String
    let isProxy: Bool
    /// The password would cross the network in cleartext.
    let isInsecure: Bool
    /// False where nothing is saved: private windows and proxies.
    let canRemember: Bool

    init(
        origin: String,
        realm: String = "",
        isProxy: Bool = false,
        isInsecure: Bool = false,
        canRemember: Bool = true,
        username: String = "",
        password: String = "",
        rememberCredential: Bool = false
    ) {
        self.origin = origin
        self.realm = realm
        self.isProxy = isProxy
        self.isInsecure = isInsecure
        self.canRemember = canRemember
        self.username = username
        self.password = password
        self.rememberCredential = rememberCredential
    }
}

struct BasicAuthDialog: DialogPresentable {
    @Bindable var model: BasicAuthDialogModel
    let onSubmit: (String, String, Bool) -> Void
    let onCancel: () -> Void

    init(
        model: BasicAuthDialogModel,
        onSubmit: @escaping (String, String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.model = model
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "lock.circle",
            title: "Authentication Required",
            subtitle: "The \(model.isProxy ? "proxy" : "server") \(model.origin) is requesting credentials."
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.realm.isEmpty || model.isInsecure {
                VStack(alignment: .leading, spacing: NookDesign.Spacing.sm) {
                    if !model.realm.isEmpty {
                        // verbatim: the realm must not be parsed as Markdown (links).
                        Text(verbatim: "The site says: \u{201C}\(model.realm)\u{201D}")
                            .foregroundStyle(.secondary)
                    }
                    if model.isInsecure {
                        Label("Your password will be sent unencrypted.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(NookDesign.Font.caption)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("User name")
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.primary)
                NookTextField(
                    text: $model.username,
                    placeholder: "Enter user name",
                    iconName: "person"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.primary)
                SecureField("Enter password", text: $model.password)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
            }

            if model.canRemember {
                Toggle(isOn: $model.rememberCredential) {
                    Text("Remember for this site")
                }
                .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 4)
    }

    func dialogFooter() -> DialogFooter {
        let canSubmit = !model.username.isEmpty && !model.password.isEmpty

        return DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    keyboardShortcut: .escape,
                    action: onCancel
                ),
                DialogButton(
                    text: "Sign In",
                    iconName: "arrow.right.circle",
                    variant: .primary,
                    keyboardShortcut: .return,
                    isEnabled: canSubmit,
                    action: {
                        onSubmit(model.username, model.password, model.rememberCredential)
                    }
                )
            ]
        )
    }
}

