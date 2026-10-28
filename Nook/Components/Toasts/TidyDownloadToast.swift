// Licensed under GPL-3.0. See LICENSE.
//
//  TidyDownloadToast.swift
//  Nook
//
//  Shown when Tidy Downloads renames a file: the new name, the old one struck through, undo.
//

import SwiftUI
import NookDesign
import NookUI

struct TidyDownloadToast: View {
    let download: Download
    let downloads: DownloadManager

    private let visibleFor: Duration = .seconds(6)
    private let maxWidth: CGFloat = 300

    var body: some View {
        HStack(alignment: .top, spacing: NookDesign.Spacing.md) {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text("Download renamed to:")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
                Text(download.displayName)
                    .font(NookDesign.Font.secondary)
                    .lineLimit(1)
                if let old = download.renamedFrom {
                    Text(old)
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.tertiary)
                        .strikethrough()
                        .lineLimit(1)
                }
            }
            HStack(spacing: NookDesign.Spacing.xxs) {
                Button("Undo", systemImage: "arrow.uturn.backward") { downloads.undoTidy(download) }
                    .help("Undo")
                Button("Close", systemImage: "xmark") { downloads.dismissTidyToast() }
                    .help("Close")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.rowButton))
            .foregroundStyle(.secondary)
        }
        .padding(NookDesign.Spacing.lg)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .nookFloatingSurface(in: NookDesign.Radius.shape(NookDesign.Radius.xl))
        .task(id: download.id) {
            try? await Task.sleep(for: visibleFor)
            if downloads.lastTidied === download { downloads.dismissTidyToast() }
        }
    }
}
