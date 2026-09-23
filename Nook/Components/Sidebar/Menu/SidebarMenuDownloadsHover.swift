// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarMenuHoverDownloads.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import SwiftUI
import NookDesign
import NookUI

struct SidebarMenuHoverDownloads: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var itemsVisible: [Bool] = []
    let isVisible: Bool

    /// Shown only while there is something to list; the sidebar leaves it out otherwise.
    var body: some View {
        // Once per render: it sorts, and the rows used to ask per row.
        let downloads = browserManager.downloadManager.recentDownloads
        VStack(spacing: NookDesign.Spacing.rowGap) {
            ForEach(Array(downloads.enumerated()), id: \.element.id) { index, download in
                let shown = index < itemsVisible.count && itemsVisible[index]
                SidebarMenuHoverDownloadItem(download: download)
                    .offset(y: shown ? 0 : 50)
                    .opacity(shown ? 1 : 0)
                    .animation(
                        NookDesign.Motion.quick.delay(Double(downloads.count - index) * 0.01),
                        value: shown
                    )
            }
        }
        .padding(NookDesign.Spacing.xs)
        // The recent downloads card that opens above the bottom bar on hover.
        .nookControlGlass(in: NookDesign.Radius.shape(NookDesign.Radius.lg))
        .padding(.horizontal, NookDesign.Spacing.sidebarInset)
        .onAppear {
            updateItemsVisible(count: downloads.count)
            if isVisible {
                show()
            } else {
                hide()
            }
        }
        .onChange(of: isVisible) { _, newValue in
            updateItemsVisible(count: downloads.count)
            if newValue {
                show()
            } else {
                hide()
            }
        }
        .onChange(of: downloads.count) { _, count in
            updateItemsVisible(count: count)
        }
    }

    private func updateItemsVisible(count: Int) {
        if itemsVisible.count != count {
            itemsVisible = Array(repeating: false, count: count)
        }
    }

    func show() {
        for index in 0 ..< itemsVisible.count {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Double(itemsVisible.count - index) * 0.01
            ) {
                if index < itemsVisible.count {
                    itemsVisible[index] = true
                }
            }
        }
    }

    func hide() {
        for index in 0 ..< itemsVisible.count {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Double(index) * 0.01
            ) {
                if index < itemsVisible.count {
                    itemsVisible[index] = false
                }
            }
        }
    }
}

struct SidebarMenuHoverDownloadItem: View {
    @State private var isHovering: Bool = false
    let download: Download

    private let iconSize: CGFloat = 32

    private var timeAgoText: String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(download.startDate)

        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) min ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d ago"
        }
    }

    private var statusText: String {
        switch download.state {
        case .downloading:
            return download.formattedProgress
        case .completed:
            return timeAgoText
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .pending:
            return "Pending"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: NookDesign.Spacing.md) {
            Group {
                if download.state == .downloading {
                    CircularProgressView(progress: download.progress)
                } else {
                    Image(nsImage: download.downloadThumbnail ?? download.icon)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: 0) {
                Text(download.suggestedFilename)
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Bytes while they are moving; otherwise the state in a word.
                Group {
                    if download.state == .downloading {
                        Text(
                            "\(download.formattedDownloadedSize)/\(download.formattedFileSize) • \(download.formattedTimeRemaining)"
                        )
                    } else {
                        Text(statusText)
                    }
                }
                .font(NookDesign.Font.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        .padding(.vertical, NookDesign.Spacing.sm)
        .background(isHovering ? NookDesign.Surface.fill : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.md))
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .animation(NookDesign.Motion.quick, value: isHovering)
        .onHoverTracking { state in
            isHovering = state
        }
        .onTapGesture {
            if let file = download.completedFile {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
        }
        .onDrag {
            download.dragItemProvider()
        }
    }
}
