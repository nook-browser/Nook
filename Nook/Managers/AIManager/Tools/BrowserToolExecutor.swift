//
//  BrowserToolExecutor.swift
//  Nook
//
//  Executes browser tool calls using BrowserManager and WebView APIs
//

import Foundation
import OSLog
import WebKit

@MainActor
class BrowserToolExecutor {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "BrowserToolExecutor")

    weak var browserManager: BrowserManager?
    weak var windowState: BrowserWindowState?

    init(browserManager: BrowserManager? = nil, windowState: BrowserWindowState? = nil) {
        self.browserManager = browserManager
        self.windowState = windowState
    }

    // MARK: - Tool Definitions

    func availableToolDefinitions(enabledTools: Set<String>) -> [AIToolDefinition] {
        BrowserTools.allTools.filter { enabledTools.contains($0.name) }
    }

    // MARK: - Execute Tool Call

    func execute(_ toolCall: AIToolCall) async throws -> AIToolResult {
        guard let browserManager = browserManager,
              let windowState = windowState else {
            return AIToolResult(toolCallId: toolCall.id, content: "Browser not available", isError: true)
        }

        let result: String

        switch toolCall.name {
        case "navigateToURL":
            result = try await executeNavigateToURL(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "readPageContent":
            result = try await executeReadPageContent(toolCall.arguments, browserManager: browserManager, windowState: windowState)
        case "clickElement":
            result = try await executeClickElement(toolCall.arguments, browserManager: browserManager, windowState: windowState)
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
            return AIToolResult(toolCallId: toolCall.id, content: "Unknown tool: \(toolCall.name)", isError: true)
        }

        return AIToolResult(toolCallId: toolCall.id, content: result)
    }

    // MARK: - Tool Implementations

    private func getWebView(browserManager: BrowserManager, windowState: BrowserWindowState) -> WKWebView? {
        guard let currentTab = browserManager.currentTab(for: windowState) else { return nil }
        return browserManager.getWebView(for: currentTab.id, in: windowState.id)
    }

    private func executeNavigateToURL(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let urlString = args["url"] as? String,
              let url = URL(string: urlString) else {
            return "Invalid URL"
        }

        let newTab = args["newTab"] as? Bool ?? false

        if newTab {
            browserManager.createNewTab(in: windowState)
            // Give the new tab a moment to initialize
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }

        let request = URLRequest(url: url)
        webView.load(request)

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
            script = """
            (function() {
                const el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
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

    private func executeClickElement(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }

        // Support clicking by CSS selector OR by visible text
        if let selector = args["selector"] as? String, !selector.isEmpty {
            let escapedSelector = selector.replacingOccurrences(of: "'", with: "\\'")
            let script = """
            (function() {
                const el = document.querySelector('\(escapedSelector)');
                if (!el) return 'Element not found: \(escapedSelector)';
                el.scrollIntoView({block: 'center'});
                el.click();
                return 'Clicked element: ' + (el.textContent || '').substring(0, 100).trim();
            })();
            """
            let result = try await webView.evaluateJavaScript(script)
            return result as? String ?? "Click executed"
        } else if let text = args["text"] as? String, !text.isEmpty {
            let escapedText = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            let script = """
            (function() {
                const query = '\(escapedText)'.toLowerCase();
                const candidates = document.querySelectorAll('a, button, input[type="submit"], input[type="button"], [role="button"], [onclick], [tabindex]');
                let best = null;
                let bestScore = Infinity;
                for (const el of candidates) {
                    if (el.offsetParent === null && el.style.display !== 'contents') continue;
                    const label = (el.textContent || el.value || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim();
                    const lower = label.toLowerCase();
                    if (lower === query) {
                        best = el;
                        bestScore = 0;
                        break;
                    }
                    if (lower.includes(query) && label.length < bestScore) {
                        best = el;
                        bestScore = label.length;
                    }
                }
                if (!best) return 'No clickable element found matching: ' + query;
                best.scrollIntoView({block: 'center'});
                best.click();
                return 'Clicked: ' + (best.textContent || best.value || '').substring(0, 100).trim();
            })();
            """
            let result = try await webView.evaluateJavaScript(script)
            return result as? String ?? "Click executed"
        } else {
            return "Provide either 'selector' (CSS) or 'text' (visible text) to identify the element"
        }
    }

    private func executeGetInteractiveElements(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) async throws -> String {
        guard let webView = getWebView(browserManager: browserManager, windowState: windowState) else {
            return "No active tab"
        }

        let filter = args["filter"] as? String ?? ""
        let limit = args["limit"] as? Int ?? 50
        let escapedFilter = filter
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let script = """
        (function() {
            const filter = '\(escapedFilter)'.toLowerCase();
            const limit = \(limit);
            const selectors = 'a[href], button, input, select, textarea, [role="button"], [role="link"], [role="menuitem"], [onclick], [tabindex]';
            const elements = document.querySelectorAll(selectors);
            const results = [];

            for (const el of elements) {
                if (results.length >= limit) break;
                if (el.offsetParent === null && el.style.display !== 'contents' && !el.closest('label')) continue;

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

        let escapedQuery = query.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\\", with: "\\\\")
        let script = """
        (function() {
            const text = document.body.innerText;
            const query = '\(escapedQuery)'.toLowerCase();
            const matches = [];
            let idx = text.toLowerCase().indexOf(query);
            while (idx !== -1 && matches.length < 10) {
                const start = Math.max(0, idx - 50);
                const end = Math.min(text.length, idx + query.length + 50);
                matches.push({ index: idx, context: text.substring(start, end) });
                idx = text.toLowerCase().indexOf(query, idx + 1);
            }
            return JSON.stringify({ count: matches.length, matches: matches });
        })();
        """

        let result = try await webView.evaluateJavaScript(script)
        return result as? String ?? "No matches found"
    }

    private func executeGetTabList(browserManager: BrowserManager, windowState: BrowserWindowState) -> String {
        guard let tabManager = windowState.tabManager,
              let space = windowState.currentSpace else {
            return "No tabs available"
        }

        let tabs = tabManager.tabs(in: space)
        var tabList: [[String: Any]] = []
        for (index, tab) in tabs.enumerated() {
            tabList.append([
                "index": index,
                "title": tab.name,
                "url": tab.url.absoluteString,
                "isActive": tab.id == windowState.currentTabId
            ])
        }

        let data = try? JSONSerialization.data(withJSONObject: tabList, options: .prettyPrinted)
        return String(data: data ?? Data(), encoding: .utf8) ?? "[]"
    }

    private func executeSwitchTab(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) throws -> String {
        guard let index = args["index"] as? Int else {
            return "Missing index parameter"
        }

        guard let tabManager = windowState.tabManager,
              let space = windowState.currentSpace else {
            return "No tabs available"
        }

        let tabs = tabManager.tabs(in: space)
        guard index >= 0, index < tabs.count else {
            return "Tab index \(index) out of range (0-\(tabs.count - 1))"
        }

        let tab = tabs[index]
        tabManager.setActiveTab(tab)
        return "Switched to tab: \(tab.name)"
    }

    private func executeCreateTab(_ args: [String: Any], browserManager: BrowserManager, windowState: BrowserWindowState) throws -> String {
        browserManager.createNewTab(in: windowState)

        if let urlString = args["url"] as? String,
           let url = URL(string: urlString) {
            // Load URL in the new tab after a brief delay for initialization
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let webView = self.getWebView(browserManager: browserManager, windowState: windowState) {
                    webView.load(URLRequest(url: url))
                }
            }
            return "Created new tab with URL: \(urlString)"
        }

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
