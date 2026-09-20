// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  DownloadManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 05/08/2025.
//

import AppKit
import Foundation
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Download Model

@Observable
public class Download: Identifiable {
    public let id: UUID
    let download: WKDownload
    let originalURL: URL
    let suggestedFilename: String
    let destinationPreference: DestinationPreference
    let allowedContentTypes: [UTType]?
    /// Save Image and the media download button: the page chose the URL, so only an image or video is kept.
    let mediaOnly: Bool
    var destinationURL: URL?
    var progress: Double
    var state: DownloadState {
        didSet {
            if state == .completed && oldValue != .completed {
                Task {
                    await loadThumbnail()
                }
            }
        }
    }

    var error: Error?
    var fileSize: Int64?
    var downloadedBytes: Int64
    var icon: NSImage?
    var startDate: Date
    var estimatedTimeRemaining: TimeInterval?
    var downloadThumbnail: NSImage?

    enum DownloadState {
        case pending
        case downloading
        case completed
        case failed
        case cancelled

        var description: String {
            switch self {
            case .pending:
                return "Pending"
            case .downloading:
                return "Downloading"
            case .completed:
                return "Completed"
            case .failed:
                return "Failed"
            case .cancelled:
                return "Cancelled"
            }
        }

        var icon: String {
            switch self {
            case .pending:
                return "clock"
            case .downloading:
                return "arrow.down.circle"
            case .completed:
                return "checkmark.circle"
            case .failed:
                return "exclamationmark.circle"
            case .cancelled:
                return "xmark.circle"
            }
        }
    }

    enum DestinationPreference {
        case automaticDownloadsFolder
        case askUser
    }

    init(
        download: WKDownload,
        originalURL: URL,
        suggestedFilename: String,
        destinationPreference: DestinationPreference = .automaticDownloadsFolder,
        allowedContentTypes: [UTType]? = nil,
        mediaOnly: Bool = false
    ) {
        id = UUID()
        self.download = download
        self.originalURL = originalURL
        self.suggestedFilename = suggestedFilename
        self.destinationPreference = destinationPreference
        self.allowedContentTypes = allowedContentTypes
        self.mediaOnly = mediaOnly
        progress = 0.0
        state = .pending
        downloadedBytes = 0
        startDate = Date()

        // Set default icon based on file extension
        icon = getIconForFile(suggestedFilename)
    }

    @MainActor
    func loadThumbnail(size: CGSize = CGSize(width: 80, height: 80)) async {
        guard let destinationURL = destinationURL,
              FileManager.default.fileExists(atPath: destinationURL.path),
              downloadThumbnail == nil
        else {
            return
        }

        #if DEBUG
        print("Loading thumbnail for: \(destinationURL.lastPathComponent)")
        #endif

        if shouldGenerateThumbnail(for: destinationURL) {
            if let thumbnail = await getQuickLookThumbnail(for: destinationURL, size: size) {
                downloadThumbnail = thumbnail
                #if DEBUG
                print("QuickLook thumbnail loaded for: \(destinationURL.lastPathComponent)")
                #endif
                return
            }
            #if DEBUG
            print("QuickLook thumbnail failed, falling back to Finder icon for: \(destinationURL.lastPathComponent)")
            #endif
        }

        let finderIcon = NSWorkspace.shared.icon(forFile: destinationURL.path)

        let targetSize = NSSize(width: size.width, height: size.height)
        let highResIcon = NSImage(size: targetSize)

        highResIcon.lockFocus()
        finderIcon.draw(in: NSRect(origin: .zero, size: targetSize),
                        from: NSRect(origin: .zero, size: finderIcon.size),
                        operation: .copy,
                        fraction: 1.0)
        highResIcon.unlockFocus()

        downloadThumbnail = highResIcon
        #if DEBUG
        print("Finder icon loaded for: \(destinationURL.lastPathComponent)")
        #endif
    }

