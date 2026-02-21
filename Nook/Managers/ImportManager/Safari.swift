//
//  Safari.swift
//  Nook
//
//  Created by Maciek Bagiński on 20/02/2026.
//

import Foundation

// MARK: - Safari History JSON Models

struct SafariHistoryFile: Codable {
    let metadata: SafariMetadata
    let history: [SafariHistoryEntry]
}

struct SafariMetadata: Codable {
    let browser_name: String
    let browser_version: String
    let data_type: String
    let export_time_usec: Int64
    let schema_version: Int
}

struct SafariHistoryEntry: Codable {
    let url: String
    let time_usec: Int64
    let visit_count: Int
    let title: String?
    let destination_url: String?
    let destination_time_usec: Int64?
    let source_url: String?
    let source_time_usec: Int64?
    let latest_visit_was_http_get: Bool?
}

// MARK: - Safari Import Result Models

struct SafariImportResult {
    let bookmarks: [SafariBookmark]
    let history: [SafariImportHistoryEntry]
}

struct SafariBookmark {
    let title: String
    let url: String
    let folder: String?
}

struct SafariImportHistoryEntry {
    let url: String
    let title: String
    let visitDate: Date
    let visitCount: Int
}

// MARK: - Safari Export Validation

struct SafariExportContents {
    let directoryURL: URL
    let hasBookmarks: Bool
    let hasHistory: Bool
    let bookmarkCount: Int
    let historyCount: Int
}

func validateSafariExport(at directoryURL: URL) -> SafariExportContents? {
    let fm = FileManager.default

    let bookmarksURL = directoryURL.appendingPathComponent("Bookmarks.html")
    let historyURL = directoryURL.appendingPathComponent("History.json")

    let hasBookmarks = fm.fileExists(atPath: bookmarksURL.path)
    let hasHistory = fm.fileExists(atPath: historyURL.path)

    guard hasBookmarks || hasHistory else { return nil }

    if hasHistory {
        guard let data = try? Data(contentsOf: historyURL),
              let json = try? JSONDecoder().decode(SafariHistoryFile.self, from: data),
              json.metadata.browser_name == "Safari"
        else { return nil }

        let bookmarkCount = hasBookmarks ? countBookmarks(at: bookmarksURL) : 0

        return SafariExportContents(
            directoryURL: directoryURL,
            hasBookmarks: hasBookmarks,
            hasHistory: hasHistory,
            bookmarkCount: bookmarkCount,
            historyCount: json.history.count
        )
    }

    let bookmarkCount = hasBookmarks ? countBookmarks(at: bookmarksURL) : 0
    return SafariExportContents(
        directoryURL: directoryURL,
        hasBookmarks: hasBookmarks,
        hasHistory: hasHistory,
        bookmarkCount: bookmarkCount,
        historyCount: 0
    )
}

private func countBookmarks(at url: URL) -> Int {
    guard let html = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
    var count = 0
    var searchRange = html.startIndex..<html.endIndex
    while let range = html.range(of: "<DT><A HREF=", options: .caseInsensitive, range: searchRange) {
        count += 1
        searchRange = range.upperBound..<html.endIndex
    }
    return count
}

// MARK: - Parsers

func parseSafariExport(from directoryURL: URL, importBookmarks: Bool, importHistory: Bool) throws -> SafariImportResult {
    var bookmarks: [SafariBookmark] = []
    var history: [SafariImportHistoryEntry] = []

    if importBookmarks {
        let bookmarksURL = directoryURL.appendingPathComponent("Bookmarks.html")
        if FileManager.default.fileExists(atPath: bookmarksURL.path) {
            bookmarks = try parseSafariBookmarks(from: bookmarksURL)
        }
    }

    if importHistory {
        let historyURL = directoryURL.appendingPathComponent("History.json")
        if FileManager.default.fileExists(atPath: historyURL.path) {
            history = try parseSafariHistory(from: historyURL)
        }
    }

    return SafariImportResult(bookmarks: bookmarks, history: history)
}

func parseSafariBookmarks(from fileURL: URL) throws -> [SafariBookmark] {
    let html = try String(contentsOf: fileURL, encoding: .utf8)
    var bookmarks: [SafariBookmark] = []
    var currentFolder: String? = nil

    for line in html.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("<DT><H3") {
            if let startRange = trimmed.range(of: ">", range: trimmed.index(after: trimmed.startIndex)..<trimmed.endIndex),
               let endRange = trimmed.range(of: "</H3>", options: .caseInsensitive) {
                currentFolder = String(trimmed[startRange.upperBound..<endRange.lowerBound])
            }
        }

        if trimmed.hasPrefix("<DT><A HREF=") {
            if let hrefStart = trimmed.range(of: "HREF=\"", options: .caseInsensitive),
               let hrefEnd = trimmed.range(of: "\"", range: hrefStart.upperBound..<trimmed.endIndex),
               let titleStart = trimmed.range(of: ">", range: hrefEnd.upperBound..<trimmed.endIndex),
               let titleEnd = trimmed.range(of: "</A>", options: .caseInsensitive) {
                let url = String(trimmed[hrefStart.upperBound..<hrefEnd.lowerBound])
                let title = String(trimmed[titleStart.upperBound..<titleEnd.lowerBound])

                bookmarks.append(SafariBookmark(
                    title: title,
                    url: url,
                    folder: currentFolder
                ))
            }
        }

        if trimmed.hasPrefix("</DL>") {
            currentFolder = nil
        }
    }

    return bookmarks
}

func parseSafariHistory(from fileURL: URL) throws -> [SafariImportHistoryEntry] {
    let data = try Data(contentsOf: fileURL)
    let decoded = try JSONDecoder().decode(SafariHistoryFile.self, from: data)

    return decoded.history.compactMap { entry in
        guard let title = entry.title, !title.isEmpty else {
            guard let url = URL(string: entry.url),
                  (url.scheme == "http" || url.scheme == "https"),
                  !entry.url.contains("accounts.google.com"),
                  !entry.url.contains("auth0."),
                  !entry.url.contains("/oauth") else {
                return nil
            }
            let displayTitle = url.host ?? entry.url
            let date = Date(timeIntervalSince1970: Double(entry.time_usec) / 1_000_000)
            return SafariImportHistoryEntry(
                url: entry.url,
                title: displayTitle,
                visitDate: date,
                visitCount: entry.visit_count
            )
        }

        if entry.url.contains("accounts.google.com/") && entry.url.contains("oauth") { return nil }
        if entry.url.contains("auth0.") { return nil }

        let date = Date(timeIntervalSince1970: Double(entry.time_usec) / 1_000_000)

        return SafariImportHistoryEntry(
            url: entry.url,
            title: title,
            visitDate: date,
            visitCount: entry.visit_count
        )
    }
}
