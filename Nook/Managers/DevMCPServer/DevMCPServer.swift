// Licensed under GPL-3.0. See LICENSE.
//
//  DevMCPServer.swift
//  Nook
//
//  Debug-only MCP server so a coding agent can drive the running app during development.
//  Streamable HTTP (JSON responses only) on 127.0.0.1, bearer token from a 0600 file.
//
//  claude mcp add --transport http nook http://127.0.0.1:47823/mcp \
//    --header "Authorization: Bearer $(cat ~/Library/Application\ Support/com.gstudios.nook/dev-mcp-token)"
//

import AppKit
import Foundation
import Network
import OSLog
import WebKit
import NookBlocker
import NookWeb

@MainActor
final class DevMCPServer {
    static let shared = DevMCPServer()
    /// `-NookDevMCPPort 47900` moves the server so a second copy can run beside the installed app.
    static let port: NWEndpoint.Port = {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let override = (arguments["NookDevMCPPort"] as? String).flatMap { UInt16($0) }
        return override.flatMap { NWEndpoint.Port(rawValue: $0) } ?? 47823
    }()

    nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "DevMCP")
    nonisolated private static let maxBody = 8 * 1024 * 1024
    nonisolated private static let toolTimeout: Double = 30

    private weak var browserManager: BrowserManager?
    private var listener: NWListener?
    /// Last snapshot per page and selector, so the next call can answer with a diff.
    private var snapshots: [String: String] = [:]
    private var token = ""
    private let queue = DispatchQueue(label: "com.gstudios.nook.devmcp")

    /// Remember the browser and start only if the user has turned the server on.
    /// Off is the default: see NookSettingsService.browserControlServerEnabled.
    func configure(browserManager: BrowserManager, enabled: Bool) {
        self.browserManager = browserManager
        applyEnabledSetting(enabled)
    }

    /// Called when the setting changes, so the server starts and stops without a relaunch.
    func applyEnabledSetting(_ enabled: Bool) {
        guard enabled else { stop(); return }
        guard let browserManager else { return }   // configure() has not run yet
        start(browserManager: browserManager)
    }

    func stop() {
        guard listener != nil else { return }
        listener?.cancel()
        listener = nil
        Self.log.notice("listener stopped")
    }

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
        } catch {
            Self.log.error("start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadOrCreateToken() throws -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Nook", isDirectory: true)
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
        // Compare the parsed host, not a string prefix: http://localhost.attacker.example passed.
        if let origin = req.headers["origin"] {
            let host = URL(string: origin)?.host
            guard host == "127.0.0.1" || host == "localhost" || host == "::1" else { return (403, nil) }
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
                "instructions": "Drives the running Debug build of Nook. Page and tab tools act on the Agent space: a space in the person's window, made on first use, with the logins of the space they had open. Agent activity never changes the space they see; they open the Agent space to watch. Popups from its pages open as Agent space tabs. pick and selection use the person's active tab."
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": Self.toolList]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            // Counted here, not in callTool, so a call the deadline abandons stops the pulse.
            browserManager?.tabs.agentCallsInFlight += 1
            let called = await withTimeout(Self.toolTimeout, operation: { await self.callTool(name, args) })
            browserManager?.tabs.agentCallsInFlight -= 1
            guard let called else {
                return (200, rpcError(id: id, code: -32001, message: "Tool \(name) did not answer within \(Int(Self.toolTimeout))s"))
            }
            result = called
        default:
            return (200, rpcError(id: id, code: -32601, message: "Method not found: \(method)"))
        }
        return (200, try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result]))
    }

    /// A tool that never returns must not hold its connection open for ever, so
    /// every call races a deadline and nil means the deadline won. The losing work
    /// is cancelled but may not notice: `evaluateJavaScript` cannot be cancelled.
    private func withTimeout<T: Sendable>(_ seconds: Double, operation: @escaping @MainActor () async -> T) async -> T? {
        // Not a task group: a group waits for its children even after cancelAll(),
        // so an abandoned evaluateJavaScript would still hold the connection open
        // for as long as it took. These two tasks race and the loser is dropped.
        let latch = Latch()
        return await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
            // The deadline task is made first so the work task can cancel it: a tool that
            // answers in a millisecond otherwise leaves a sleeper on the main actor for the
            // full timeout, one per request.
            let deadline = Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                guard !latch.done else { return }
                latch.done = true
                latch.work?.cancel()
                cont.resume(returning: nil)
            }
            latch.work = Task { @MainActor in
                let value = await operation()
                guard !latch.done else { return }
                latch.done = true
                deadline.cancel()
                cont.resume(returning: value)
            }
        }
    }

    /// Whether the race above has already been decided, and the work task the deadline
    /// branch cancels (assigned after the deadline task is made, so it is passed this way).
    @MainActor private final class Latch {
        var done = false
        var work: Task<Void, Never>?
    }

    private func rpcError(id: Any, code: Int, message: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    // MARK: - Tools

    private static let devTools: [AIToolDefinition] = [
        AIToolDefinition(
            name: "evaluate",
            description: "Run JavaScript as an async function body in the selected tab and return the JSON of its return value. Use `return` and `await` freely. world: 'page' (default) or 'isolated'. saveTo: a path relative to ~/Downloads/Nook MCP; the result is written there instead of returned (a string as is, anything else as JSON), and append: true adds it to the end of the file.",
            parameters: ["type": "object", "properties": [
                "code": ["type": "string"],
                "world": ["type": "string", "enum": ["page", "isolated"]],
                "saveTo": ["type": "string"],
                "append": ["type": "boolean"]
            ], "required": ["code"]]
        ),
        AIToolDefinition(
            name: "download",
            description: "Save https URLs (plain http fails App Transport Security) as files in dir, a path relative to ~/Downloads/Nook MCP, fetched with the selected tab's cookies and user agent and its URL as Referer. urls: a list, and/or urlsFile: a file under the same root with one URL per line (write one with evaluate saveTo). Files are named <hash>-<last path component>; ones already there are skipped. Each URL adds a line to dir/manifest.jsonl (url, file, status ok|exists|http|error|tooLarge, httpStatus, contentType, bytes). Answers when all are done or after 20 s; the rest keep downloading, so read the manifest for the outcome.",
            parameters: ["type": "object", "properties": [
                "urls": ["type": "array", "items": ["type": "string"]],
                "urlsFile": ["type": "string"],
                "dir": ["type": "string"]
            ], "required": ["dir"]]
        ),
        AIToolDefinition(
            name: "screenshot",
            description: "JPEG of the selected tab's visible page, at most maxWidth pixels wide (default 1200).",
            parameters: ["type": "object", "properties": ["maxWidth": ["type": "integer"]]]
        ),
        AIToolDefinition(
            name: "console",
            description: "Console messages, uncaught errors and failed resource loads from every frame of the selected tab since its last load. Pass the returned cursor as since to get only newer entries. clear: true empties the log after reading.",
            parameters: ["type": "object", "properties": ["since": ["type": "integer"], "clear": ["type": "boolean"]]]
        ),
        AIToolDefinition(
            name: "blocker_log",
            description: "What the content blocker did to the selected tab since its last load: loads and cookies blocked, loads made HTTPS, navigations rewritten by $removeparam or urlskip, plus the page's procedural cosmetic rules and scriptlet names. Pass the returned cursor as since for only newer actions. The rule list that blocked a load is not known.",
            parameters: ["type": "object", "properties": ["since": ["type": "integer"]]]
        ),
        AIToolDefinition(
            name: "snapshot",
            description: "Accessibility outline of the selected tab under a CSS selector (the body when omitted): one line per role with its name and state, generic wrappers flattened, hidden content left out. A repeat call for the same page and selector returns only the lines that changed; pass full: true for the whole outline. maxNodes defaults to 300, maxDepth to 12.",
            parameters: ["type": "object", "properties": [
                "selector": ["type": "string"], "full": ["type": "boolean"],
                "maxNodes": ["type": "integer"], "maxDepth": ["type": "integer"],
            ]]
        ),
        AIToolDefinition(
            name: "perf",
            description: "The selected tab's load timings (TTFB, FCP, LCP with its element, DOMContentLoaded, load) and Interaction to Next Paint with the worst interaction's target and its input delay, processing and presentation delay, plus the WebContent process's memory footprint. WebKit cannot measure CLS. Interactions only count after the person clicks or types.",
            parameters: ["type": "object", "properties": [:] as [String: Any]]
        ),
        AIToolDefinition(
            name: "pick",
            description: "Start the element picker in the selected tab and wait up to 25 seconds for the person to click an element, then return it as selection does. Use it to ask the person which element they mean.",
            parameters: ["type": "object", "properties": [:] as [String: Any]]
        ),
        AIToolDefinition(
            name: "selection",
            description: "What the person last handed to the agent from the selected tab: an element picked with Pick Element (selector, role, HTML, styles that differ from defaults, React or Vue component names and source when the page exposes them, recent errors and failed requests) or a console line or request sent with Send to Agent. Markdown, plus the element's screenshot when there is one.",
            parameters: ["type": "object", "properties": [:] as [String: Any]]
        ),
        AIToolDefinition(
            name: "network",
            description: "Requests from the selected tab since its last load: fetch and XHR with status, plus every other load from Resource Timing. Pass the returned cursor as since for only new or updated entries. detail: true adds headers and bodies for fetch and XHR.",
            parameters: ["type": "object", "properties": ["since": ["type": "integer"], "detail": ["type": "boolean"]]]
        ),
        AIToolDefinition(
            name: "reload",
            description: "Reload the selected tab and wait for the load to finish (timeout seconds, default 20, capped at 25 by the server's own deadline).",
            parameters: ["type": "object", "properties": ["timeout": ["type": "number"]]]
        ),
        AIToolDefinition(
            name: "wait_for_load",
            description: "Wait until the selected tab stops loading (timeout seconds, default 20, capped at 25 by the server's own deadline). Call after navigateToURL.",
            parameters: ["type": "object", "properties": ["timeout": ["type": "number"]]]
        ),
        AIToolDefinition(
            name: "blocker_status",
            description: "Content blocker state for the selected tab: enabled, whether this page is exempt, allowlisted host, compiled rule lists.",
            parameters: ["type": "object", "properties": [:] as [String: Any]]
        ),
        AIToolDefinition(
            name: "set_blocking",
            description: "Turn ad blocking on or off for the selected tab's host (edits the persisted allowlist) and reload.",
            parameters: ["type": "object", "properties": ["enabled": ["type": "boolean"]], "required": ["enabled"]]
        ),
        AIToolDefinition(
            name: "check_urls",
            description: "Ask adblock-rust whether each URL would be blocked when requested from sourceURL (default: the selected tab's URL). type is an adblock request type: script, image, stylesheet, xmlhttprequest, sub_frame, media, font, ping, other.",
            parameters: ["type": "object", "properties": [
                "urls": ["type": "array", "items": ["type": "string"]],
                "type": ["type": "string"],
                "sourceURL": ["type": "string"]
            ], "required": ["urls"]]
        ),
        AIToolDefinition(
            name: "closeTabs",
            description: "Close Agent space tabs. indices: positions from getTabList. Or regular: true to delete every tab and folder in its regular tabs section, leaving favorites and pinned tabs.",
            parameters: ["type": "object", "properties": [
                "indices": ["type": "array", "items": ["type": "integer"]],
                "regular": ["type": "boolean"]
            ]]
        ),
        AIToolDefinition(
            name: "pinTab",
            description: "Pin the tab at a getTabList index to the Agent space's pinned section.",
            parameters: ["type": "object", "properties": ["index": ["type": "integer"]], "required": ["index"]]
        ),
        AIToolDefinition(
            name: "user_scripts",
            description: "User scripts installed in the selected tab: first line, injection time, main frame only, length.",
            parameters: ["type": "object", "properties": [:] as [String: Any]]
        ),
        AIToolDefinition(
            name: "pages",
            description: "Every live page in every window: url, WebContent pid, loaded, on screen, in a window, document.visibilityState.",
            parameters: ["type": "object", "properties": [:] as [String: Any]]
        ),
        AIToolDefinition(
            name: "clear_page_cache",
            description: "Drop the back/forward page cache of every live page that is not on screen (hidden: false for all). Returns how many views were cleared.",
            parameters: ["type": "object", "properties": ["all": ["type": "boolean"]]]
        )
    ]

    /// `executeJavaScript` is not advertised: over this server it is only an old name for
    /// `evaluate` (see callTool), and the chat's description of it is wrong for that behaviour.
    /// The alias stays so an agent registered against the old name keeps working.
    private static let toolList: [[String: Any]] = (BrowserTools.allTools.filter { $0.name != "executeJavaScript" } + devTools).map {
        ["name": $0.name, "description": $0.description, "inputSchema": $0.parameters]
    }

    /// About the person's own page, so they act on the active window's tab, not the Agent space.
    private static let humanTools: Set<String> = ["pick", "selection"]
    /// Need no Agent page, so they neither create the Agent space nor load its tab.
    private static let readOnlyTools: Set<String> = ["pages", "clear_page_cache", "check_urls", "getTabList"]

    private var humanWindow: BrowserWindowState? {
        guard let registry = browserManager?.windowRegistry else { return nil }
        return registry.activeWindow ?? registry.windows.values.first
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

    /// The server does not enforce the advertised schemas, and `intValue` would turn 1.9 into tab 1.
    private static func wholeNumber(_ number: NSNumber) -> Int? {
        let value = number.doubleValue
        return value == value.rounded() && abs(value) < 1e9 ? Int(value) : nil
    }

    private func callTool(_ rawName: String, _ args: [String: Any]) async -> [String: Any] {
        // The chat's executeJavaScript evaluates an expression, so `return` (which
        // every agent writes) is a syntax error. Here it is another name for
        // `evaluate`, which runs the code as an async function body.
        let name = rawName == "executeJavaScript" ? "evaluate" : rawName
        // Everything but pick and selection works in the Agent space, whatever the window shows,
        // through a regular window: a private one holds no Agent space. No window is ever opened.
        let forPerson = Self.humanTools.contains(name)
        let active = humanWindow
        guard let bm = browserManager,
              let window = forPerson ? active : (active?.privateTree == nil ? active : bm.tabs.regularWindows.first)
        else { return text("No browser window", error: true) }
        // Tools that only read never create the Agent space; with none yet, it has no tabs.
        let agentSpace = forPerson ? nil
            : Self.readOnlyTools.contains(name) ? bm.tabs.agentSpaceID : bm.tabs.ensureAgentSpace(loginsFrom: window)
        if agentSpace == nil, !forPerson {
            if name == "getTabList" { return text("No tabs available") }
            if !Self.readOnlyTools.contains(name) { return text("No space to borrow logins from", error: true) }
        }
        let space = forPerson ? window.spaceID : agentSpace
        let order = space.map(bm.tabs.displayOrder(inSpace:)) ?? []

        do {
            if BrowserTools.toolsByName[name] != nil {
                let executor = BrowserToolExecutor(browserManager: bm, windowState: window, agentSpace: agentSpace)
                let r = try await executor.execute(AIToolCall(name: name, arguments: args))
                return text(r.content, error: r.isError)
            }
            // The agent's page, loaded and hosted once for this call; a read-only tool loads nothing.
            let agentView: WKWebView? = forPerson || Self.readOnlyTools.contains(name) || agentSpace == nil
                ? nil : try bm.agentWebView()
            var webView: WKWebView? {
                if !forPerson { return agentView }
                guard let id = window.selectedItemID else { return nil }
                return bm.getWebView(for: id, in: window.id) ?? bm.tabs.controllableSession(in: window)?.webView
            }
            var session: PageSession? {
                guard !forPerson else { return bm.tabs.controllableSession(in: window) }
                return agentView == nil ? nil : bm.tabs.agentItem.flatMap(bm.tabs.session(for:))
            }

            switch name {
            case "evaluate":
                guard let wv = webView else { return text("No active tab", error: true) }
                let code = args["code"] as? String ?? ""
                let world: WKContentWorld = args["world"] as? String == "isolated" ? .defaultClient : .page
                var saveURL: URL?
                if let saveTo = args["saveTo"] as? String {
                    guard let url = DevMCPFiles.resolve(saveTo) else {
                        return text("saveTo must be a relative path inside \(DevMCPFiles.root.path)", error: true)
                    }
                    saveURL = url
                }
                // Serialize in the page so DOM nodes, undefined and cycles come back readable.
                // A string being saved is written as is, not as a JSON string literal.
                let wrapped = """
                const __v = await (async () => { \(code)
                })();
                if (__v === undefined) return 'undefined';
                if (\(saveURL != nil) && typeof __v === 'string') return __v;
                try { const s = JSON.stringify(__v, null, 2); return s === undefined ? String(__v) : s; }
                catch (e) { return String(__v); }
                """
                let result = try await wv.callAsyncJavaScript(wrapped, contentWorld: world)
                let output = result as? String ?? String(describing: result)
                guard let saveURL else { return text(output) }
                try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = Data(output.utf8)
                if args["append"] as? Bool == true, let handle = try? FileHandle(forWritingTo: saveURL) {
                    defer { try? handle.close() }
                    handle.seekToEndOfFile()
                    handle.write(data)
                } else {
                    try data.write(to: saveURL)
                }
                return text("Saved \(data.count) bytes to \(saveURL.path)")

            case "download":
                guard let wv = webView else { return text("No active tab", error: true) }
                guard let dir = (args["dir"] as? String).flatMap({ DevMCPFiles.resolve($0) }) else {
                    return text("dir must be a relative path inside \(DevMCPFiles.root.path)", error: true)
                }
                var list = args["urls"] as? [String] ?? []
                if let file = args["urlsFile"] as? String {
                    guard let source = DevMCPFiles.resolve(file), let body = try? String(contentsOf: source, encoding: .utf8) else {
                        return text("urlsFile must be a readable file inside \(DevMCPFiles.root.path)", error: true)
                    }
                    list += body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                }
                var seen = Set<URL>()
                let urls = list.compactMap(URL.init(string:)).filter { ["http", "https"].contains($0.scheme) && seen.insert($0).inserted }
                guard !urls.isEmpty else { return text("No http(s) URLs given", error: true) }
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let job = DevMCPDownload(
                    urls: urls, dir: dir,
                    cookies: await wv.configuration.websiteDataStore.httpCookieStore.allCookies(),
                    userAgent: (try? await wv.evaluateJavaScript("navigator.userAgent")) as? String,
                    referer: wv.url?.absoluteString
                )
                Task.detached { await job.run() }
                let deadline = Date().addingTimeInterval(20)
                // ponytail: 250 ms poll bounded by 20 s; the job itself keeps running past it.
                while !job.progress.finished, Date() < deadline { try await Task.sleep(for: .milliseconds(250)) }
                let progress = job.progress
                let done = progress.counts.values.reduce(0, +)
                return text(json([
                    "dir": dir.path, "manifest": dir.appendingPathComponent("manifest.jsonl").path,
                    "total": urls.count, "done": done, "finished": progress.finished, "counts": progress.counts
                ]))

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

            case "pick":
                guard let session, session.devCapture != nil else {
                    return text("No capture for this tab. Reload it: it loaded before Developer Mode turned on.", error: true)
                }
                let before = session.devCapture?.lastPick?.date
                session.startDevPicker()
                let deadline = Date().addingTimeInterval(25)
                // ponytail: 200 ms poll bounded by 25 s; a continuation on onDevPick if this ever matters.
                while Date() < deadline, session.devCapture?.lastPick?.date == before {
                    try await Task.sleep(for: .milliseconds(200))
                }
                guard session.devCapture?.lastPick?.date != before else {
                    return text("No element picked within 25 seconds.", error: true)
                }
                return await callTool("selection", [:])

            case "selection":
                guard let pick = session?.devCapture?.lastPick else {
                    return text("Nothing picked in this tab. Ask the person to press Cmd+Shift+X and click an element.", error: true)
                }
                var content: [[String: Any]] = [["type": "text", "text": pick.markdown]]
                if let path = pick.imagePath, let png = FileManager.default.contents(atPath: path) {
                    content.append(["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"])
                }
                return ["content": content, "isError": false]

            case "snapshot":
                guard let session else { return text("No active tab", error: true) }
                let selector = args["selector"] as? String ?? ""
                let maxNodes = (args["maxNodes"] as? NSNumber).flatMap(Self.wholeNumber).map { min(max($0, 1), 2_000) } ?? 300
                let maxDepth = (args["maxDepth"] as? NSNumber).flatMap(Self.wholeNumber).map { min(max($0, 1), 40) } ?? 12
                guard let outline = try await session.devSnapshot(selector, maxDepth: maxDepth, maxNodes: maxNodes) else {
                    return text(session.devCapture == nil ? "Developer Mode is off." : "Nothing matches \(selector).", error: true)
                }
                let key = "\(session.itemID)|\(session.url.absoluteString)|\(selector)"
                defer { snapshots[key] = outline }
                if args["full"] as? Bool != true, let previous = snapshots[key] {
                    return text(DevHandoff.snapshotDiff(old: previous, new: outline))
                }
                return text(outline)

            case "perf":
                guard let session, let capture = session.devCapture else {
                    return text("No capture for this tab. Reload it: it loaded before Developer Mode turned on.", error: true)
                }
                var summary = capture.perf.summary
                var usage = rusage_info_v6()
                let pid = session.webProcessID
                let ok = withUnsafeMutablePointer(to: &usage) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
                }
                if pid > 0, ok == 0 { summary += "\nWebContent memory footprint: \(usage.ri_phys_footprint / 1_048_576) MB" }
                if !capture.perf.advice.isEmpty { summary += "\n\n" + capture.perf.advice.joined(separator: "\n") }
                return text(summary)

            case "blocker_log":
                guard let capture = session?.devCapture else {
                    return text("No capture for this tab. Reload it: it loaded before Developer Mode turned on.", error: true)
                }
                let since = (args["since"] as? NSNumber).flatMap(Self.wholeNumber) ?? 0
                let actions = capture.blocked.since(since).map { e -> [String: Any] in
                    var o: [String: Any] = ["action": e.action.rawValue, "url": e.url]
                    if let t = e.target { o["target"] = t }
                    return o
                }
                var result: [String: Any] = ["actions": actions, "cursor": capture.blocked.lastSeq,
                                             "dropped": capture.blocked.dropped,
                                             "blockedByHost": capture.blockedHosts.map { [$0.host: $0.count] }]
                if let rules = capture.pageRules {
                    result["scriptlets"] = rules.scriptlets
                    result["scriptletBytes"] = rules.scriptletBytes
                    result["procedural"] = rules.procedural
                }
                return text(json(result))

            case "console", "network":
                guard let capture = session?.devCapture else {
                    return text("No capture for this tab. Reload it: it loaded before Developer Mode turned on.", error: true)
                }
                let since = (args["since"] as? NSNumber).flatMap(Self.wholeNumber) ?? 0
                if name == "console" {
                    let entries = capture.console.since(since).map { e -> [String: Any] in
                        var o: [String: Any] = ["level": e.level, "msg": e.message]
                        if let at = e.location { o["at"] = at }
                        if let frame = e.frameURL { o["frame"] = frame }
                        if e.repeatCount > 1 { o["repeat"] = e.repeatCount }
                        return o
                    }
                    let result: [String: Any] = ["entries": entries, "cursor": capture.console.lastSeq,
                                                 "dropped": capture.droppedMessages + capture.console.dropped]
                    if args["clear"] as? Bool == true { capture.clearConsole() }
                    return text(json(result))
                }
                let entries = capture.network.since(since).map { e -> [String: Any] in
                    var o: [String: Any] = ["kind": e.kind, "method": e.method, "url": e.url, "state": e.state.rawValue]
                    if let v = e.status { o["status"] = v }
                    if let v = e.duration { o["ms"] = Int(v.rounded()) }
                    if let v = e.size { o["size"] = v }
                    if let v = e.error { o["error"] = v }
                    if args["detail"] as? Bool == true, e.hasDetail {
                        o["requestHeaders"] = e.requestHeaders
                        o["responseHeaders"] = e.responseHeaders
                        if let b = e.requestBody { o["requestBody"] = b }
                        if let b = e.responseBody { o["responseBody"] = b }
                    }
                    return o
                }
                return text(json(["entries": entries, "cursor": capture.network.lastSeq, "dropped": capture.network.dropped]))

            case "reload", "wait_for_load":
                guard let wv = webView else { return text("No active tab", error: true) }
                if name == "reload" { wv.reload() }
                // Clamped below the outer deadline: an uncapped timeout: 60 would be cut off
                // by withTimeout at 30s as a confusing -32001 instead of this tool's own answer.
                let timeout = min((args["timeout"] as? NSNumber)?.doubleValue ?? 20, Self.toolTimeout - 5)
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
                    "host": host ?? ""
                ]
                if let s = session {
                    status["blockingApplied"] = cb.shouldApplyBlocking(to: s)
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
                let engine = bm.contentBlockerManager.advancedRulesEngine.engine
                let urls = args["urls"] as? [String] ?? []
                let type = args["type"] as? String ?? "script"
                let source = args["sourceURL"] as? String ?? webView?.url?.absoluteString ?? ""
                var out: [String: Bool] = [:]
                for url in urls {
                    out[url] = engine.matches(url: url, sourceURL: source, type: type)
                }
                return text(json(out))

            case "closeTabs":
                if args["regular"] as? Bool == true {
                    guard let spaceID = space else { return text("Window has no space", error: true) }
                    let roots = bm.tabs.children(of: .tabs(spaceID: spaceID))
                    for item in roots { bm.tabs.remove(item.id) }
                    return text("Removed \(roots.count) items from the regular tabs section")
                }
                let indices = (args["indices"] as? [NSNumber] ?? []).compactMap(Self.wholeNumber)
                guard !indices.isEmpty, indices.count == (args["indices"] as? [Any])?.count,
                      indices.allSatisfy(order.indices.contains) else {
                    return text("indices must be positions from getTabList (0-\(order.count - 1))", error: true)
                }
                bm.tabs.close(indices.map { order[$0] })
                return text("Closed \(indices.count) tabs")

            case "pinTab":
                guard let index = (args["index"] as? NSNumber).flatMap(Self.wholeNumber), order.indices.contains(index),
                      let spaceID = space else { return text("index must be a position from getTabList", error: true) }
                bm.tabs.pin(order[index], to: .pinned(spaceID: spaceID))
                return text("Pinned: \(bm.tabs.item(order[index])?.displayTitle ?? "")")

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

            case "pages":
                var pages: [[String: Any]] = []
                for page in bm.tabs.sessions {
                    var entry: [String: Any] = [
                        "url": page.url.absoluteString,
                        "loaded": !page.isUnloaded,
                        "onScreen": bm.tabs.isOnScreen(page.itemID)
                    ]
                    if let wv = page.webView {
                        entry["pid"] = wv.nookWebProcessIdentifier
                        entry["inWindow"] = wv.window != nil
                        entry["visibility"] = (try? await wv.evaluateJavaScript("document.visibilityState")) as? String ?? ""
                    }
                    pages.append(entry)
                }
                return text(json(pages))

            case "clear_page_cache":
                let all = args["all"] as? Bool ?? false
                let views = bm.tabs.sessions.filter { !$0.isUnloaded && (all || !bm.tabs.isOnScreen($0.itemID)) }
                views.forEach { $0.clearPageCache() }
                return text("Cleared \(views.count)")

            default:
                return text("Unknown tool: \(name)", error: true)
            }
        } catch {
            return text("\(name) failed: \(error.localizedDescription)", error: true)
        }
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
        // A negative length would build an inverted range below and trap before the token check.
        let length = max(0, Int(headers["content-length"] ?? "0") ?? 0)
        let bodyStart = split.upperBound
        guard buffer.count - bodyStart >= length else { return nil }
        method = String(start[0])
        path = String(start[1])
        self.headers = headers
        body = buffer.subdata(in: bodyStart..<(bodyStart + length))
    }
}

private extension WKWebView {
    /// `_webProcessIdentifier`: the pid of the WebContent process behind this view, 0 when it has none.
    var nookWebProcessIdentifier: Int32 {
        let selector = NSSelectorFromString("_webProcessIdentifier")
        guard responds(to: selector) else { return 0 }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Int32
        return unsafeBitCast(method(for: selector), to: Getter.self)(self, selector)
    }
}
