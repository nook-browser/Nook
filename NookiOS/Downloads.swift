// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  Downloads.swift
//  NookiOS
//
//  WKDownload straight into the app's Documents directory, which Files shows
//  because Info.plist sets UIFileSharingEnabled. The Mac's DownloadManager,
//  with its panel and its resume data, does not come along.
//

import Foundation
import WebKit
import OSLog

final class IOSDownload: NSObject, WKDownloadDelegate {
    private let logger = Logger(subsystem: "com.gstudios.nook", category: "Downloads")
    private let onFinish: @MainActor (IOSDownload) -> Void

    init(onFinish: @escaping @MainActor (IOSDownload) -> Void) {
        self.onFinish = onFinish
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        completionHandler(Self.destination(for: suggestedFilename))
    }

    func downloadDidFinish(_ download: WKDownload) {
        logger.notice("download finished")
        finish()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        logger.error("download failed: \(error.localizedDescription, privacy: .public)")
        finish()
    }

    private func finish() {
        Task { @MainActor in onFinish(self) }
    }

    /// A free path in Documents. WKDownload refuses a destination that exists.
    static func destination(for suggestedFilename: String) -> URL {
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var target = documents.appendingPathComponent(name)
        var index = 1
        while FileManager.default.fileExists(atPath: target.path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            target = documents.appendingPathComponent(candidate)
            index += 1
        }
        return target
    }
}
