//
//  SidebarMenuDownloadsTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 17/09/2025.
//

import AppKit
import SwiftUI

struct SidebarMenuDownloadsTab: View {
    @EnvironmentObject var browserManager: BrowserManager
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
                    .font(.system(size: 12, weight: .medium))
                TextField("Search downloads", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AppColors.textPrimary)
                    .focused($isSearchFocused)
                
                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHovering ? .white.opacity(0.3) : .white.opacity(0.2))
            .animation(.easeInOut(duration: 0.1), value: isHovering)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onHover { state in
                isHovering = state
            }
            .onTapGesture {
                isSearchFocused = true
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
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
    var download: Download

    var body: some View {
        HStack {
            Image(nsImage: download.icon!)
            VStack(alignment: .leading, spacing: 4) {
                Text(download.suggestedFilename)
                    .font(.system(size: 14, weight: .medium))
                Text(download.originalURL.absoluteString)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
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
            } label: {
                NavButton(iconName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

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
            showInFinder()
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
