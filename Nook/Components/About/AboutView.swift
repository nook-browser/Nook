// Licensed under GPL-3.0. See LICENSE.

import AppKit
import SwiftUI
import NookDesign
import NookUI

struct AboutView: View {
    static let presentationKey = "about"

    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(\.isEnabled) private var isEnabled

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    var body: some View {
        NookPanel(maxWidth: 420, padding: 0) {
            VStack(spacing: NookDesign.Spacing.md) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)

                Text("Nook")
                    .font(NookDesign.Font.display)

                Text(build.map { "Version \(version) (\($0))" } ?? "Version \(version)")
                    .font(NookDesign.Font.bodyRegular)
                    .foregroundStyle(.secondary)

                if let url = URL(string: "https://github.com/nook-browser/Nook") {
                    Link("View on GitHub", destination: url)
                        .font(NookDesign.Font.body)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(NookDesign.Spacing.xxxl)
            .padding(.top, NookDesign.Spacing.xxxl)
            .overlay(alignment: .topTrailing) {
                Button {
                    browserManager.dialogManager.closeDialog()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close About Nook")
                .padding(NookDesign.Spacing.md)
            }
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand {
            if isEnabled {
                browserManager.dialogManager.closeDialog()
            }
        }
    }
}
