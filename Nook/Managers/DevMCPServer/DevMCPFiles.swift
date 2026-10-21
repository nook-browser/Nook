// Licensed under GPL-3.0. See LICENSE.
//
//  DevMCPFiles.swift
//  Nook
//
//  Where DevMCP's evaluate saveTo and download tools may write (only under ~/Downloads/Nook MCP),
//  file names for downloaded URLs, and which of the page's cookies a download sends.
//  Foundation only, so scripts/tests/DevMCPFilesCheck.swift can compile it directly.
//

import Foundation

enum DevMCPFiles {
    static let root = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nook MCP", isDirectory: true)

    /// `relative` under `root`, or nil when it is empty, absolute, or climbs out through `..` or a symlink.
    static func resolve(_ relative: String, root: URL = root) -> URL? {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.hasPrefix("~") else { return nil }
        let base = realPath(root.standardizedFileURL)
        let url = realPath(base.appendingPathComponent(relative).standardizedFileURL)
        return url.path.hasPrefix(base.path + "/") ? url : nil
    }

    /// `resolvingSymlinksInPath` leaves a path alone when its last part doesn't exist yet,
    /// so resolve the deepest existing ancestor and put the rest back on.
    private static func realPath(_ url: URL) -> URL {
        var existing = url, rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return rest.reduce(existing.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
    }

    /// A short hash of the URL (so two `image.jpg`s don't collide) plus its last path component made safe;
    /// the extension comes from the content type when the URL has none.
    static func fileName(for url: URL, contentType: String?) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        var name = String(url.lastPathComponent.unicodeScalars.filter { allowed.contains($0) }.prefix(80).map(Character.init))
        if name.isEmpty || name == "." || name == ".." { name = "file" }
        if !name.contains("."), let ext = contentType.flatMap(extensionFor) { name += "." + ext }
        return hash(url.absoluteString) + "-" + name
    }

    static func extensionFor(_ contentType: String) -> String? {
        let type = contentType.split(separator: ";")[0].trimmingCharacters(in: .whitespaces).lowercased()
        return ["image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif", "image/avif": "avif",
                "image/svg+xml": "svg", "application/pdf": "pdf", "application/json": "json", "text/html": "html",
                "text/plain": "txt", "video/mp4": "mp4"][type]
    }

    /// FNV-1a, 8 hex digits: stable across launches, unlike `hashValue`.
    static func hash(_ s: String) -> String {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return String(format: "%08x", h)
    }

    /// The cookies a browser would send to `url`: domain and path match, secure ones only over https, unexpired.
    static func cookies(_ all: [HTTPCookie], for url: URL, now: Date = Date()) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        return all.filter { c in
            let domain = c.domain.lowercased()
            let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let domainOK = host == bare || (domain.hasPrefix(".") && host.hasSuffix("." + bare))
            let cp = c.path.isEmpty ? "/" : c.path
            let pathOK = path == cp || path.hasPrefix(cp.hasSuffix("/") ? cp : cp + "/")
            return domainOK && pathOK && (!c.isSecure || url.scheme == "https") && (c.expiresDate.map { $0 > now } ?? true)
        }
    }
}

/// The download tool's job: fetches `urls` into `dir` six at a time with the page's cookies,
/// user agent and Referer, appending one `manifest.jsonl` line per URL. Outlives the tool call.
final class DevMCPDownload: @unchecked Sendable {
    static let maxBytes = 100 * 1024 * 1024

    let urls: [URL]
    let dir: URL
    private let cookies: [HTTPCookie]
    private let userAgent: String?
    private let referer: String?
    private let session: URLSession
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var finished = false

    init(urls: [URL], dir: URL, cookies: [HTTPCookie], userAgent: String?, referer: String?) {
        self.urls = urls
        self.dir = dir
        self.cookies = cookies
        self.userAgent = userAgent
        self.referer = referer
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
    }

    /// Status counts so far (ok, exists, http, error, tooLarge) and whether every URL is done.
    var progress: (counts: [String: Int], finished: Bool) { lock.withLock { (counts, finished) } }

    func run() async {
        await withTaskGroup(of: Void.self) { group in
            var pending = urls.makeIterator()
            for _ in 0..<6 { if let url = pending.next() { group.addTask { await self.fetch(url) } } }
            while await group.next() != nil {
                if let url = pending.next() { group.addTask { await self.fetch(url) } }
            }
        }
        session.finishTasksAndInvalidate()
        lock.withLock { finished = true }
    }

    private func fetch(_ url: URL) async {
        var row: [String: Any] = ["url": url.absoluteString]
        let guess = dir.appendingPathComponent(DevMCPFiles.fileName(for: url, contentType: nil))
        if !url.pathExtension.isEmpty, FileManager.default.fileExists(atPath: guess.path) {
            row["status"] = "exists"; row["file"] = guess.lastPathComponent
            return record(row)
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (field, value) in HTTPCookie.requestHeaderFields(with: DevMCPFiles.cookies(cookies, for: url)) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let type = http?.value(forHTTPHeaderField: "Content-Type")
            row["httpStatus"] = http?.statusCode
            row["contentType"] = type
            if let code = http?.statusCode, !(200..<300).contains(code) {
                row["status"] = "http"
            } else if data.count > Self.maxBytes {
                row["status"] = "tooLarge"
            } else {
                let file = dir.appendingPathComponent(DevMCPFiles.fileName(for: url, contentType: type))
                if FileManager.default.fileExists(atPath: file.path) {
                    row["status"] = "exists"
                } else {
                    try data.write(to: file)
                    row["status"] = "ok"
                    row["bytes"] = data.count
                }
                row["file"] = file.lastPathComponent
            }
        } catch {
            row["status"] = "error"
            row["error"] = error.localizedDescription
        }
        record(row)
    }

    private func record(_ row: [String: Any]) {
        guard var line = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        lock.withLock {
            counts[row["status"] as? String ?? "error", default: 0] += 1
            let manifest = dir.appendingPathComponent("manifest.jsonl")
            if let handle = try? FileHandle(forWritingTo: manifest) {
                handle.seekToEndOfFile(); handle.write(line); try? handle.close()
            } else {
                try? line.write(to: manifest)
            }
        }
    }
}
