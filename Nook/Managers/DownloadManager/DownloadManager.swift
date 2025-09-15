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

// MARK: - Download Model
@Observable
public class Download: Identifiable {
    public let id: UUID
    let download: WKDownload
    let originalURL: URL
    let suggestedFilename: String
    var destinationURL: URL?
    var progress: Double
    var state: DownloadState
    var error: Error?
    var fileSize: Int64?
    var downloadedBytes: Int64
    var icon: NSImage?
    var startDate: Date
    var estimatedTimeRemaining: TimeInterval?
    
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
    
    private func getIconForFile(_ filename: String) -> NSImage {
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        
        switch fileExtension {
        case "pdf":
            return NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage()
        case "doc", "docx":
            return NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
        case "xls", "xlsx":
            return NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil) ?? NSImage()
        case "ppt", "pptx":
            return NSImage(systemSymbolName: "chart.bar", accessibilityDescription: nil) ?? NSImage()
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff":
            return NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage()
        case "mp4", "avi", "mov", "wmv", "flv":
            return NSImage(systemSymbolName: "video", accessibilityDescription: nil) ?? NSImage()
        case "mp3", "wav", "aac", "flac":
            return NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage()
        case "zip", "rar", "7z", "tar", "gz":
            return NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil) ?? NSImage()
        case "txt", "rtf":
            return NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage()
        case "html", "htm":
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
        default:
            return NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
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
    
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
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
}

