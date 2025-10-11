//
//  SidebarMenuDownloadsTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarMenuDownloadsTab: View {
    @Environment(BrowserManager.self) private var browserManager
    @State private var isHovering: Bool = false
    @State private var text: String = ""
    @FocusState private var isSearchFocused: Bool

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
        VStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 16, height: 16)
                TextField("Search downloads...", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
                    .focused($isSearchFocused)

                if !text.isEmpty {
                    Button(action: {
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(isHovering ? .white.opacity(0.08) : .white.opacity(0.05))
            .animation(.easeInOut(duration: 0.1), value: isHovering)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onHover { state in
                isHovering = state
            }
            .onTapGesture {
                isSearchFocused = true
            }

            ScrollView {
                VStack(spacing: 8) {
                    if filteredDownloads.isEmpty && !text.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text("No downloads found")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Try searching with a different term")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    } else {
                        ForEach(filteredDownloads.indices, id: \.self) { index in
                            let entry = filteredDownloads[index]
                            DownloadItem(download: entry)
                        }
                    }
                }
            }
        }
        .padding(8)
    }
}

struct DownloadItem: View {
    @State private var isHovering: Bool = false
    @State private var isIconHovered: Bool = false
    var download: Download

    private var canDrag: Bool {
        guard download.state == .completed,
              let destinationURL = download.destinationURL
        else {
            return false
        }
        return FileManager.default.fileExists(atPath: destinationURL.path)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: download.downloadThumbnail ?? download.icon!)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(download.suggestedFilename)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(download.originalURL.absoluteString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()

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
                    Button(action: showInFinder) {
                        Label("Move to Trash", systemImage: "trash")
                    }
                } label: {
                    Button {} label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 16, height: 16)
                    }
                    .padding(8)
                    .background(isIconHovered ? .white.opacity(0.1) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(PlainButtonStyle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .onHover { state in
                    isIconHovered = state
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(isHovering ? .white.opacity(0.2) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.1), value: isHovering)
        .onHover { state in
            isHovering = state
        }
        .onTapGesture {
            openFile()
        }
        .onDrag {
            guard canDrag,
                  let destinationURL = download.destinationURL,
                  FileManager.default.fileExists(atPath: destinationURL.path)
            else {
                return NSItemProvider()
            }

            let provider = NSItemProvider(contentsOf: destinationURL)

            if let fileData = try? Data(contentsOf: destinationURL) {
                let fileExtension = destinationURL.pathExtension.lowercased()

                if let utType = UTType(filenameExtension: fileExtension) {
                    provider?.registerDataRepresentation(
                        forTypeIdentifier: utType.identifier,
                        visibility: .all
                    ) { completion in
                        completion(fileData, nil)
                        return nil
                    }
                }
            }

            return provider ?? NSItemProvider()
        }
    }

    private func openFile() {
        guard let destinationURL = download.destinationURL else {
            print(
                "No destination URL available for download: \(download.suggestedFilename)"
            )
            return
        }

        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            print("File does not exist at path: \(destinationURL.path)")
            return
        }

        NSWorkspace.shared.open(destinationURL)
    }

    private func copyFile() {
        guard let destinationURL = download.destinationURL else {
            print(
                "No destination URL available for download: \(download.suggestedFilename)"
            )
            return
        }

        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            print("File does not exist at path: \(destinationURL.path)")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([destinationURL as NSURL])
    }

    private func showInFinder() {
        guard let destinationURL = download.destinationURL else {
            print(
                "No destination URL available for download: \(download.suggestedFilename)"
            )
            return
        }

        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            print("File does not exist at path: \(destinationURL.path)")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }
}
