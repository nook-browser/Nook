//
//  OAuthAssistBanner.swift
//  Nook
//
//  Lightweight banner to help users allow cross-site tracking for OAuth flows.
//

import SwiftUI

struct OAuthAssistBanner: View {
    @EnvironmentObject var browserManager: BrowserManager

    let host: String

    var body: some View {
        ToastView {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign-in may be blocked")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Allow cross-site for \(host)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
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
        }
        .transition(.toast)
    }
}

