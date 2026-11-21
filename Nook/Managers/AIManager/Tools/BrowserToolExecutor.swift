// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserToolExecutor.swift
//  Nook
//
//  Executes browser tool calls using BrowserManager and WebView APIs
//

import Foundation
import OSLog
import WebKit
import NookTabsCore
import NookWeb

@MainActor
class BrowserToolExecutor {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "BrowserToolExecutor")

    weak var browserManager: BrowserManager?
    weak var windowState: BrowserWindowState?
    /// DevMCP's Agent space: tools act on its tabs instead of what the window shows.
    let agentSpace: UUID?

    init(browserManager: BrowserManager? = nil, windowState: BrowserWindowState? = nil, agentSpace: UUID? = nil) {
        self.browserManager = browserManager
        self.windowState = windowState
        self.agentSpace = agentSpace
    }

    // MARK: - Tool Definitions

    func availableToolDefinitions(enabledTools: Set<String>) -> [AIToolDefinition] {
        BrowserTools.allTools.filter { enabledTools.contains($0.name) }
    }

    /// Callback for requesting user confirmation before executing dangerous tools.
    /// Set by AIService to route through the standard approval UI.
    var confirmationHandler: ((_ toolName: String, _ args: [String: Any]) async -> Bool)?

    // MARK: - Execute Tool Call

    func execute(_ toolCall: AIToolCall) async throws -> AIToolResult {
        guard let browserManager = browserManager,
              let windowState = windowState else {
            return AIToolResult(toolCallId: toolCall.id, toolName: toolCall.name, content: "Browser not available", isError: true)
        }

        // On a tab Look It Up opened to act on, no script runs at all, asked or not.
        if toolCall.name == "executeJavaScript", let webView = getWebView(browserManager: browserManager, windowState: windowState),
           let refusal = GuardedTools.refusal(tool: toolCall.name, label: nil, guarded: isGuarded(webView, browserManager)) {
            return AIToolResult(toolCallId: toolCall.id, toolName: toolCall.name, content: refusal, isError: true)
        }

        // SECURITY: executeJavaScript ALWAYS requires user confirmation regardless of execution mode,
        // because it can run arbitrary code on the current page.
        if toolCall.name == "executeJavaScript" {
            if let handler = confirmationHandler {
                let approved = await handler(toolCall.name, toolCall.arguments)
                if !approved {
                    Self.log.warning("User denied executeJavaScript execution")
                    return AIToolResult(toolCallId: toolCall.id, toolName: toolCall.name, content: "User denied execution of executeJavaScript.", isError: true)
                }
            } else {
                Self.log.error("executeJavaScript called without a confirmation handler — denying by default")
                return AIToolResult(toolCallId: toolCall.id, toolName: toolCall.name, content: "executeJavaScript requires user confirmation but no confirmation handler is available.", isError: true)
            }
        }

        let result: String

        switch toolCall.name {
        case "navigateToURL":
            result = try await executeNavigateToURL(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "readPageContent":
            result = try await executeReadPageContent(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "clickElement":
            result = try await executeClickElement(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "fillField":
            result = try await executeFillField(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "getInteractiveElements":
            result = try await executeGetInteractiveElements(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "extractStructuredData":
            result = try await executeExtractStructuredData(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "summarizePage":
            result = try await executeSummarizePage(browserManager: browserManager, windowState: windowState)
        case "searchInPage":
            result = try await executeSearchInPage(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "getTabList":
            result = executeGetTabList(browserManager: browserManager, windowState: windowState)
        case "switchTab":
            result = try executeSwitchTab(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "createTab":
            result = try executeCreateTab(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "getSelectedText":
            result = try await executeGetSelectedText(browserManager: browserManager, windowState: windowState)
        case "executeJavaScript":
            result = try await executeJavaScript(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        default:
            return AIToolResult(toolCallId: toolCall.id, toolName: toolCall.name, content: "Unknown tool: \(toolCall.name)", isError: true)
        }

        return AIToolResult(toolCallId: toolCall.id, toolName: toolCall.name, content: result)
    }

    // MARK: - Tool Implementations

    private func tabTitle(_ itemID: UUID, in tabs: TabsController) -> String {
        if let custom = tabs.item(itemID)?.customTitle, !custom.isEmpty { return custom }
        return tabs.session(for: itemID)?.title ?? tabs.item(itemID)?.displayTitle ?? ""
    }

    private func getWebView(browserManager: BrowserManager, windowState: BrowserWindowState) -> WKWebView? {
        if agentSpace != nil { return (try? browserManager.agentWebView()) ?? nil }
        guard let itemID = windowState.selectedItemID else { return nil }
        return browserManager.getWebView(for: itemID, in: windowState.id)
    }

    private func tabOrder(_ tabs: TabsController, _ windowState: BrowserWindowState) -> [UUID] {
        agentSpace.map(tabs.displayOrder(inSpace:)) ?? tabs.displayOrder(in: windowState)
    }

    /// A new selected tab: in the Agent space when there is one, without showing it. Opened
    /// while the tools' tab is guarded, it is guarded too.
    @discardableResult
    private func openTab(_ url: URL, _ tabs: TabsController, _ windowState: BrowserWindowState) -> UUID? {
        let from = agentSpace != nil ? tabs.agentItem : windowState.selectedItemID
        let opened = tabs.open(url: url, in: windowState, placement: .newTab, parent: agentSpace.map { .tabs(spaceID: $0) })
        if let opened, let from, tabs.session(for: from)?.guardsCommits == true { tabs.markGuarded(opened) }
        return opened
    }

    /// JSON-encodes a string for interpolation into a script. `JSONSerialization` raises an
    /// ObjC `NSInvalidArgumentException` for a bare string at the top level unless
    /// `.fragmentsAllowed` is set, and neither `try` nor `try?` catches an ObjC exception:
    /// it unwinds through the Swift async frames, leaves the main thread's executor tracking
    /// pointing at a dead stack frame, and the next `MainActor.assumeIsolated` anywhere in the
    /// app segfaults in `swift_getObjectType`.
    private func jsLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
        return literal
    }

    /// Only web URLs. A file: URL would load with read access to its directory, and the
    /// read tools never prompt, so a page could have a local file read and sent elsewhere.
    private func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func executeNavigateToURL(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let urlString = args["url"] as? String,
              let url = webURL(urlString) else {
            return "Invalid URL: only http and https URLs are allowed"
        }

        let newTab = args["newTab"] as? Bool ?? false
        let tabs = browserManager.tabs
        if agentSpace != nil {
            if !newTab, let id = tabs.agentItem, let session = tabs.ensureSession(for: id) {
                tabs.select(id, in: windowState)
                session.load(url)
            } else {
                openTab(url, tabs, windowState)
            }
            return "Navigated to \(urlString)\(newTab ? " in new tab" : "")"
        }

        guard (newTab ? openTab(url, tabs, windowState) : tabs.open(url: url, in: windowState, placement: .replaceCurrent)) != nil else {
            return "No active tab"
        }

        return "Navigated to \(urlString)\(newTab ? " in new tab" : "")"
    }

    private func executeReadPageContent(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }

        let maxLength = args["maxLength"] as? Int ?? 8000
        let selector = args["selector"] as? String

        let script: String
        if let selector = selector {
            let selectorJSON = jsLiteral(selector)
            script = """
            (function() {
                const el = document.querySelector(\(selectorJSON));
                if (!el) return { error: 'Element not found' };
                return {
                    title: document.title,
                    url: window.location.href,
                    content: el.innerText.substring(0, \(maxLength))
                };
            })();
            """
        } else {
            script = """
            (function() {
                const clone = document.body.cloneNode(true);
                clone.querySelectorAll('script, style, noscript').forEach(el => el.remove());
                let text = clone.innerText || clone.textContent || '';
                text = text.replace(/\\s+/g, ' ').trim();
                if (text.length > \(maxLength)) text = text.substring(0, \(maxLength)) + '...';
                return { title: document.title, url: window.location.href, content: text };
            })();
            """
        }

        let result = try await webView.evaluateJavaScript(script)
        if let dict = result as? [String: Any] {
            if let error = dict["error"] as? String {
                return "Error: \(error)"
            }
            let title = dict["title"] as? String ?? ""
            let url = dict["url"] as? String ?? ""
            let content = dict["content"] as? String ?? ""
            return "Title: \(title)\nURL: \(url)\n\n\(content)"
        }

        return "Failed to read page content"
    }

    /// Whether a tool's page is one Look It Up opened to act on (`PageSession.guardsCommits`).
    private func isGuarded(_ webView: WKWebView, _ browserManager: BrowserManager) -> Bool {
        browserManager.tabs.session(for: webView)?.guardsCommits == true
    }

    /// Runs a click or fill script. On a guarded page the script first only names its target, and
    /// acts on a second pass when that name commits the person to nothing and is still the same.
    private func act(_ tool: String, in webView: WKWebView, guarded: Bool, script: (_ dryRun: Bool, _ expected: String?) -> String) async throws -> String {
        var expected: String?
        if guarded {
            let found = try await webView.evaluateJavaScript(script(true, nil)) as? [String: Any]
            if let message = found?["message"] as? String { return message }
            let label = found?["secret"] as? Bool == true ? nil : found?["label"] as? String
            if let refusal = GuardedTools.refusal(tool: tool, label: label, guarded: true) { return refusal }
            expected = label
        }
        let done = try await webView.evaluateJavaScript(script(false, expected)) as? [String: Any]
        if done?["changed"] as? Bool == true, let refusal = GuardedTools.refusal(tool: tool, label: nil, guarded: true) { return refusal }
        return done?["message"] as? String ?? "Done"
    }

    private func executeClickElement(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }
        // Support clicking by CSS selector OR by visible text
        let selector = (args["selector"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let text = (args["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard selector != nil || text != nil else {
            return "Provide either 'selector' (CSS) or 'text' (visible text) to identify the element"
        }
        return try await act("clickElement", in: webView, guarded: isGuarded(webView, browserManager)) { dryRun, expected in
            """
            (function() {
                const sel = \(selector.map(jsLiteral) ?? "null");
                const query = \(text.map { jsLiteral($0.lowercased()) } ?? "null");
                const expected = \(expected.map(jsLiteral) ?? "null");
                let el = null;
                if (sel !== null) {
                    el = document.querySelector(sel);
                    if (!el) return { message: 'Element not found: ' + sel };
                } else {
                    const candidates = document.querySelectorAll('a, button, input[type="submit"], input[type="button"], [role="button"], [onclick], [tabindex]');
                    let bestScore = Infinity;
                    for (const candidate of candidates) {
                        if (candidate.getClientRects().length === 0 && candidate.style.display !== 'contents') continue;
                        const label = (candidate.textContent || candidate.value || candidate.getAttribute('aria-label') || candidate.getAttribute('title') || '').trim();
                        const lower = label.toLowerCase();
                        if (lower === query) {
                            el = candidate;
                            break;
                        }
                        if (lower.includes(query) && label.length < bestScore) {
                            el = candidate;
                            bestScore = label.length;
                        }
                    }
                    if (!el) return { message: 'No clickable element found matching: ' + query };
                }
                // Everything the control could be called by, and the control it sits in: a click on
                // the amount inside a Pay button presses Pay.
                const owner = el.closest('a, button, input, select, label, [role="button"], [role="link"], [onclick]') || el;
                const label = [owner, el].flatMap(part => [part.getAttribute('aria-label'), part.textContent, part.value, part.getAttribute('title')])
                    .filter(part => typeof part === 'string' && part.trim()).join(' ').replace(/\\s+/g, ' ').trim().slice(0, 600);
                if (\(dryRun)) return { label: label };
                if (expected !== null && label !== expected) return { changed: true };
                el.scrollIntoView({block: 'center'});
                el.click();
                return { message: (sel !== null ? 'Clicked element: ' : 'Clicked: ') + (el.textContent || el.value || '').substring(0, 100).trim() };
            })();
            """
        }
    }

    /// Types into the field whose label, placeholder or name holds `label`: the shortest match.
    private func executeFillField(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }
        guard let label = args["label"] as? String, !label.isEmpty, let text = args["text"] as? String else {
            return "Provide the field's 'label' and the 'text' to type"
        }
        return try await act("fillField", in: webView, guarded: isGuarded(webView, browserManager)) { dryRun, expected in
            """
            (function() {
                const query = \(jsLiteral(label.lowercased()));
                const text = \(jsLiteral(text));
                const expected = \(expected.map(jsLiteral) ?? "null");
                const nameOf = field => [field.getAttribute('aria-label'), field.labels && field.labels[0] && field.labels[0].innerText,
                                         field.getAttribute('placeholder'), field.getAttribute('name')]
                    .filter(part => typeof part === 'string' && part.trim()).join(' ').replace(/\\s+/g, ' ').trim().slice(0, 300);
                let el = null;
                let bestScore = Infinity;
                for (const field of document.querySelectorAll('input, textarea, select')) {
                    if (['hidden', 'submit', 'button', 'reset', 'image', 'checkbox', 'radio', 'file'].includes(field.type)) continue;
                    if (field.disabled || field.readOnly || field.getClientRects().length === 0) continue;
                    const name = nameOf(field);
                    if (name.toLowerCase().includes(query) && name.length < bestScore) {
                        el = field;
                        bestScore = name.length;
                    }
                }
                if (!el) return { message: 'No field found matching: ' + query };
                const name = nameOf(el);
                const secret = el.type === 'password' || /cc-|password|one-time-code/.test(el.getAttribute('autocomplete') || '');
                if (\(dryRun)) return { label: name, secret: secret };
                if (expected !== null && name !== expected) return { changed: true };
                el.scrollIntoView({block: 'center'});
                el.focus();
                if (el.tagName === 'SELECT') {
                    const wanted = text.trim().toLowerCase();
                    const option = [...el.options].find(o => o.text.trim().toLowerCase() === wanted || o.value.toLowerCase() === wanted);
                    if (!option) return { message: 'No option matching: ' + text };
                    el.value = option.value;
                } else {
                    // A framework watches the element's own setter, so the prototype's is called.
                    const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
                    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
                }
                el.dispatchEvent(new Event('input', {bubbles: true}));
                el.dispatchEvent(new Event('change', {bubbles: true}));
                return { message: 'Filled: ' + name.substring(0, 100) };
            })();
            """
        }
    }

    private func executeGetInteractiveElements(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }

        let filter = args["filter"] as? String ?? ""
        let limit = args["limit"] as? Int ?? 50
        let filterJSON = jsLiteral(filter)

        let script = """
        (function() {
            const filter = \(filterJSON).toLowerCase();
            const limit = \(limit);
            const selectors = 'a[href], button, input, select, textarea, [role="button"], [role="link"], [role="menuitem"], [onclick], [tabindex]';
            const elements = document.querySelectorAll(selectors);
            const results = [];

            for (const el of elements) {
                if (results.length >= limit) break;
                if (el.getClientRects().length === 0 && el.style.display !== 'contents' && !el.closest('label')) continue;

                const tag = el.tagName.toLowerCase();
                const type = el.getAttribute('type') || '';
                const text = (el.textContent || '').trim().substring(0, 80);
                const value = el.value || '';
                const ariaLabel = el.getAttribute('aria-label') || '';
                const placeholder = el.getAttribute('placeholder') || '';
                const href = el.getAttribute('href') || '';
                const role = el.getAttribute('role') || '';
                const name = el.getAttribute('name') || '';
                const id = el.id || '';
                const classes = el.className && typeof el.className === 'string' ? el.className.split(' ').slice(0, 3).join('.') : '';

                const label = text || ariaLabel || placeholder || value;
                if (filter && !label.toLowerCase().includes(filter) && !ariaLabel.toLowerCase().includes(filter) && !placeholder.toLowerCase().includes(filter)) continue;
                if (!label && tag === 'input' && type === 'hidden') continue;

                let selector = '';
                if (id) selector = '#' + CSS.escape(id);
                else if (name) selector = tag + '[name="' + name + '"]';
                else if (ariaLabel) selector = tag + '[aria-label="' + ariaLabel.replace(/"/g, '\\\\"') + '"]';
                else if (classes) selector = tag + '.' + classes.split('.').map(c => CSS.escape(c.trim())).filter(c => c).join('.');

                const entry = { tag, text: text.substring(0, 60) };
                if (type) entry.type = type;
                if (href) entry.href = href.substring(0, 100);
                if (ariaLabel) entry.ariaLabel = ariaLabel;
                if (placeholder) entry.placeholder = placeholder;
                if (selector) entry.selector = selector;
                if (role) entry.role = role;

                results.push(entry);
            }
            return JSON.stringify(results);
        })();
        """

        let result = try await webView.evaluateJavaScript(script)
        if let jsonString = result as? String {
            return jsonString
        }
        return "[]"
    }

    private func executeExtractStructuredData(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let type = args["type"] as? String else {
            return "Missing type parameter"
        }

        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }

        let script: String
        switch type {
        case "schema_org":
            script = """
            (function() {
                const scripts = document.querySelectorAll('script[type="application/ld+json"]');
                const data = [];
                scripts.forEach(s => { try { data.push(JSON.parse(s.textContent)); } catch(e) {} });
                return JSON.stringify(data, null, 2);
            })();
            """
        case "open_graph":
            script = """
            (function() {
                const og = {};
                document.querySelectorAll('meta[property^="og:"]').forEach(m => {
                    og[m.getAttribute('property')] = m.getAttribute('content');
                });
                return JSON.stringify(og, null, 2);
            })();
            """
        case "meta":
            script = """
            (function() {
                const meta = {};
                document.querySelectorAll('meta[name], meta[property]').forEach(m => {
                    const key = m.getAttribute('name') || m.getAttribute('property');
                    meta[key] = m.getAttribute('content');
                });
                return JSON.stringify(meta, null, 2);
            })();
            """
        case "custom":
            guard let selectors = args["selectors"] as? [String] else {
                return "Missing selectors for custom extraction"
            }
            let selectorsJSON = (try? String(data: JSONSerialization.data(withJSONObject: selectors), encoding: .utf8)) ?? "[]"
            script = """
            (function() {
                const selectors = \(selectorsJSON);
                const results = {};
                selectors.forEach(s => {
                    const els = document.querySelectorAll(s);
                    results[s] = Array.from(els).map(e => e.innerText.trim()).filter(t => t);
                });
                return JSON.stringify(results, null, 2);
            })();
            """
        default:
            return "Unknown extraction type: \(type)"
        }

        let result = try await webView.evaluateJavaScript(script)
        return result as? String ?? "No data found"
    }

    private func executeSummarizePage(browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }

        let script = """
        (function() {
            const clone = document.body.cloneNode(true);
            clone.querySelectorAll('script, style, noscript, nav, footer, header').forEach(el => el.remove());
            let text = clone.innerText || clone.textContent || '';
            text = text.replace(/\\s+/g, ' ').trim();
            if (text.length > 16000) text = text.substring(0, 16000) + '...';
            return { title: document.title, url: window.location.href, content: text, length: text.length };
        })();
        """

        let result = try await webView.evaluateJavaScript(script)
        if let dict = result as? [String: Any] {
            let title = dict["title"] as? String ?? ""
            let url = dict["url"] as? String ?? ""
            let content = dict["content"] as? String ?? ""
            return "Title: \(title)\nURL: \(url)\n\n\(content)"
        }

        return "Failed to read page"
    }

    private func executeSearchInPage(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let query = args["query"] as? String else {
            return "Missing query parameter"
        }

        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }

        // The query goes in as an argument. Interpolating it meant JSON-encoding a
        // bare String, which JSONSerialization rejects as an invalid top-level type
        // by raising an ObjC exception rather than returning an error.
        let script = """
        const text = document.body.innerText;
        const needle = query.toLowerCase();
        const hay = text.toLowerCase();
        const matches = [];
        let idx = needle ? hay.indexOf(needle) : -1;
        while (idx !== -1 && matches.length < 10) {
            const start = Math.max(0, idx - 50);
            const end = Math.min(text.length, idx + needle.length + 50);
            matches.push({ index: idx, context: text.substring(start, end) });
            idx = hay.indexOf(needle, idx + needle.length);
        }
        return JSON.stringify({ count: matches.length, matches: matches });
        """

        let result = try await webView.callAsyncJavaScript(script, arguments: ["query": query], contentWorld: .page)
        return result as? String ?? "No matches found"
    }

    private func executeGetTabList(browserManager: BrowserManager, windowState: BrowserWindowState) -> String {
        let controller = browserManager.tabs
        let order = tabOrder(controller, windowState)
        guard !order.isEmpty else {
            return "No tabs available"
        }

        var tabList: [[String: Any]] = []
        for (index, itemID) in order.enumerated() {
            tabList.append([
                "index": index,
                "title": tabTitle(itemID, in: controller),
                "url": (controller.session(for: itemID)?.url ?? controller.item(itemID)?.url)?.absoluteString ?? "",
                "isActive": itemID == (agentSpace != nil ? controller.agentItem : windowState.selectedItemID)
            ])
        }

        let data = try? JSONSerialization.data(withJSONObject: tabList, options: .prettyPrinted)
        return String(data: data ?? Data(), encoding: .utf8) ?? "[]"
    }

    private func executeSwitchTab(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) throws -> String {
        guard let index = args["index"] as? Int else {
            return "Missing index parameter"
        }

        let controller = browserManager.tabs
        let order = tabOrder(controller, windowState)
        guard !order.isEmpty else {
            return "No tabs available"
        }
        guard order.indices.contains(index) else {
            return "Tab index \(index) out of range (0-\(order.count - 1))"
        }

        controller.select(order[index], in: windowState)
        return "Switched to tab: \(tabTitle(order[index], in: controller))"
    }

    private func executeCreateTab(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) throws -> String {
        if let urlString = args["url"] as? String, !urlString.isEmpty {
            guard let url = webURL(urlString) else {
                return "Invalid URL: only http and https URLs are allowed"
            }
            openTab(url, browserManager.tabs, windowState)
            return "Created new tab with URL: \(urlString)"
        }

        openTab(TabsController.homeURL, browserManager.tabs, windowState)

        return "Created new empty tab"
    }

    private func executeGetSelectedText(browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }

        let script = "window.getSelection().toString();"
        let result = try await webView.evaluateJavaScript(script)
        let text = result as? String ?? ""
        return text.isEmpty ? "No text selected" : text
    }

    private func executeJavaScript(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let code = args["code"] as? String else {
            return "Missing code parameter"
        }

        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }

        let result = try await webView.evaluateJavaScript(code)
        if let result = result {
            return String(describing: result)
        }
        return "JavaScript executed (no return value)"
    }
}