    private func shouldGenerateThumbnail(for fileURL: URL) -> Bool {
        let fileExtension = fileURL.pathExtension.lowercased()

        let supportedExtensions: Set<String> = [
            // Images
            "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "webp", "ico", "svg",
            // Videos
            "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v",
            // Documents
            "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "pages", "numbers", "keynote",
            // Text files
            "txt", "rtf", "html", "htm", "md", "swift", "js", "css", "json", "xml",
            // Audio files
            "mp3", "m4a", "flac", "aac",
        ]

        return supportedExtensions.contains(fileExtension)
    }

    private func getQuickLookThumbnail(for fileURL: URL, size: CGSize) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 1.0,
            representationTypes: .thumbnail
        )

        do {
            let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return thumbnail.nsImage
        } catch {
            return nil
        }
    }

    private func getIconForFile(_ filename: String) -> NSImage {
        let fileExtension = (filename as NSString).pathExtension.lowercased()

        let possibleTypes = UTType.types(tag: fileExtension,
                                         tagClass: .filenameExtension,
                                         conformingTo: nil)

        if let utType = possibleTypes.first {
            return NSWorkspace.shared.icon(for: utType)
        } else {
            return NSWorkspace.shared.icon(for: .item)
        }
    }

    var formattedFileSize: String {
        guard let fileSize = fileSize else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDownloadedSize: String {
        return ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }

    var formattedProgress: String {
        return String(format: "%.1f%%", progress * 100)
    }

    var formattedSpeed: String {
        let elapsed = Date().timeIntervalSince(startDate)
        guard elapsed > 0 else { return "0 B/s" }

        let speed = Double(downloadedBytes) / elapsed
        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .binary) + "/s"
    }

    var formattedTimeRemaining: String {
        guard let estimatedTimeRemaining = estimatedTimeRemaining else { return "Unknown" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: estimatedTimeRemaining) ?? "Unknown"
    }
}

// MARK: - Download Manager

@MainActor
@Observable
public class DownloadManager: NSObject {
    public static let shared = DownloadManager()

    private var downloads: [UUID: Download] = [:]
    private var downloadDelegates: [UUID: DownloadDelegate] = [:]

    var activeDownloads: [Download] {
        return Array(downloads.values).filter { $0.state == .downloading || $0.state == .pending }
    }

    var completedDownloads: [Download] {
        return Array(downloads.values).filter { $0.state == .completed }
    }

    var failedDownloads: [Download] {
        return Array(downloads.values).filter { $0.state == .failed }
    }

    var allDownloads: [Download] {
        return Array(downloads.values).sorted { $0.startDate > $1.startDate }
    }

    var totalDownloads: Int {
        return downloads.count
    }

    var activeDownloadsCount: Int {
        return activeDownloads.count
    }

    override private init() {
        super.init()
    }

    // MARK: - Download Management

    func addDownload(
        _ download: WKDownload,
        originalURL: URL,
        suggestedFilename: String,
        destinationPreference: Download.DestinationPreference = .automaticDownloadsFolder,
        allowedContentTypes: [UTType]? = nil,
        mediaOnly: Bool = false
    ) -> Download {
        let downloadModel = Download(
            download: download,
            originalURL: originalURL,
            suggestedFilename: suggestedFilename,
            destinationPreference: destinationPreference,
            allowedContentTypes: allowedContentTypes,
            mediaOnly: mediaOnly
        )
        let delegate = DownloadDelegate(downloadManager: self, download: downloadModel)

        downloads[downloadModel.id] = downloadModel
        downloadDelegates[downloadModel.id] = delegate
        download.delegate = delegate

        #if DEBUG
        print("Added download: \(suggestedFilename) with ID: \(downloadModel.id)")
        print("Download delegate set: \(download.delegate != nil)")
        #endif
        return downloadModel
    }

    func removeDownload(_ id: UUID) {
        if let download = downloads[id], download.state == .pending || download.state == .downloading {
            cancelDownload(id)
        }
        downloadDelegates[id]?.stopProgressObservation()
        downloads.removeValue(forKey: id)
        downloadDelegates.removeValue(forKey: id)
    }

    func cancelDownload(_ id: UUID) {
        guard let download = downloads[id] else { return }
        updateDownloadState(id, state: .cancelled)
        download.download.cancel()
        #if DEBUG
        print("Cancelled download: \(download.suggestedFilename)")
        #endif
    }

