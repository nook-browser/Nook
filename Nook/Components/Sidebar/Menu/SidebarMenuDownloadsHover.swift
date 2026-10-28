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
                    .offset(y: shown ? 0 : 16)
                    .opacity(shown ? 1 : 0)
                    .blur(radius: shown ? 0 : 4)
                    .animation(
                        .interpolatingSpring(Spring(response: 0.32, dampingRatio: 0.86))
                            .delay(Double(downloads.count - index) * 0.04),
                        value: shown
                    )
            }
        }
        // Arc's recent downloads: rows straight on the sidebar, no card, rising in one by one.
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

    private let iconSize: CGFloat = 40

    /// "40 minutes ago", in full as Arc writes it.
    private var timeAgoText: String {
        guard Date().timeIntervalSince(download.startDate) >= 60 else { return "Just now" }
        return download.startDate.formatted(.relative(presentation: .named, unitsStyle: .wide))
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
                    // A page-like tile: the file's own preview filling a small rounded card.
                    Image(nsImage: download.downloadThumbnail ?? download.icon)
                        .resizable()
                        .aspectRatio(contentMode: download.downloadThumbnail == nil ? .fit : .fill)
                        .frame(width: iconSize, height: iconSize)
                        .background(download.downloadThumbnail == nil ? Color.clear : Color.white)
                        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                        .overlay(NookDesign.Radius.shape(NookDesign.Radius.sm).strokeBorder(NookDesign.Surface.hairline))
                }
            }
            .frame(width: iconSize, height: iconSize)
            .task(id: download.destinationURL) {
                if download.downloadThumbnail == nil, download.state == .completed { await download.loadThumbnail() }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(download.displayName)
                    .id(download.displayName)
                    .transition(.blurReplace)
                    .font(NookDesign.Font.title)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

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
                .font(NookDesign.Font.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, NookDesign.Spacing.xs)
        .padding(.vertical, NookDesign.Spacing.xs)
        .background(isHovering ? NookDesign.Surface.fill : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.md))
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .animation(NookDesign.Motion.quick, value: isHovering)
        .onHoverTracking { state in
            isHovering = state
        }
        // Opens in place, as Arc does, rather than in Finder.
        .onTapGesture {
            if download.completedFile != nil { DownloadManager.shared.previewing = download }
        }
        .onDrag {
            download.dragItemProvider()
        }
    }
}
