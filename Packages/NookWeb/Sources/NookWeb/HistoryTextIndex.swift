// Licensed under GPL-3.0. See LICENSE.
//
//  HistoryTextIndex.swift
//  Nook
//
//  Visited pages' text in an SQLite FTS5 file beside the history store, one row per URL.
//  Kept out of SwiftData so the shared store's schema stays put.
//

import Foundation
import OSLog
import SQLite3

public struct PageTextMatch: Sendable, Equatable {
    public let url: String
    public let title: String
    public let snippet: String
}

public actor HistoryTextIndex {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "HistoryTextIndex")
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public let fileURL: URL
    private var db: OpaquePointer?
    /// Set when FTS5 is missing or the file cannot be opened; the feature stays off this launch.
    private var unavailable = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Writes

    public func record(url: String, title: String, body: String, visitedAt: Date) {
        guard let db = open(create: true) else { return }
        let sql = """
            INSERT INTO pages(url, title, body, visitedAt) VALUES(?, ?, ?, ?)
            ON CONFLICT(url) DO UPDATE SET title = excluded.title, body = excluded.body, visitedAt = excluded.visitedAt
            """
        run(db, sql) { stmt in
            sqlite3_bind_text(stmt, 1, url, -1, Self.transient)
            sqlite3_bind_text(stmt, 2, title, -1, Self.transient)
            sqlite3_bind_text(stmt, 3, body, -1, Self.transient)
            sqlite3_bind_double(stmt, 4, visitedAt.timeIntervalSince1970)
        }
    }

    public func delete(url: String) {
        guard let db = open(create: false) else { return }
        run(db, "DELETE FROM pages WHERE url = ?") { sqlite3_bind_text($0, 1, url, -1, Self.transient) }
    }

    /// Drops every row whose URL is not in `urls`, so text never outlives its history row.
    public func retain(only urls: Set<String>) {
        guard let db = open(create: false) else { return }
        let stale = allURLs(db).subtracting(urls)
        guard !stale.isEmpty else { return }
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for url in stale {
            run(db, "DELETE FROM pages WHERE url = ?") { sqlite3_bind_text($0, 1, url, -1, Self.transient) }
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    /// Closes and removes the file.
    public func erase() {
        if let db { sqlite3_close_v2(db) }
        db = nil
        for suffix in ["", "-journal", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: fileURL.path + suffix))
        }
    }

    // MARK: - Search

    /// Pages whose title or text holds every word of `query` as a prefix, best bm25 first, then newest.
    public func search(_ query: String, limit: Int) -> [PageTextMatch] {
        guard limit > 0, let match = Self.matchExpression(for: query), let db = open(create: false) else { return [] }
        let sql = """
            SELECT p.url, p.title, snippet(page_fts, -1, '', '', '…', 12)
            FROM page_fts JOIN pages p ON p.rowid = page_fts.rowid
            WHERE page_fts MATCH ? ORDER BY bm25(page_fts), p.visitedAt DESC LIMIT ?
            """
        var results: [PageTextMatch] = []
        run(db, sql, bind: { stmt in
            sqlite3_bind_text(stmt, 1, match, -1, Self.transient)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }, row: { stmt in
            results.append(PageTextMatch(url: Self.text(stmt, 0), title: Self.text(stmt, 1), snippet: Self.text(stmt, 2)))
        })
        return results
    }

    /// Each word as a quoted prefix term, so no FTS5 operator or quote in the query can reach the parser.
    nonisolated static func matchExpression(for query: String) -> String? {
        let terms = query.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
        return terms.isEmpty ? nil : terms.joined(separator: " ")
    }

    // MARK: - SQLite

    private func open(create: Bool) -> OpaquePointer? {
        if let db { return db }
        guard !unavailable else { return nil }
        let fm = FileManager.default
        if !create, !fm.fileExists(atPath: fileURL.path) { return nil }
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            Self.logger.error("Page text index open failed: \(String(cString: sqlite3_errmsg(handle)), privacy: .public)")
            sqlite3_close_v2(handle)
            unavailable = true
            return nil
        }
        // External-content FTS5 over a URL-keyed table; the triggers keep the two in step.
        let schema = """
            PRAGMA secure_delete = ON;
            CREATE TABLE IF NOT EXISTS pages(url TEXT PRIMARY KEY, title TEXT, body TEXT, visitedAt REAL);
            CREATE VIRTUAL TABLE IF NOT EXISTS page_fts USING fts5(title, body, content='pages', content_rowid='rowid',
                tokenize='unicode61 remove_diacritics 2');
            CREATE TRIGGER IF NOT EXISTS pages_ai AFTER INSERT ON pages BEGIN
                INSERT INTO page_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
            END;
            CREATE TRIGGER IF NOT EXISTS pages_ad AFTER DELETE ON pages BEGIN
                INSERT INTO page_fts(page_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
            END;
            CREATE TRIGGER IF NOT EXISTS pages_au AFTER UPDATE ON pages BEGIN
                INSERT INTO page_fts(page_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
                INSERT INTO page_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
            END;
            """
        guard sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK else {
            Self.logger.error("Page text index unavailable (FTS5): \(String(cString: sqlite3_errmsg(handle)), privacy: .public)")
            sqlite3_close_v2(handle)
            unavailable = true
            return nil
        }
        db = handle
        return handle
    }

    private func allURLs(_ db: OpaquePointer) -> Set<String> {
        var urls = Set<String>()
        run(db, "SELECT url FROM pages", bind: { _ in }, row: { urls.insert(Self.text($0, 0)) })
        return urls
    }

    private func run(_ db: OpaquePointer, _ sql: String, bind: (OpaquePointer) -> Void) {
        run(db, sql, bind: bind, row: { _ in })
    }

    private func run(_ db: OpaquePointer, _ sql: String, bind: (OpaquePointer) -> Void, row: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            Self.logger.error("Page text index prepare failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { row(stmt); continue }
            if rc != SQLITE_DONE {
                Self.logger.error("Page text index step failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            }
            return
        }
    }

    private static func text(_ stmt: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
    }
}
