// Licensed under GPL-3.0. See LICENSE.
//
//  AgentSpace.swift
//  NookTabsCore
//
//  The space DevMCP agents browse in. It is found by a marker in `icon`, which nothing
//  displays or edits and older builds carry through a save unchanged; the marker also names
//  the space whose logins (website data store) the agent uses.
//

import Foundation

extension SpaceRecord {
    static let agentIconPrefix = "nook.agent:"
    /// Fixed accent, so folder icons and selection tint match the agent chrome.
    public static let agentAccentHex = "#F2541B"

    public static func agentIcon(loginsFrom spaceID: UUID) -> String { agentIconPrefix + spaceID.uuidString }

    public var isAgent: Bool { icon.hasPrefix(Self.agentIconPrefix) }

    /// The space whose logins this agent space borrows, as recorded at creation.
    public var agentLoginSpaceID: UUID? {
        isAgent ? UUID(uuidString: String(icon.dropFirst(Self.agentIconPrefix.count))) : nil
    }
}

extension TabTree {
    public var agentSpace: SpaceRecord? { orderedSpaces.first(where: \.isAgent) }

    /// The space whose data store `spaceID`'s pages use: itself, or for the agent space the
    /// space it borrows logins from, else the first ordinary space.
    public func loginSpace(for spaceID: UUID) -> UUID? {
        guard let space = space(spaceID) else { return nil }
        guard space.isAgent else { return spaceID }
        if let borrowed = space.agentLoginSpaceID.flatMap(self.space), !borrowed.isAgent { return borrowed.id }
        return orderedSpaces.first { !$0.isAgent }?.id
    }

    /// The agent space, created last in order with logins from `loginsFrom` when there is none.
    public mutating func ensureAgentSpace(loginsFrom: UUID?, now: Date = Date()) -> (id: UUID, change: Change)? {
        if let existing = agentSpace { return (existing.id, Change()) }
        let given = loginsFrom.flatMap(space).flatMap { $0.isAgent ? nil : $0 }
        let login = given ?? orderedSpaces.first { !$0.isAgent }
        guard let login else { return nil }
        let id = UUID()
        let change = createSpace(id: id, name: "Agent", icon: SpaceRecord.agentIcon(loginsFrom: login.id),
                                 accentHex: SpaceRecord.agentAccentHex, after: orderedSpaces.last?.id, now: now)
        return (id, change)
    }
}
