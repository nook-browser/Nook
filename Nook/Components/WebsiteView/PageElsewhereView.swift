//
//  PageElsewhereView.swift
//  Nook
//
//  Shown in place of a page whose live view another window holds.
//

import AppKit
import SwiftUI

struct PageElsewhereView: View {
    let title: String
    let onShowHere: () -> Void
    let onGoToWindow: () -> Void

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(NookDesign.Font.display)
                    .foregroundStyle(.tertiary)
                Text("Open in another window")
                    .font(NookDesign.Font.title)
                    .foregroundStyle(.secondary)
                if !title.isEmpty {
                    Text(title)
                        .font(NookDesign.Font.body)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                HStack(spacing: NookDesign.Spacing.sm) {
                    Button("Show Here", action: onShowHere)
                        .buttonStyle(.borderedProminent)
                    Button("Go to Window", action: onGoToWindow)
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(NookDesign.Spacing.lg)
        }
    }
}

/// AppKit host for the compositor, tagged with the item it stands in for so a rebuild can
/// keep the same view instead of recreating it.
final class PageElsewhereHostView: NSHostingView<PageElsewhereView> {
    let itemID: UUID

    init(itemID: UUID, rootView: PageElsewhereView) {
        self.itemID = itemID
        super.init(rootView: rootView)
    }

    @MainActor required init(rootView: PageElsewhereView) {
        fatalError("init(rootView:) is not used")
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}
