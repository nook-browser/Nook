// Licensed under GPL-3.0. See LICENSE.
//
//  SyncOfferToast.swift
//  Nook
//
//  One-time offer to turn on iCloud sync after an update, shown only while an
//  iCloud account is available and sync is off.
//

import SwiftUI
import NookDesign

public struct SyncOfferToast: View {
    let onTurnOn: () -> Void
    let onDismiss: () -> Void

    public init(onTurnOn: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onTurnOn = onTurnOn
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ToastView {
            HStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "icloud")
                    .foregroundStyle(.primary)
                Text("Sync your spaces across your Macs?")
                    .font(NookDesign.Font.body)
                Button("Turn On", action: onTurnOn)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Not Now", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
