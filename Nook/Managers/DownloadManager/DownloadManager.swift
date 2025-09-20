//
//  DownloadManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 05/08/2025.
//

import AppKit
import Foundation
import SwiftUI
import WebKit
import QuickLook
import QuickLookThumbnailing
import UniformTypeIdentifiers

// MARK: - Download Model
@Observable
public class Download: Identifiable {
    public let id: UUID
    let download: WKDownload
    let originalURL: URL
    let suggestedFilename: String
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
    
    init(download: WKDownload, originalURL: URL, suggestedFilename: String) {
        self.id = UUID()
        self.download = download
        self.originalURL = originalURL
        self.suggestedFilename = suggestedFilename
        self.progress = 0.0
        self.state = .pending
        self.downloadedBytes = 0
        self.startDate = Date()
        
        // Set default icon based on file extension
        self.icon = getIconForFile(suggestedFilename)
    }
    
    @MainActor
    func loadThumbnail(size: CGSize = CGSize(width: 80, height: 80)) async {
        guard let destinationURL = destinationURL,
              FileManager.default.fileExists(atPath: destinationURL.path),
              downloadThumbnail == nil else {
            return
        }
        
        print("Loading thumbnail for: \(destinationURL.lastPathComponent)")
        
        if shouldGenerateThumbnail(for: destinationURL) {
            if let thumbnail = await getQuickLookThumbnail(for: destinationURL, size: size) {
                self.downloadThumbnail = thumbnail
                print("QuickLook thumbnail loaded for: \(destinationURL.lastPathComponent)")
                return
            }
            print("QuickLook thumbnail failed, falling back to Finder icon for: \(destinationURL.lastPathComponent)")
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
        
        self.downloadThumbnail = highResIcon
        print("Finder icon loaded for: \(destinationURL.lastPathComponent)")
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
            "mp3", "m4a", "flac", "aac"
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
    
    private override init() {
        super.init()
    }
    
    // MARK: - Download Management
    func addDownload(_ download: WKDownload, originalURL: URL, suggestedFilename: String) -> Download {
        let downloadModel = Download(download: download, originalURL: originalURL, suggestedFilename: suggestedFilename)
        let delegate = DownloadDelegate(downloadManager: self, download: downloadModel)
        
        downloads[downloadModel.id] = downloadModel
        downloadDelegates[downloadModel.id] = delegate
        download.delegate = delegate
        
        print("Added download: \(suggestedFilename) with ID: \(downloadModel.id)")
        print("Download delegate set: \(download.delegate != nil)")
        return downloadModel
    }
    
    func removeDownload(_ id: UUID) {
        downloads.removeValue(forKey: id)
        downloadDelegates.removeValue(forKey: id)
    }
    
    func cancelDownload(_ id: UUID) {
        guard let download = downloads[id] else { return }
        download.state = .cancelled
        download.download.cancel()
        print("Cancelled download: \(download.suggestedFilename)")
    }
    
    func retryDownload(_ id: UUID) {
        guard let download = downloads[id], download.state == .failed else { return }
        print("Retry not supported for WKDownload")
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
        downloads.removeAll()
        downloadDelegates.removeAll()
    }
    
    // MARK: - Download Updates
    func updateDownloadProgress(_ id: UUID, progress: Double, downloadedBytes: Int64, fileSize: Int64?) {
        guard let download = downloads[id] else { 
            print("Download not found for ID: \(id)")
            return 
        }
        
        print("Updating download progress: \(progress * 100)% for \(download.suggestedFilename)")
        
        download.progress = progress
        download.downloadedBytes = downloadedBytes
        download.fileSize = fileSize
        
        // Calculate estimated time remaining
        if let fileSize = fileSize, downloadedBytes > 0 {
            let elapsed = Date().timeIntervalSince(download.startDate)
            let bytesPerSecond = Double(downloadedBytes) / elapsed
            let remainingBytes = fileSize - downloadedBytes
            download.estimatedTimeRemaining = Double(remainingBytes) / bytesPerSecond
        }
    }
    
    func updateDownloadState(_ id: UUID, state: Download.DownloadState, error: Error? = nil) {
        guard let download = downloads[id] else { 
            print("Download not found for ID: \(id)")
            return 
        }
        
        print("Updating download state to \(state.description) for \(download.suggestedFilename)")
        
        download.state = state
        download.error = error
        
        if state == .completed {
            print("Download completed: \(download.suggestedFilename)")
        } else if state == .failed {
            print("Download failed: \(download.suggestedFilename) - \(error?.localizedDescription ?? "Unknown error")")
        }
    }
    
    func setDownloadDestination(_ id: UUID, destination: URL) {
        guard let download = downloads[id] else { return }
        download.destinationURL = destination
    }
}

// MARK: - Download Delegate
private class DownloadDelegate: NSObject, WKDownloadDelegate {
    weak var downloadManager: DownloadManager?
    let download: Download
    
    init(downloadManager: DownloadManager, download: Download) {
        self.downloadManager = downloadManager
        self.download = download
        super.init()
    }
    
    // iOS-style API (older) – keep for compatibility where this signature exists
    public func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            completionHandler(nil)
            return
        }
        
        let defaultName = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let cleanName = defaultName.replacingOccurrences(of: "/", with: "_")
        
        var dest = downloads.appendingPathComponent(cleanName)
        let ext = dest.pathExtension
        let base = dest.deletingPathExtension().lastPathComponent
        var counter = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let newName = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            dest = downloads.appendingPathComponent(newName)
            counter += 1
        }
        
