// Licensed under GPL-3.0. See LICENSE.
//
//  TabsController+LiveFolders.swift
//  Nook
//
//  Folders whose tabs follow a source. One source so far: GitHub pull requests.
//

import Foundation
import NookTabsCore

extension TabsController {
    /// Why a live folder's last refresh brought nothing.
    public enum LiveFolderStatus: Sendable { case signedOut, failed }

    /// Refreshes run on events (app active, folder opened, a pull request page), never on a
    /// timer; this is the least time between two for one folder.
    static let liveRefreshInterval: TimeInterval = 120

    private func liveFolders(inSpace spaceID: UUID?) -> [Item] {
        tree.items.values.filter { folder in
            folder.deletedAt == nil && folder.live == .githubPulls
                && (spaceID == nil || tree.spaceID(of: folder.id) == spaceID)
        }
    }

    /// The space's pull requests folder, made at the top of its pinned section when it has none.
    /// It reads the space's own github.com login.
    @discardableResult
    public func createPullRequestsFolder(in spaceID: UUID) -> UUID? {
        guard case .main? = owner(ofSpace: spaceID) else { return nil }
        if let existing = liveFolders(inSpace: spaceID).first {
            openFolder(existing.id)
            return existing.id
        }
        let id = UUID()
        guard perform(.main, "createLiveFolder", {
            try $0.createFolder(id: id, title: "Pull Requests", in: .pinned(spaceID: spaceID), after: nil, live: .githubPulls)
        }) != nil else { return nil }
        // Opening it starts the first refresh.
        openFolder(id)
        return id
    }

    /// Refreshes the live folders that are due, of one space when given.
    public func refreshLiveFolders(inSpace spaceID: UUID? = nil) {
        for folder in liveFolders(inSpace: spaceID) { refreshLiveFolder(folder.id) }
    }

    /// `force` skips the interval, for the folder's Refresh menu item.
    public func refreshLiveFolder(_ folderID: UUID, force: Bool = false) {
        guard tree.item(folderID)?.live == .githubPulls, !liveRefreshing.contains(folderID),
              force || Date().timeIntervalSince(liveRefreshed[folderID] ?? .distantPast) >= Self.liveRefreshInterval,
              let spaceID = tree.spaceID(of: folderID), let profile = profile(forSpace: spaceID) else { return }
        liveRefreshing.insert(folderID)
        liveRefreshed[folderID] = Date()
        Task {
            let cookies = await profile.dataStore.httpCookieStore.allCookies()
            let result = await Result { try await GitHubPulls.fetch(cookies: cookies) }
            liveRefreshing.remove(folderID)
            guard tree.item(folderID)?.live == .githubPulls else { return }
            switch result {
            case .success(let pages):
                applyLivePages(pages, to: folderID)
                liveStatus[folderID] = nil
            case .failure(let error):
                liveStatus[folderID] = (error as? GitHubPulls.Failure) == .signedOut ? .signedOut : .failed
                log.info("Live folder refresh failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func applyLivePages(_ pages: [LivePage], to folderID: UUID) {
        // A dismissed page that left the source is forgotten, so it shows again if it returns.
        let dismissed = (device.liveDismissed?[folderID] ?? []).intersection(pages.map(\.url))
        setLiveDismissed(folderID, dismissed)
        let open = children(of: .folder(itemID: folderID)).map(\.id)
            .filter { session(for: $0) != nil || device.openPages[$0] != nil }
        perform(.main, "reconcileLive", undoable: false) {
            try $0.reconcileLive(folderID, with: pages, dismissed: dismissed, keeping: Set(open), owns: GitHubPulls.owns)
        }
    }

    /// The open pull requests of a space's github.com login, for a favorite's hover card. Empty
    /// when signed out or when the list could not be read.
    public func pullRequests(inSpace spaceID: UUID) async -> [LivePage] {
        guard let profile = profile(forSpace: spaceID) else { return [] }
        let cookies = await profile.dataStore.httpCookieStore.allCookies()
        return (try? await GitHubPulls.fetch(cookies: cookies)) ?? []
    }

    /// A tab the person took out of a live folder stays out until its page leaves the source.
    func dismissFromLiveFolder(_ item: Item) {
        guard case .folder(let folderID) = item.parent, tree.item(folderID)?.live != nil, let url = item.url else { return }
        setLiveDismissed(folderID, (device.liveDismissed?[folderID] ?? []).union([url]))
    }

    /// A pull request page committed in a space: its folder may be out of date.
    func livePageCommitted(_ url: URL, itemID: UUID) {
        guard GitHubPulls.owns(url), let spaceID = tree.spaceID(of: itemID) else { return }
        refreshLiveFolders(inSpace: spaceID)
    }
}

private extension Result where Failure == Error {
    init(_ body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
