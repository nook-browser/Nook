//
//  OAuthAssistBanner.swift
//  Pulse
//
//  Lightweight banner to help users allow cross-site tracking for OAuth flows.
//

import SwiftUI

struct OAuthAssistBanner: View {
    @EnvironmentObject var browserManager: BrowserManager

    let host: String

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign-in may be blocked")
                    .font(.system(size: 12, weight: .semibold))
                Text("Allow cross-site for \(host)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Button("Allow 15m") {
                browserManager.oauthAssistAllowForThisTab()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Button("Always allow") {
                browserManager.oauthAssistAlwaysAllowDomain()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button(action: { browserManager.hideOAuthAssist() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .padding(12)
        .background(Color(hex: "3E4D2E"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 2)
        }
        .transition(.scale(scale: 0.0, anchor: .top))
    }
}

