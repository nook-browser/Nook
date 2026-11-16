// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserManager+Lookup.swift
//  Nook
//
//  Look It Up's seams into the window: where its reader pages sit while they load, what the
//  URL bar shows for one of its pages, and the button on a booking card.
//

import AppKit
import SwiftUI
import NookDesign
import NookWeb

extension BrowserManager {
    private static let readerHostSize = NSSize(width: 1100, height: 1500)

    /// The request behind one of Look It Up's pages, nil for any other address.
    func lookupRequest(for url: URL?) -> String? {
        guard let url, url.isFileURL, tabs.isLookupPage(url) else { return nil }
        return lookupManager.request(forPage: url)
    }

    /// The hidden host for reader pages in the most recent regular window, made on first use.
    /// Placed like the agent's host: outside the content area and clipped, so nothing reaches it.
    func lookupReaderHost() -> NSView? {
        guard let content = windowRegistry?.mostRecentRegularWindow?.window?.contentView else { return nil }
        if let host = content.subviews.first(where: { $0 is LookupReaderHostView }) { return host }
        let host = LookupReaderHostView(frame: NSRect(origin: NSPoint(x: -AgentPageHostView.offset, y: 0), size: Self.readerHostSize))
        host.alphaValue = 0
        host.clipsToBounds = true
        content.addSubview(host, positioned: .below, relativeTo: nil)
        return host
    }

    // MARK: - The Card Button

    func lookupAction(card: Int, from session: PageSession) {
        lookupManager.pick(card: card, from: session)
    }

    /// Puts `text` in the chat's compose box in `window` and shows the chat. Nothing is sent.
    func showChatDraft(_ text: String, in window: BrowserWindowState) {
        guard nookSettings?.showAIAssistant == true else { return }
        window.agentDraft = text
        withAnimation(NookDesign.Motion.standard) {
            window.devPanelTab = .agent
            window.isSidebarAIChatVisible = true
            window.isSidebarMenuVisible = false
        }
    }

}
