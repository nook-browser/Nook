//
//  SidebarMenuHoverDownloads.swift
//  Nook
//
//  Created by Maciek Bagiński on 18/09/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct SidebarMenuHoverDownloads: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var itemsVisible: [Bool] = []
    let isVisible: Bool
    let onAnimationComplete: (Bool) -> Void

    private var prioritizedDownloads: [Download] {
        let activeDownloads = browserManager.downloadManager.activeDownloads
            .sorted { $0.startDate > $1.startDate }
        let completedDownloads = browserManager.downloadManager
            .completedDownloads.sorted { $0.startDate > $1.startDate }
        let failedDownloads = browserManager.downloadManager.failedDownloads
            .sorted { $0.startDate > $1.startDate }

        var result: [Download] = []

        result.append(contentsOf: activeDownloads.prefix(4))

        if result.count < 4 {
            let remaining = 4 - result.count
            result.append(contentsOf: completedDownloads.prefix(remaining))
        }

        if result.count < 4 {
            let remaining = 4 - result.count
            result.append(contentsOf: failedDownloads.prefix(remaining))
        }

        return Array(result.prefix(4))
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(prioritizedDownloads.enumerated()), id: \.element.id) { index, download in
                SidebarMenuHoverDownloadItem(download: download, index: index)
                    .offset(
                        y: (index < itemsVisible.count && itemsVisible[index])
                            ? 0 : 50
                    )
                    .opacity(
                        (index < itemsVisible.count && itemsVisible[index])
                            ? 1 : 0
                    )
                    .animation(
                        .easeOut(duration: 0.15)
                            .delay(
                                Double(prioritizedDownloads.count - index)
                                    * 0.01
                            ),
                        value: index < itemsVisible.count
                            ? itemsVisible[index] : false
                    )
            }

            if prioritizedDownloads.isEmpty {
                Text("No downloads")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            updateItemsVisible()
            if isVisible {
                show()
            } else {
                hide()
            }
        }
        .onChange(of: isVisible) { _, newValue in
            updateItemsVisible()
            if newValue {
                show()
            } else {
                hide()
            }
        }
        .onChange(of: prioritizedDownloads.count) { _, _ in
            updateItemsVisible()
        }
    }

    private func updateItemsVisible() {
        let count = prioritizedDownloads.count
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
        print("hidden")

        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(itemsVisible.count) * 0.01 + 0.15
        ) {
            onAnimationComplete(false)
        }
    }
}

struct SidebarMenuHoverDownloadItem: View {
    @State private var isHovering: Bool = false
    let download: Download
    let index: Int

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

    private var canDrag: Bool {
        guard download.state == .completed,
              let destinationURL = download.destinationURL
        else {
            return false
        }
        return FileManager.default.fileExists(atPath: destinationURL.path)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if download.state == .downloading {
                CircularProgressView(progress: download.progress)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 8)
            } else if download.state == .completed
                && download.downloadThumbnail != nil
            {
                Image(nsImage: download.downloadThumbnail!)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            } else if let icon = download.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.primary)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 20))
                    .frame(width: 32, height: 32)
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(download.suggestedFilename)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    if download.state != .completed {
                        Text(
                            "\(download.formattedDownloadedSize)/\(download.formattedFileSize) • \(download.formattedTimeRemaining)"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    } else {
                        Text(statusText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovering ? .white.opacity(0.2) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.1), value: isHovering)
        .onHover { state in
            isHovering = state
        }
        .onTapGesture {
            if let destinationURL = download.destinationURL,
               download.state == .completed,
               FileManager.default.fileExists(atPath: destinationURL.path)
            {
                NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
            }
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
}