        let fileSize = response.expectedContentLength
        print("Download destination set: \(dest.path) with file size: \(fileSize) bytes")
        downloadManager?.updateDownloadProgress(self.download.id, progress: 0.0, downloadedBytes: 0, fileSize: fileSize)
        downloadManager?.updateDownloadState(self.download.id, state: .downloading)
        downloadManager?.setDownloadDestination(self.download.id, destination: dest)
        
        startFileSizeMonitoring()
        
        completionHandler(dest)
    }

    // macOS 12+/15+ API – WebKit on macOS expects the (URL, Bool) completion to grant a sandbox extension
    public func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL, Bool) -> Void) {
        let defaultName = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let cleanName = defaultName.replacingOccurrences(of: "/", with: "_")
        
        // Try Downloads folder first
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            var dest = downloads.appendingPathComponent(cleanName)
            let ext = dest.pathExtension
            let base = dest.deletingPathExtension().lastPathComponent
            var counter = 1
            while FileManager.default.fileExists(atPath: dest.path) {
                let newName = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
                dest = downloads.appendingPathComponent(newName)
                counter += 1
            }
            
            let fileSize = response.expectedContentLength
            print("Download destination set: \(dest.path) with file size: \(fileSize) bytes")
            downloadManager?.updateDownloadProgress(self.download.id, progress: 0.0, downloadedBytes: 0, fileSize: fileSize)
            downloadManager?.updateDownloadState(self.download.id, state: .downloading)
            downloadManager?.setDownloadDestination(self.download.id, destination: dest)
            
            startFileSizeMonitoring()
            
            // Do not allow overwrite; we already de-duped above
            completionHandler(dest, false)
        } else {
            // Fallback: use NSSavePanel if Downloads access fails
            print("Downloads folder access failed, using NSSavePanel fallback")
            DispatchQueue.main.async {
                self.showSavePanel(for: download, response: response, suggestedFilename: cleanName, completionHandler: completionHandler)
            }
        }
    }
    
    private func showSavePanel(for download: WKDownload, response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL, Bool) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.allowedContentTypes = [.data] // Allow any file type
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                let fileSize = response.expectedContentLength
                print("Download destination set via save panel: \(url.path) with file size: \(fileSize) bytes")
                self.downloadManager?.updateDownloadProgress(self.download.id, progress: 0.0, downloadedBytes: 0, fileSize: fileSize)
                self.downloadManager?.updateDownloadState(self.download.id, state: .downloading)
                self.downloadManager?.setDownloadDestination(self.download.id, destination: url)
                
                self.startFileSizeMonitoring()
                
                completionHandler(url, false)
            } else {
                print("Download cancelled by user")
                self.downloadManager?.updateDownloadState(self.download.id, state: .cancelled)
                completionHandler(URL(fileURLWithPath: "/tmp/cancelled"), false)
            }
        }
    }
    
    private func startProgressSimulation() {
        DispatchQueue.global(qos: .background).async {
            var progress: Double = 0.0
            let totalSteps = 20
            let stepDuration = 0.5
            
            for step in 1...totalSteps {
                progress = Double(step) / Double(totalSteps)
                
                DispatchQueue.main.async {
                    self.downloadManager?.updateDownloadProgress(
                        self.download.id,
                        progress: progress,
                        downloadedBytes: Int64(Double(self.download.fileSize ?? 0) * progress),
                        fileSize: self.download.fileSize
                    )
                }
                
                Thread.sleep(forTimeInterval: stepDuration)
            }
        }
    }
    
    private func startFileSizeMonitoring() {
        guard let destinationURL = self.download.destinationURL else { return }
        
        DispatchQueue.global(qos: .background).async {
            var lastSize: Int64 = 0
            
            while true {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        if fileSize > lastSize {
                            lastSize = fileSize
                            
                            let expectedSize = self.download.fileSize ?? 0
                            let progress = expectedSize > 0 ? Double(fileSize) / Double(expectedSize) : 0.0
                            let clampedProgress = min(progress, 1.0)
                            
                            DispatchQueue.main.async {
                                self.downloadManager?.updateDownloadProgress(
                                    self.download.id,
                                    progress: clampedProgress,
                                    downloadedBytes: fileSize,
                                    fileSize: expectedSize
                                )
                            }
                            
                            print("File size monitoring: \(clampedProgress * 100)% (\(fileSize) / \(expectedSize))")
                        }
                    }
                } catch {
                    print("Error monitoring file size: \(error)")
                }
                
                Thread.sleep(forTimeInterval: 0.5)
                
                if self.download.state == .completed || self.download.state == .failed {
                    break
                }
            }
        }
    }
    
    func download(_ download: WKDownload, didReceive response: URLResponse) {
        let fileSize = response.expectedContentLength
        print("Download started with file size: \(fileSize) bytes")
        downloadManager?.updateDownloadProgress(self.download.id, progress: 0.0, downloadedBytes: 0, fileSize: fileSize)
        downloadManager?.updateDownloadState(self.download.id, state: .downloading)
    }
    
    func download(_ download: WKDownload, didReceive bytes: UInt64) {
        let downloadedBytes = Int64(bytes)
        let progress = self.download.fileSize.map { Double(downloadedBytes) / Double($0) } ?? 0.0
        
        let clampedProgress = min(progress, 1.0)
        
        downloadManager?.updateDownloadProgress(self.download.id, progress: clampedProgress, downloadedBytes: downloadedBytes, fileSize: self.download.fileSize)
        
        print("Download progress: \(clampedProgress * 100)% (\(downloadedBytes) / \(self.download.fileSize ?? 0))")
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        print("Download finished: \(self.download.suggestedFilename)")
        downloadManager?.updateDownloadState(self.download.id, state: .completed)
    }
    
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        print("Download failed: \(self.download.suggestedFilename) - \(error.localizedDescription)")
        downloadManager?.updateDownloadState(self.download.id, state: .failed, error: error)
    }
    
    func downloadWillPerformHTTPRedirection(_ download: WKDownload, navigationResponse: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (URLRequest?) -> Void) {
        print("Download will perform HTTP redirection")
        decisionHandler(request)
    }
    
    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("Download received authentication challenge")
        completionHandler(.performDefaultHandling, nil)
    }
    
    public func download(_ download: WKDownload, didFinishDownloadingTo location: URL) {
        print("🔽 [DownloadManager] Download finished to: \(location.path)")
        // The download is already handled by downloadDidFinish, but we can add additional logic here if needed
    }
    
    public func download(_ download: WKDownload, didFailWithError error: Error) {
        print("🔽 [DownloadManager] Download failed: \(error.localizedDescription)")
        // The download is already handled by the existing didFailWithError method, but we can add additional logic here if needed
    }
}

