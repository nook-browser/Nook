// Licensed under GPL-3.0. See LICENSE.
//
//  BackgroundTabToast.swift
//  Nook
//

import SwiftUI
import NookDesign
import NookTabsCore

/// Shown when a tab opens in the background while the sidebar is hidden; a click selects it.
public struct BackgroundTabToast: View {
    let item: Item
    let title: String
    let count: Int
    let onSelect: () -> Void

    public init(item: Item, title: String, count: Int, onSelect: @escaping () -> Void) {
        self.item = item
        self.title = title
        self.count = count
        self.onSelect = onSelect
    }

    public var body: some View {
        ToastView {
            HStack(spacing: NookDesign.Spacing.md) {
                ItemFavicon(item: item, session: nil)
                    .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                VStack(alignment: .leading, spacing: 0) {
                    if count == 1 {
                        Text(title.prefix(40))
                            .font(NookDesign.Font.secondary)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text(count == 1 ? "Opened in background" : "\(count) tabs opened in background")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(count == 1 ? .secondary : .primary)
                }
            }
        }
        .transition(.toast)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
