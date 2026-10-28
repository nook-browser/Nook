// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarMenuDownloadsTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import NookDesign
import NookUI

struct SidebarMenuDownloadsTab: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var text: String = ""
    @State private var profileID: UUID?

    private var filteredDownloads: [Download] {
        browserManager.downloadManager.allDownloads.filter { download in
            (profileID == nil || download.origin.profileID == profileID)
                && (text.isEmpty
                    || download.displayName.localizedCaseInsensitiveContains(text)
                    || download.originalURL.absoluteString.localizedCaseInsensitiveContains(text))
        }
    }

    var body: some View {
        // Once per render: every access sorts the whole list.
        let downloads = filteredDownloads
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NookDesign.Spacing.rowGap) {
                if downloads.isEmpty {
                    VStack(spacing: NookDesign.Spacing.md) {
                        Image(systemName: text.isEmpty && profileID == nil ? "arrow.down.circle" : "magnifyingglass")
                            .font(NookDesign.Font.titleLarge)
                            .foregroundStyle(.tertiary)
                        Text(text.isEmpty && profileID == nil ? "No downloads yet" : "No downloads found")
                            .font(NookDesign.Font.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NookDesign.Spacing.xxxl)
                } else {
                    ForEach(Self.days(downloads), id: \.title) { day in
                        Text(day.title)
                            .font(NookDesign.Font.label)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, NookDesign.Spacing.rowPadding)
                            .padding(.top, NookDesign.Spacing.lg)
                            .padding(.bottom, NookDesign.Spacing.xs)
                        ForEach(day.downloads) { download in
                            DownloadItem(download: download)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                }
            }
            .padding(.horizontal, NookDesign.Spacing.md)
            .padding(.bottom, NookDesign.Spacing.md)
        }
        // Rows scroll under the floating search field, as in the history tab.
        .nookScrollHeader {
            HStack(spacing: NookDesign.Spacing.sm) {
                SidebarMenuSearchField(prompt: "Search downloads...", text: $text)
                filterMenu
            }
            .padding(NookDesign.Spacing.md)
        }
    }

    /// Hidden while there is only one profile to filter by.
    @ViewBuilder
    private var filterMenu: some View {
        let profiles = browserManager.tabs.profiles
        if profiles.count > 1 {
            Menu {
                Picker("Show", selection: $profileID) {
                    Text("All Downloads").tag(UUID?.none)
                    Divider()
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(UUID?.some(profile.id))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(profiles.first { $0.id == profileID }?.name ?? "Filter",
                      systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(RectNavButtonStyle())
            .fixedSize()
        }
    }

    private struct Day {
        let title: String
        let downloads: [Download]
    }

    /// Today, Yesterday, then days ago for a week, then the date, as Arc groups them.
    private static func days(_ downloads: [Download]) -> [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var order: [Date] = []
        var byDay: [Date: [Download]] = [:]
        for download in downloads {
            let day = calendar.startOfDay(for: download.startDate)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(download)
        }
        return order.map { day in
            let ago = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let title: String
            switch ago {
            case 0: title = "Today"
            case 1: title = "Yesterday"
            case 2..<7: title = "\(ago) days ago"
            default: title = day.formatted(.dateTime.day().month(.wide).year())
            }
            return Day(title: title, downloads: byDay[day] ?? [])
        }
    }
}

/// What a downloaded file is, for the row's subtitle.
enum DownloadKind: Hashable {
    case image, video, audio, pdf, document, diskImage, archive, other

    init(_ filename: String) {
        let type = UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data
        switch true {
        case type.conforms(to: .image): self = .image
        case type.conforms(to: .movie): self = .video
        case type.conforms(to: .audio): self = .audio
        case type.conforms(to: .pdf): self = .pdf
        case type.conforms(to: .diskImage): self = .diskImage
        case type.conforms(to: .archive): self = .archive
        case type.conforms(to: .text), type.conforms(to: .presentation), type.conforms(to: .spreadsheet),
             type.conforms(to: .rtf), type.conforms(to: .compositeContent): self = .document
        default: self = .other
        }
    }

    var name: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        case .pdf: "PDF"
        case .document: "Document"
        case .diskImage: "Disk Image"
        case .archive: "Archive"
        case .other: "Download"
        }
    }
}

struct DownloadItem: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var isHovering: Bool = false
    var download: Download

    private let iconSize: CGFloat = 36

    /// "Disk Image from github.com", as Arc writes it.
    private var subtitle: String {
        let kind = DownloadKind(download.displayName).name
        guard let host = download.originalURL.host, !host.isEmpty else { return kind }
        return "\(kind) from \(host)"
    }

    var body: some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Image(nsImage: download.downloadThumbnail ?? download.icon)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: NookDesign.Spacing.xs) {
                    Text(download.displayName)
                        .font(NookDesign.Font.title)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .id(download.displayName)
                        .transition(.blurReplace)
                    if download.renamedFrom != nil {
                        Image(systemName: "sparkles")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                            .symbolEffect(.bounce, value: download.displayName)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                            .help("Renamed by Tidy Downloads")
                    }
                }

                Text(subtitle)
                    .font(NookDesign.Font.body)
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
                    if download.renamedFrom != nil {
                        Button {
                            browserManager.downloadManager.undoTidy(download)
                        } label: {
                            Label("Restore Original Name", systemImage: "arrow.uturn.backward")
                        }
                    }
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
            if download.completedFile != nil { browserManager.downloadManager.previewing = download }
        }
        .onDrag {
            download.dragItemProvider()
        }
        // Rows restored from an earlier launch load their thumbnail when they first show.
        .task(id: download.destinationURL) {
            if download.downloadThumbnail == nil, download.state == .completed { await download.loadThumbnail() }
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

    /// The file goes to the Trash and its row leaves the list.
    private func moveToTrash() {
        browserManager.downloadManager.moveToTrash(download)
    }
}
