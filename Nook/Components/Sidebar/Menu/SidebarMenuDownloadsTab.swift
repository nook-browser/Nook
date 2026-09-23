// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarMenuDownloadsTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import AppKit
import SwiftUI
import NookDesign
import NookUI

struct SidebarMenuDownloadsTab: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var text: String = ""

    private var filteredDownloads: [Download] {
        if text.isEmpty {
            return browserManager.downloadManager.allDownloads
        } else {
            return browserManager.downloadManager.allDownloads.filter { download in
                download.suggestedFilename.localizedCaseInsensitiveContains(text) ||
                    download.originalURL.absoluteString.localizedCaseInsensitiveContains(text)
            }
        }
    }

    var body: some View {
        // Once per render: every access sorts the whole list.
        let downloads = filteredDownloads
        ScrollView {
            LazyVStack(spacing: NookDesign.Spacing.rowGap) {
                if downloads.isEmpty && !text.isEmpty {
                    VStack(spacing: NookDesign.Spacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(NookDesign.Font.titleLarge)
                            .foregroundStyle(.tertiary)
                        Text("No downloads found")
                            .font(NookDesign.Font.body)
                            .foregroundStyle(.secondary)
                        Text("Try searching with a different term")
                            .font(NookDesign.Font.secondary)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, NookDesign.Spacing.xxxl)
                } else {
                    ForEach(downloads) { download in
                        DownloadItem(download: download)
                    }
                }
            }
            .padding(.horizontal, NookDesign.Spacing.md)
            .padding(.bottom, NookDesign.Spacing.md)
        }
        // Rows scroll under the floating search field, as in the history tab.
        .safeAreaBar(edge: .top, spacing: 0) {
            SidebarMenuSearchField(prompt: "Search downloads...", text: $text)
                .padding(NookDesign.Spacing.md)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

struct DownloadItem: View {
    @State private var isHovering: Bool = false
    var download: Download

    private let iconSize: CGFloat = 24

    var body: some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Image(nsImage: download.downloadThumbnail ?? download.icon)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: 0) {
                Text(download.suggestedFilename)
                    .font(NookDesign.Font.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(download.originalURL.absoluteString)
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            if isHovering {
                Menu {
                    Button(action: openFile) {
                        Label("Open", systemImage: "doc")
                    }
                    Button(action: copyFile) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button(action: showInFinder) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    Divider()
                    Button(action: moveToTrash) {
                        Label("Move to Trash", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(NookIconButtonStyle())
                .transition(.opacity)
            }
        }
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        .padding(.vertical, NookDesign.Spacing.sm)
        .background(isHovering ? NookDesign.Surface.fill : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.md))
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .onHoverTracking { state in
            withAnimation(NookDesign.Motion.quick) {
                isHovering = state
            }
        }
        .onTapGesture {
            openFile()
        }
        .onDrag {
            download.dragItemProvider()
        }
    }

    private func openFile() {
        guard let file = download.completedFile else { return }
        NSWorkspace.shared.open(file)
    }

    private func copyFile() {
        guard let file = download.completedFile else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
    }

    /// Any file on disk, finished or not, the way Finder's own downloads stack behaves.
    private func showInFinder() {
        guard let destinationURL = download.destinationURL,
              FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    /// This item used to call Show in Finder. The row stays, as it does in Safari.
    private func moveToTrash() {
        guard let file = download.completedFile else { return }
        NSWorkspace.shared.recycle([file])
    }
}