    func retryDownload(_ id: UUID) {
        guard let download = downloads[id], download.state == .failed else { return }
        #if DEBUG
        print("Retry not supported for WKDownload")
        #endif
    }

    func clearCompletedDownloads() {
        let completedIds = downloads.values.filter { $0.state == .completed }.map { $0.id }
        for id in completedIds {
            removeDownload(id)
        }
    }

    func clearFailedDownloads() {
        let failedIds = downloads.values.filter { $0.state == .failed }.map { $0.id }
        for id in failedIds {
            removeDownload(id)
        }
    }

    func clearAllDownloads() {
        for id in Array(downloads.keys) { removeDownload(id) }
    }

    // MARK: - Download Updates

    func updateDownloadProgress(_ id: UUID, progress: Double, downloadedBytes: Int64, fileSize: Int64?) {
        guard let download = downloads[id] else {
            #if DEBUG
            print("Download not found for ID: \(id)")
            #endif
            return
        }

        #if DEBUG
        print("Updating download progress: \(progress * 100)% for \(download.suggestedFilename)")
        #endif

        guard download.state == .pending || download.state == .downloading else { return }

        download.progress = progress
        download.downloadedBytes = downloadedBytes
        download.fileSize = fileSize

        // Calculate estimated time remaining
        if let fileSize = fileSize, fileSize > 0, downloadedBytes > 0 {
            let elapsed = Date().timeIntervalSince(download.startDate)
            let bytesPerSecond = Double(downloadedBytes) / max(elapsed, 0.001)
            let remainingBytes = max(0, fileSize - downloadedBytes)
            download.estimatedTimeRemaining = Double(remainingBytes) / bytesPerSecond
        } else {
            download.estimatedTimeRemaining = nil
        }
    }

    func updateDownloadState(_ id: UUID, state: Download.DownloadState, error: Error? = nil) {
        guard let download = downloads[id] else {
            #if DEBUG
            print("Download not found for ID: \(id)")
            #endif
            return
        }

        #if DEBUG
        print("Updating download state to \(state.description) for \(download.suggestedFilename)")
        #endif

        guard download.state == .pending || download.state == .downloading else { return }
        download.state = state
        download.error = error
        if state == .completed || state == .failed || state == .cancelled {
            downloadDelegates[id]?.stopProgressObservation()
            download.download.delegate = nil
            downloadDelegates.removeValue(forKey: id)
        }
        if state == .completed {
            download.progress = 1
            download.downloadedBytes = max(download.downloadedBytes, download.download.progress.completedUnitCount)
            download.estimatedTimeRemaining = 0
        }

        #if DEBUG
        if state == .completed {
            print("Download completed: \(download.suggestedFilename)")
        } else if state == .failed {
            print("Download failed: \(download.suggestedFilename) - \(error?.localizedDescription ?? "Unknown error")")
        }
        #endif
    }

    func setDownloadDestination(_ id: UUID, destination: URL) {
        guard let download = downloads[id] else { return }
        download.destinationURL = destination
    }

    /// Sets the `com.apple.quarantine` extended attribute on a downloaded file.
    ///
    /// This ensures macOS Gatekeeper will prompt the user before opening
    /// executables, disk images, or other potentially dangerous files
    /// downloaded from the web.
    nonisolated static func setQuarantineAttribute(on fileURL: URL) {
        // com.apple.quarantine format: flags;timestamp_hex;agent_name;uuid
        // 0083 = "downloaded from the web, not yet opened by the user"
        let quarantineValue = "0083;\(String(format: "%08x", Int(Date().timeIntervalSince1970)));Nook;\(UUID().uuidString)"
        guard let data = quarantineValue.data(using: .utf8) else { return }

        fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path = path else { return }
            let result = setxattr(path, "com.apple.quarantine", (data as NSData).bytes, data.count, 0, 0)
            if result != 0 {
                #if DEBUG
                print("Failed to set quarantine attribute on \(fileURL.lastPathComponent): errno \(errno)")
                #endif
            }
        }
    }
}

