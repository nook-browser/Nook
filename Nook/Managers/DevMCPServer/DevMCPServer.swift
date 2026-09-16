//
//  DevMCPServer.swift
//  Nook
//
//  Debug-only MCP server so a coding agent can drive the running app during development.
//  Streamable HTTP (JSON responses only) on 127.0.0.1, bearer token from a 0600 file.
//
//  claude mcp add --transport http nook http://127.0.0.1:47823/mcp \
//    --header "Authorization: Bearer $(cat ~/Library/Application\ Support/com.baingurley.nook/dev-mcp-token)"
//

#if DEBUG
import AppKit
import Foundation
import Network
import OSLog
import WebKit

@MainActor
final class DevMCPServer {
    static let shared = DevMCPServer()
    static let port: NWEndpoint.Port = 47823

    nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "DevMCP")
    nonisolated private static let maxBody = 8 * 1024 * 1024

    private weak var browserManager: BrowserManager?
    private var listener: NWListener?
    private var token = ""
    private let queue = DispatchQueue(label: "com.baingurley.nook.devmcp")

    func start(browserManager: BrowserManager) {
        guard listener == nil else { return }
        self.browserManager = browserManager
        do {
            token = try Self.loadOrCreateToken()
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: Self.port)
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            listener.stateUpdateHandler = { state in
                Self.log.notice("listener \(String(describing: state), privacy: .public)")
            }
            listener.start(queue: queue)
            self.listener = listener
            installConsoleCapture()
        } catch {
            Self.log.error("start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadOrCreateToken() throws -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.baingurley.nook", isDirectory: true)
        let file = dir.appendingPathComponent("dev-mcp-token")
        if let existing = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count >= 32 {
            return existing
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fresh = UUID().uuidString + UUID().uuidString
        try Data(fresh.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return fresh
    }

    // MARK: - HTTP

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private nonisolated func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(buffer) {
                Task { @MainActor in
                    let (status, body) = await self.handle(request)
                    self.send(conn, status: status, body: body)
                }
            } else if error != nil || isComplete || buffer.count > Self.maxBody {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buffer)
            }
        }
    }

    private nonisolated func send(_ conn: NWConnection, status: Int, body: Data?) {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "Error"
        var head = "HTTP/1.1 \(status) \(reason)\r\nConnection: close\r\nContent-Length: \(body?.count ?? 0)\r\n"
        if body != nil { head += "Content-Type: application/json\r\n" }
        var out = Data((head + "\r\n").utf8)
        if let body { out.append(body) }
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func handle(_ req: HTTPRequest) async -> (Int, Data?) {
        // Web pages cannot reach us: they would send an Origin, and could not know the token.
        if let origin = req.headers["origin"], !origin.hasPrefix("http://127.0.0.1"), !origin.hasPrefix("http://localhost") {
            return (403, nil)
        }
        guard req.headers["authorization"] == "Bearer \(token)" else { return (401, nil) }
        guard req.path.hasPrefix("/mcp") else { return (404, nil) }
        switch req.method {
        case "POST": break
        case "DELETE": return (200, nil)
        default: return (405, nil)
        }
        guard let msg = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any] else {
            return (400, rpcError(id: NSNull(), code: -32700, message: "Parse error"))
        }
        guard let id = msg["id"] else { return (202, nil) } // notification
        let method = msg["method"] as? String ?? ""
        let params = msg["params"] as? [String: Any] ?? [:]

        let result: [String: Any]
        switch method {
        case "initialize":
            result = [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "nook-dev", "version": "1"],
                "instructions": "Drives the running Debug build of Nook. Page tools act on the selected tab of the active window."
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": Self.toolList]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            result = await callTool(name, args)
        default:
            return (200, rpcError(id: id, code: -32601, message: "Method not found: \(method)"))
        }
        return (200, try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result]))
    }

    private func rpcError(id: Any, code: Int, message: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    // MARK: - Tools

    private static let devTools: [AIToolDefinition] = [
        AIToolDefinition(
            name: "evaluate",
            description: "Run JavaScript as an async function body in the selected tab and return the JSON of its return value. Use `return` and `await` freely. world: 'page' (default) or 'isolated'.",
            parameters: ["type": "object", "properties": [
                "code": ["type": "string"],
                "world": ["type": "string", "enum": ["page", "isolated"]]
            ], "required": ["code"]]
        ),
        AIToolDefinition(
            name: "screenshot",
            description: "JPEG of the selected tab's visible page, at most maxWidth pixels wide (default 1200).",
            parameters: ["type": "object", "properties": ["maxWidth": ["type": "integer"]]]
        ),
        AIToolDefinition(
            name: "console",
            description: "Console messages, uncaught errors and failed resource loads (a blocked script or image shows here) captured in the selected tab's main frame since its last load. Tabs loaded before the server started need a reload. clear: true empties the buffer after reading.",
            parameters: ["type": "object", "properties": ["clear": ["type": "boolean"]]]
        ),
        AIToolDefinition(
            name: "reload",
            description: "Reload the selected tab and wait for the load to finish (timeout seconds, default 20).",
            parameters: ["type": "object", "properties": ["timeout": ["type": "number"]]]
        ),
        AIToolDefinition(
            name: "wait_for_load",
            description: "Wait until the selected tab stops loading (timeout seconds, default 20). Call after navigateToURL.",
            parameters: ["type": "object", "properties": ["timeout": ["type": "number"]]]
        ),
        AIToolDefinition(
            name: "blocker_status",
            description: "Content blocker state for the selected tab: enabled, whether this page is exempt, allowlisted host, blocked-request count, compiled rule lists.",
            parameters: ["type": "object", "properties": [:] as [String: Any]]
        ),
        AIToolDefinition(
            name: "set_blocking",
            description: "Turn ad blocking on or off for the selected tab's host (edits the persisted allowlist) and reload.",
            parameters: ["type": "object", "properties": ["enabled": ["type": "boolean"]], "required": ["enabled"]]
        ),
        AIToolDefinition(
            name: "check_urls",
            description: "Ask adblock-rust whether each URL would be blocked when requested from sourceURL (default: the selected tab's URL). type is an adblock request type: script, image, stylesheet, xmlhttprequest, sub_frame, media, font, ping, other. Needs 'Detailed blocked-request counts' on.",
            parameters: ["type": "object", "properties": [
                "urls": ["type": "array", "items": ["type": "string"]],
                "type": ["type": "string"],
                "sourceURL": ["type": "string"]
            ], "required": ["urls"]]
        ),
        AIToolDefinition(
            name: "user_scripts",
            description: "User scripts installed in the selected tab: first line, injection time, main frame only, length.",
            parameters: ["type": "object", "properties": [:] as [String: Any]]
        )
    ]

    private static let toolList: [[String: Any]] = (BrowserTools.allTools + devTools).map {
        ["name": $0.name, "description": $0.description, "inputSchema": $0.parameters]
    }

    private var window: BrowserWindowState? {
        guard let registry = browserManager?.windowRegistry else { return nil }
        return registry.activeWindow ?? registry.windows.values.first
    }

    private var session: PageSession? {
        guard let bm = browserManager, let window else { return nil }
        return bm.tabs.controllableSession(in: window)
    }

    private var webView: WKWebView? {
        guard let bm = browserManager, let window, let id = window.selectedItemID else { return nil }
        return bm.getWebView(for: id, in: window.id) ?? session?.webView
    }

    private func text(_ s: String, error: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": s]], "isError": error]
    }

    private func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else {
            return String(describing: value)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func callTool(_ name: String, _ args: [String: Any]) async -> [String: Any] {
        guard let bm = browserManager, let window else { return text("No browser window", error: true) }

        do {
            if BrowserTools.toolsByName[name] != nil {
                let executor = BrowserToolExecutor(browserManager: bm, windowState: window)
                executor.confirmationHandler = { _, _ in true } // the bearer token is the approval
                let r = try await executor.execute(AIToolCall(name: name, arguments: args))
                return text(r.content, error: r.isError)
            }

            switch name {
            case "evaluate":
                guard let wv = webView else { return text("No active tab", error: true) }
                let code = args["code"] as? String ?? ""
                let world: WKContentWorld = args["world"] as? String == "isolated" ? .defaultClient : .page
                // Serialize in the page so DOM nodes, undefined and cycles come back readable.
                let wrapped = """
                const __v = await (async () => { \(code)
                })();
                if (__v === undefined) return 'undefined';
                try { const s = JSON.stringify(__v, null, 2); return s === undefined ? String(__v) : s; }
                catch (e) { return String(__v); }
                """
                let result = try await wv.callAsyncJavaScript(wrapped, contentWorld: world)
                return text(result as? String ?? String(describing: result))

            case "screenshot":
                guard let wv = webView else { return text("No active tab", error: true) }
                let maxWidth = (args["maxWidth"] as? NSNumber)?.doubleValue ?? 1200
                let config = WKSnapshotConfiguration()
                // snapshotWidth is in points; the image comes back at the backing scale.
                let scale = wv.window?.backingScaleFactor ?? 2
                config.snapshotWidth = NSNumber(value: min(wv.bounds.width, maxWidth / scale))
                let image = try await wv.takeSnapshot(configuration: config)
                guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
                    return text("Snapshot encoding failed", error: true)
                }
                return ["content": [["type": "image", "data": jpeg.base64EncodedString(), "mimeType": "image/jpeg"]]]

            case "console":
                guard let wv = webView else { return text("No active tab", error: true) }
                let clear = args["clear"] as? Bool == true
                let result = try await wv.callAsyncJavaScript(
                    "const b = globalThis.__nookDevConsole; if (!b) return null; const out = JSON.stringify(b, null, 1); if (clear) b.length = 0; return out;",
                    arguments: ["clear": clear], contentWorld: .page
                )
                return text(result as? String ?? "No capture in this page. Reload it (the capture script installs at document start).")

            case "reload", "wait_for_load":
                guard let wv = webView else { return text("No active tab", error: true) }
                if name == "reload" { wv.reload() }
                let timeout = (args["timeout"] as? NSNumber)?.doubleValue ?? 20
                let deadline = Date().addingTimeInterval(timeout)
                // ponytail: 100 ms poll, debug-only and bounded by the timeout; use navigation delegate callbacks if this ever matters.
                if name == "reload" { try await Task.sleep(for: .milliseconds(150)) }
                while wv.isLoading, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
                return text(wv.isLoading ? "Still loading after \(timeout)s: \(wv.url?.absoluteString ?? "")" : "Loaded: \(wv.url?.absoluteString ?? "") | \(wv.title ?? "")", error: wv.isLoading)

            case "blocker_status":
                let cb = bm.contentBlockerManager
                let host = webView?.url?.host
                var status: [String: Any] = [
                    "enabled": cb.isEnabled,
                    "compiling": cb.isCompiling,
                    "hostAllowlisted": cb.isDomainAllowed(host),
                    "detailedCounts": cb.detailedCountsEnabled,
                    "host": host ?? ""
                ]
                if let s = session {
                    status["blockingApplied"] = cb.shouldApplyBlocking(to: s)
                    status["blockedRequestCount"] = s.blockedRequestCount
                    status["oauthFlow"] = s.isOAuthFlow
                    status["temporarilyDisabled"] = cb.isTemporarilyDisabled(tabId: s.itemID)
                }
                return text(json(status))

            case "set_blocking":
                guard let host = webView?.url?.host else { return text("Selected tab has no host", error: true) }
                let enabled = args["enabled"] as? Bool ?? true
                bm.contentBlockerManager.allowDomain(host, allowed: !enabled)
                return text("Blocking \(enabled ? "on" : "off") for \(host); reloading. Call wait_for_load next.")

            case "check_urls":
                let cb = bm.contentBlockerManager
                guard cb.detailedCountsEnabled else {
                    return text("Turn on Settings > Ad Blocker > Detailed blocked-request counts first.", error: true)
                }
                let urls = args["urls"] as? [String] ?? []
                let type = args["type"] as? String ?? "script"
                let source = args["sourceURL"] as? String ?? webView?.url?.absoluteString ?? ""
                var out: [String: Bool] = [:]
                for url in urls {
                    out[url] = await cb.requestStatsEngine.blockedCount(of: [(url, type)], sourceURL: source) > 0
                }
                return text(json(out))

            case "user_scripts":
                guard let wv = webView else { return text("No active tab", error: true) }
                let scripts = wv.configuration.userContentController.userScripts.map { s -> [String: Any] in
                    let first = s.source.prefix(while: { $0 != "\n" }).prefix(120)
                    return [
                        "firstLine": String(first),
                        "atStart": s.injectionTime == .atDocumentStart,
                        "mainFrameOnly": s.isForMainFrameOnly,
                        "length": s.source.count
                    ]
                }
                return text(json(scripts))

            default:
                return text("Unknown tool: \(name)", error: true)
            }
        } catch {
            return text("\(name) failed: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: - Console capture

    /// Buffers console output, uncaught errors and failed resource loads for the `console` tool.
    /// Added to the shared configuration, so it reaches tabs created (or reloaded) after start.
    private func installConsoleCapture() {
        let source = """
        // Nook Dev MCP console capture
        (function () {
          if (globalThis.__nookDevConsole) return;
          const buf = globalThis.__nookDevConsole = [];
          const MAX = 500;
          const push = (e) => { e.t = Math.round(performance.now()); buf.push(e); if (buf.length > MAX) buf.shift(); };
          const fmt = (a) => { try { return typeof a === 'string' ? a : (a instanceof Error ? a.stack || String(a) : JSON.stringify(a)); } catch (_) { return String(a); } };
          for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
            const orig = console[level];
            console[level] = function (...args) {
              try { push({ level, msg: args.map(fmt).join(' ').slice(0, 2000) }); } catch (_) {}
              return orig.apply(this, args);
            };
          }
          addEventListener('error', (ev) => {
            const el = ev.target;
            if (el && el !== window && el.tagName) {
              push({ level: 'loadError', tag: el.tagName.toLowerCase(), url: el.src || el.href || el.currentSrc || '' });
            } else {
              push({ level: 'uncaught', msg: String(ev.message), at: (ev.filename || '') + ':' + ev.lineno });
            }
          }, true);
          addEventListener('unhandledrejection', (ev) => push({ level: 'unhandledRejection', msg: fmt(ev.reason).slice(0, 2000) }));
        })();
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page)
        BrowserConfiguration.shared.webViewConfiguration.userContentController.addUserScript(script)
    }
}

// MARK: - Minimal HTTP/1.1 request parsing

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// Nil until the buffer holds the full head and a Content-Length body.
    init?(_ buffer: Data) {
        guard let split = buffer.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: buffer[..<split.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = split.upperBound
        guard buffer.count - bodyStart >= length else { return nil }
        method = String(start[0])
        path = String(start[1])
        self.headers = headers
        body = buffer.subdata(in: bodyStart..<(bodyStart + length))
    }
}
#endif
