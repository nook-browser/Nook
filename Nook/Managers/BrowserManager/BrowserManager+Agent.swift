// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserManager+Agent.swift
//  Nook
//
//  Keeps the DevMCP agent's page rendering while the person looks at another space. WebKit
//  treats a page outside any window as hidden (no rendering, 1 Hz timers), so the agent's page
//  sits in a browser window, in a view placed outside the window's content area: nothing draws,
//  no tracking area or click reaches it, and WebKit still counts it visible. After 30 s with no
//  tool call it leaves the window, so an idle agent page costs what a background tab does.
//

import AppKit
import WebKit
import NookWeb

@MainActor private var agentIdle: Task<Void, Never>?
/// Set while the agent's page is out of the window for being idle; the next tool call clears it.
@MainActor private var agentParked = false

extension BrowserManager {
    private static let agentIdleDelay: Duration = .seconds(30)
    /// How long after parking the Agent space's tabs are closed.
    private static let agentCloseDelay: Duration = .seconds(30 * 60)

    func installAgentPageHost() {
        tabs.onAgentPage = { [weak self] session in
            guard let self, !agentParked || self.tabs.agentCallsInFlight > 0 else { return }
            agentParked = false
            self.hostAgentPage(session)
            self.scheduleAgentIdle()
        }
    }

    /// The agent's page, loaded, in a window and counted as used. Nil without an Agent space tab;
    /// throws when the tab's page cannot be made.
    func agentWebView() throws -> WKWebView? {
        guard let id = tabs.agentItem else { return nil }
        guard let session = tabs.ensureSession(for: id) else { throw AgentPageError.noPage }
        session.loadWebViewIfNeeded()
        guard let view = session.webView else { throw AgentPageError.noPage }
        compositorManager.markTabAccessed(id)
        agentParked = false
        hostAgentPage(session)
        scheduleAgentIdle()
        return view
    }

    /// Puts the agent's page in the active window's hidden host when no open window holds it; a
    /// window that shows the Agent space takes it from there itself.
    func hostAgentPage(_ session: PageSession) {
        guard tabs.agentItem == session.itemID, let view = session.webView,
              let window = ((windowRegistry?.activeWindow).flatMap { $0.isIncognito ? nil : $0 } ?? tabs.regularWindows.first)?.window,
              let content = window.contentView else { return }
        // Already in a window that is still open; a closed one no longer renders it.
        if let current = view.window, current === window || current.isVisible || current.isMiniaturized { return }
        let host = content.subviews.first { $0 is AgentPageHostView } ?? {
            let host = AgentPageHostView(frame: content.bounds.offsetBy(dx: -AgentPageHostView.offset, dy: 0))
            host.autoresizingMask = [.width, .height]
            host.alphaValue = 0
            // Clipped and outside the content area, so its visible rect, and every tracking area
            // in it, is empty.
            host.clipsToBounds = true
            content.addSubview(host, positioned: .below, relativeTo: nil)
            return host
        }()
        // One page at a time: the agent's previous one goes back to being a background tab.
        host.subviews.forEach { $0.removeFromSuperview() }
        view.frame = host.bounds
        view.autoresizingMask = [.width, .height]
        host.addSubview(view)
    }

    /// Takes the agent's page out of its host once no call has run for `agentIdleDelay`.
    private func scheduleAgentIdle() {
        agentIdle?.cancel()
        agentIdle = Task { @MainActor [weak self] in
            repeat {
                try? await Task.sleep(for: Self.agentIdleDelay)
                if Task.isCancelled { return }
            } while self?.tabs.agentCallsInFlight ?? 0 > 0
            guard let self, let view = self.tabs.agentItem.flatMap(self.tabs.session(for:))?.webView,
                  view.superview is AgentPageHostView else { return }
            agentParked = true
            view.removeFromSuperview()
            try? await Task.sleep(for: Self.agentCloseDelay)
            if Task.isCancelled { return }
            self.closeIdleAgentTabs()
        }
    }

    /// Closes the Agent space's regular tabs, unless a window is showing the space or a call runs.
    func closeIdleAgentTabs() {
        guard let agent = tabs.agentSpaceID, tabs.agentCallsInFlight == 0,
              !tabs.regularWindows.contains(where: { $0.spaceID == agent }) else { return }
        for item in tabs.children(of: .tabs(spaceID: agent)) { tabs.remove(item.id) }
    }
}

enum AgentPageError: LocalizedError {
    case noPage
    var errorDescription: String? { "The Agent space's tab has no page" }
}

/// Holds the agent's page out of sight: transparent, outside the content area, never the target
/// of a click.
final class AgentPageHostView: NSView {
    /// How far left of the content area the host sits; wider than any window.
    static let offset: CGFloat = 20_000
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityChildren() -> [Any]? { [] }
}