// MARK: - Download Delegate

@MainActor
private class DownloadDelegate: NSObject, WKDownloadDelegate {
    weak var downloadManager: DownloadManager?
    let download: Download
    private var progressObservations: [NSKeyValueObservation] = []

    init(downloadManager: DownloadManager, download: Download) {
        self.downloadManager = downloadManager
        self.download = download
        super.init()
    }

    private enum DestinationDecision {
        case proceed(URL)
        case cancel
    }

    // iOS-style API (older) – keep for compatibility where this signature exists
    public func download(_: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        decideDestination(response: response, suggestedFilename: suggestedFilename) { [weak self] decision in
            guard let self else { return }
            switch decision {
            case .proceed(let url):
                completionHandler(url)
            case .cancel:
                self.download.download.cancel()
                completionHandler(nil)
            }
        }
    }

    // macOS 12+/15+ API – WebKit on macOS expects the (URL, Bool) completion to grant a sandbox extension
    public func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL, Bool) -> Void) {
        decideDestination(response: response, suggestedFilename: suggestedFilename) { [weak self] decision in
            guard let self else { return }
            switch decision {
            case .proceed(let url):
                // Return true to grant sandbox extension - this allows WebKit to write to the destination
                completionHandler(url, true)
            case .cancel:
                self.download.download.cancel()
                completionHandler(URL(fileURLWithPath: "/tmp/cancelled"), false)
            }
        }
    }

    private func decideDestination(response: URLResponse, suggestedFilename: String, completion: @escaping (DestinationDecision) -> Void) {
        let defaultName = suggestedFilename.isEmpty ? "download" : suggestedFilename
        var cleanName = defaultName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\0", with: "")       // Strip null bytes
        // Strip leading dots to prevent creating hidden files
        while cleanName.hasPrefix(".") {
            cleanName = String(cleanName.dropFirst())
        }
        if cleanName.isEmpty { cleanName = "download" }
        // A page picked this URL for a one-click save; anything but an image or video is dropped.
        if download.mediaOnly {
            let mimeType = response.mimeType?.lowercased() ?? ""
            guard mimeType.hasPrefix("image/") || mimeType.hasPrefix("video/") else {
                downloadManager?.updateDownloadState(download.id, state: .cancelled)
                completion(.cancel)
                return
            }
            // The server also names the file, and it can claim image/jpeg for "photo.jpg.dmg".
            let named = UTType(filenameExtension: (cleanName as NSString).pathExtension)
            if named?.conforms(to: .image) != true, named?.conforms(to: .audiovisualContent) != true {
                cleanName += "." + (UTType(mimeType: mimeType)?.preferredFilenameExtension ?? "media")
            }
        }
        // Limit filename length to 255 characters (filesystem maximum)
        if cleanName.count > 255 {
            let ext = (cleanName as NSString).pathExtension
            let base = (cleanName as NSString).deletingPathExtension
            let maxBase = 255 - (ext.isEmpty ? 0 : ext.count + 1)
            cleanName = String(base.prefix(maxBase)) + (ext.isEmpty ? "" : ".\(ext)")
        }
        // Safety: use lastPathComponent to ensure no directory traversal
        cleanName = (cleanName as NSString).lastPathComponent

        switch download.destinationPreference {
        case .automaticDownloadsFolder:
            resolveAutomaticDestination(response: response, cleanName: cleanName, completion: completion)
        case .askUser:
            presentSavePanel(response: response, cleanName: cleanName, completion: completion)
        }
    }

    private func resolveAutomaticDestination(response: URLResponse, cleanName: String, completion: @escaping (DestinationDecision) -> Void) {
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            presentSavePanel(response: response, cleanName: cleanName, completion: completion)
            return
        }

        var destination = downloadsDirectory.appendingPathComponent(cleanName)
        let ext = destination.pathExtension
        let base = destination.deletingPathExtension().lastPathComponent
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let newName = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            destination = downloadsDirectory.appendingPathComponent(newName)
            counter += 1
        }

        configureDownload(for: destination, response: response)
        completion(.proceed(destination))
    }

    private func presentSavePanel(response: URLResponse, cleanName: String, completion: @escaping (DestinationDecision) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = cleanName
        savePanel.allowedContentTypes = download.allowedContentTypes ?? [.data]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        if let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloadsDirectory
        }

        DispatchQueue.main.async {
            savePanel.begin { result in
                guard self.download.state == .pending else {
                    completion(.cancel)
                    return
                }
                if result == .OK, let url = savePanel.url {
                    self.configureDownload(for: url, response: response)
                    completion(.proceed(url))
                } else {
                    #if DEBUG
                    print("Download cancelled by user")
                    #endif
                    self.downloadManager?.updateDownloadState(self.download.id, state: .cancelled)
                    completion(.cancel)
                }
            }
        }
    }

    private func configureDownload(for destination: URL, response: URLResponse) {
        let fileSize = response.expectedContentLength
        #if DEBUG
        print("Download destination set: \(destination.path) with fileSize: \(fileSize) bytes")
        #endif
        downloadManager?.updateDownloadProgress(download.id, progress: 0.0, downloadedBytes: 0, fileSize: fileSize > 0 ? fileSize : nil)
        downloadManager?.updateDownloadState(download.id, state: .downloading)
        downloadManager?.setDownloadDestination(download.id, destination: destination)

        startProgressObservation()
    }

    private func startProgressObservation() {
        stopProgressObservation()
        let progress = download.download.progress
        // Progress is KVO-compliant; WebKit supplies byte counts without disk polling.
        progressObservations = [
            progress.observe(\.completedUnitCount, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishProgress() }
            },
            progress.observe(\.totalUnitCount, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishProgress() }
            },
        ]
    }

    func stopProgressObservation() {
        progressObservations.forEach { $0.invalidate() }
        progressObservations.removeAll()
    }

    private func publishProgress() {
        guard download.state == .downloading else { return }
        let progress = download.download.progress
        let completed = max(0, progress.completedUnitCount)
        let total = progress.totalUnitCount > 0 ? progress.totalUnitCount : download.fileSize
        let fraction = total.flatMap { $0 > 0 ? min(1, Double(completed) / Double($0)) : nil } ?? 0
        downloadManager?.updateDownloadProgress(
            download.id, progress: fraction, downloadedBytes: completed, fileSize: total
        )
    }

    func downloadDidFinish(_: WKDownload) {
        #if DEBUG
        print("Download finished: \(download.suggestedFilename)")
        #endif

        publishProgress()

        // Set quarantine attribute so Gatekeeper warns about downloaded executables
        if let destinationURL = download.destinationURL {
            DownloadManager.setQuarantineAttribute(on: destinationURL)
        }

        downloadManager?.updateDownloadState(download.id, state: .completed)
    }

    func download(_: WKDownload, didFailWithError error: Error, resumeData _: Data?) {
        #if DEBUG
        print("Download failed: \(download.suggestedFilename) - \(error.localizedDescription)")
        #endif
        downloadManager?.updateDownloadState(download.id, state: .failed, error: error)
    }

    func downloadWillPerformHTTPRedirection(_: WKDownload, navigationResponse _: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (URLRequest?) -> Void) {
        #if DEBUG
        print("Download will perform HTTP redirection")
        #endif
        // Cookies were picked for the first URL only; a redirect must not carry them to another host.
        var request = request
        if download.mediaOnly {
            request.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        decisionHandler(request)
    }

    func download(_: WKDownload, didReceive _: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        #if DEBUG
        print("Download received authentication challenge")
        #endif
        completionHandler(.performDefaultHandling, nil)
    }

    public func download(_: WKDownload, didFinishDownloadingTo location: URL) {
        #if DEBUG
        print("🔽 [DownloadManager] Download finished to: \(location.path)")
        #endif
        // The download is already handled by downloadDidFinish, but we can add additional logic here if needed
    }

    public func download(_: WKDownload, didFailWithError error: Error) {
        #if DEBUG
        print("🔽 [DownloadManager] Download failed: \(error.localizedDescription)")
        #endif
        // The download is already handled by the existing didFailWithError method, but we can add additional logic here if needed
    }
}
