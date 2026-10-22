// Licensed under GPL-3.0. See LICENSE.
//
//  TabsController+Agent.swift
//  NookWeb
//
//  The Agent space: where DevMCP agents browse, with the person's logins. Agent activity never
//  changes what a window shows; the person opens the space to watch, like any other.
//

import Foundation
import NookTabsCore

extension TabsController {
    public var agentSpaceID: UUID? { tree.agentSpace?.id }

    public func isInAgentSpace(_ itemID: UUID) -> Bool {
        guard let agent = agentSpaceID else { return false }
        return tree.spaceID(of: itemID) == agent
    }

    /// The Agent space, made on first use with the logins of `window`'s space.
    @discardableResult
    public func ensureAgentSpace(loginsFrom window: BrowserWindowState?) -> UUID? {
        if let existing = agentSpaceID { return existing }
        var made: UUID?
        perform(.main, "agentSpace", undoable: false) { tree in
            guard let result = tree.ensureAgentSpace(loginsFrom: window?.spaceID) else { throw TreeError.missingSpace }
            made = result.id
            return result.change
        }
        return made
    }

    /// The tab the agent works in: its last pick while it is still in the Agent space, else the
    /// space's first tab.
    public var agentItem: UUID? {
        guard let agent = agentSpaceID else { return nil }
        let order = displayOrder(inSpace: agent)
        if let current = agentItemID, order.contains(current) { return current }
        return order.first
    }

    /// Makes `itemID` the agent's tab. Windows showing the Agent space show it; the others only
    /// remember it for when the person opens the space. The page loads either way.
    func selectForAgent(_ itemID: UUID) {
        guard let agent = agentSpaceID, tree.spaceID(of: itemID) == agent else { return }
        agentItemID = itemID
        for other in regularWindows {
            if other.spaceID == agent {
                if other.selectedItemID != itemID { select(itemID, in: other) }
            } else {
                other.selectedItemBySpace[agent] = itemID
                other.emptiedSpaces.remove(agent)
                mirror(other)
            }
        }
        guard let session = ensureSession(for: itemID) else { return }
        session.loadWebViewIfNeeded()
        onAgentPage?(session)
    }
}

extension PageSession {
    /// A page in the Agent space: it opens no window, sheet or panel and records no history.
    public var isAgentPage: Bool { controller?.isInAgentSpace(itemID) == true }
}
