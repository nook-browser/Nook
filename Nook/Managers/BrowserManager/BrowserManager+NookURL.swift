// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserManager+NookURL.swift
//  Nook
//

import AppKit
import NookWeb
import OSLog

private let nookURLLog = Logger(subsystem: "com.gstudios.nook", category: "NookURL")

extension BrowserManager {
    /// Runs a nook:// link from another app. Dropped unless Settings > Links allows it.
    func handleNookURL(_ link: URL) {
        guard nookSettings?.allowNookURLs == true else {
            nookURLLog.info("Dropped nook:// link: not allowed in Settings")
            return
        }
        guard let command = NookURLCommand.parse(link) else {
            nookURLLog.info("Ignored nook:// link: \(link.host ?? "", privacy: .public) is not a valid command")
            return
        }
        if !command.ignored.isEmpty {
            nookURLLog.info("Ignored nook:// parameters: \(command.ignored.joined(separator: ","), privacy: .public)")
        }

        var spaceID: UUID?
        if let name = command.space {
            let choices = tabs.orderedSpaces.filter { !$0.isAgent }.map { (id: $0.id, name: $0.name) }
            guard let match = NookURLCommand.match(name, in: choices) else {
                nookURLLog.info("Ignored nook:// link: no such space")
                return
            }
            spaceID = match
        }
        guard let window = openBrowserWindow(), !window.isIncognito else { return }
        // A window showing the Agent space opens into the first ordinary one.
        if spaceID == nil, window.spaceID.flatMap({ tabs.space($0) })?.isAgent == true {
            spaceID = tabs.orderedSpaces.first { !$0.isAgent }?.id
        }

        switch command.action {
        case .switchSpace:
            if let spaceID { tabs.setSpace(spaceID, in: window) }
        case .open(let url, let reuse):
            openFromLauncher(url, reuse: reuse, space: spaceID, explicit: command.space != nil, in: window)
        case .search(let query):
            guard let template = nookSettings?.resolvedSearchEngineTemplate,
                  let url = NookURLCommand.searchURL(for: query, template: template) else { return }
            openFromLauncher(url, reuse: false, space: spaceID, explicit: command.space != nil, in: window)
        }
    }

    private func openFromLauncher(_ url: URL, reuse: Bool, space: UUID?, explicit: Bool, in window: BrowserWindowState) {
        if reuse, let target = space ?? window.spaceID,
           let existing = tabs.items(inSpace: target).first(where: { $0.url.map { NookURLCommand.isSamePage($0, url) } == true }) {
            tabs.select(existing.id, in: window)
            return
        }
        // Air Traffic Control only decides when the link names no space.
        if !explicit, siteRoutingManager.applyRoute(url: url, from: nil) { return }
        tabs.open(url: url, in: window, placement: .newTab, parent: space.map { .tabs(spaceID: $0) })
    }
}
