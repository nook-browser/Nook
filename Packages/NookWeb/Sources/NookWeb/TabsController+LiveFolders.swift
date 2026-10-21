// Licensed under GPL-3.0. See LICENSE.
//
//  TabsController+LiveFolders.swift
//  Nook
//
//  Folders whose tabs follow a source: GitHub pull requests, issues and notifications, Asana
//  tasks, and RSS or Atom feeds.
//

import Foundation
import NookTabsCore

extension TabsController {
    /// Why a live folder's last refresh brought nothing.
    public enum LiveFolderStatus: Sendable { case signedOut, failed }

    /// Refreshes run on events (app active, folder opened, a page the source owns), never on a
    /// timer; this is the least time between two for one folder.
    static let liveRefreshInterval: TimeInterval = 120

    private static let builtInSources: [LiveSource] = [.githubPulls, .githubIssues, .githubNotifications, .asanaTasks]

    private static func isKnown(_ source: LiveSource?) -> Bool {
        guard let source else { return false }
        return builtInSources.contains(source) || source.feedURL != nil
    }

    /// The folder's name; a feed's is replaced by the feed's own title on its first fetch.
    private static func placeholderTitle(_ source: LiveSource) -> String {
        switch source {
        case .githubPulls: return "Pull Requests"
        case .githubIssues: return "Issues"
        case .githubNotifications: return "Notifications"
        case .asanaTasks: return "My Tasks"
        default: return source.feedURL?.host ?? ""
        }
    }

    /// The pages a source reports, and for a feed its own title.
    private static func fetch(_ source: LiveSource, cookies: [HTTPCookie]) async throws -> (pages: [LivePage], title: String?) {
        switch source {
        case .githubPulls: return (try await GitHubPulls.fetch(cookies: cookies), nil)
        case .githubIssues: return (try await LiveFetch.githubIssues(cookies: cookies), nil)
        case .githubNotifications: return (try await LiveFetch.githubNotifications(cookies: cookies), nil)
        case .asanaTasks: return (try await LiveFetch.asanaTasks(cookies: cookies), nil)
        default:
            guard let url = source.feedURL else { throw LiveFetch.Failure.failed }
            let feed = try await LiveFetch.feed(url)
            return (feed.pages, feed.title)
        }
    }

    /// Which tabs in the folder the source manages. A feed owns its own host and the hosts of
    /// `pages`, or of the folder's tabs when no pages are given.
    private func owns(_ source: LiveSource, folderID: UUID, pages: [LivePage]? = nil) -> (URL) -> Bool {
        switch source {
        case .githubPulls: return GitHubPulls.owns
        case .githubIssues: return LiveParse.ownsIssue
        case .githubNotifications: return LiveParse.ownsNotification
        case .asanaTasks: return LiveParse.ownsAsanaTask
        default:
            // ponytail: host match, so a hand-added tab on a feed item's host is managed too.
            let urls = pages?.map(\.url) ?? children(of: .folder(itemID: folderID)).compactMap(\.url)
            let hosts = Set((urls + [source.feedURL].compactMap { $0 }).compactMap(\.host))
            return { $0.host.map(hosts.contains) ?? false }
        }
    }

    private func liveFolders(inSpace spaceID: UUID?) -> [Item] {
        tree.items.values.filter { folder in
            folder.deletedAt == nil && Self.isKnown(folder.live)
                && (spaceID == nil || tree.spaceID(of: folder.id) == spaceID)
        }
    }

    /// The space's folder for `source`, made at the top of its pinned section when it has none.
    /// It reads the space's own login for that site.
    @discardableResult
    public func createLiveFolder(_ source: LiveSource, in spaceID: UUID) -> UUID? {
        guard Self.isKnown(source), case .main? = owner(ofSpace: spaceID) else { return nil }
        if let existing = liveFolders(inSpace: spaceID).first(where: { $0.live == source }) {
            openFolder(existing.id)
            return existing.id
        }
        let id = UUID()
        guard perform(.main, "createLiveFolder", {
            try $0.createFolder(id: id, title: Self.placeholderTitle(source), in: .pinned(spaceID: spaceID), after: nil, live: source)
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
        guard let source = tree.item(folderID)?.live, Self.isKnown(source), !liveRefreshing.contains(folderID),
              force || Date().timeIntervalSince(liveRefreshed[folderID] ?? .distantPast) >= Self.liveRefreshInterval,
              let spaceID = tree.spaceID(of: folderID), let profile = profile(forSpace: spaceID) else { return }
        liveRefreshing.insert(folderID)
        liveRefreshed[folderID] = Date()
        Task {
            let cookies = source.feedURL == nil ? await profile.dataStore.httpCookieStore.allCookies() : []
            let result = await Result { try await Self.fetch(source, cookies: cookies) }
            liveRefreshing.remove(folderID)
            guard tree.item(folderID)?.live == source else { return }
            switch result {
            case .success(let fetched):
                applyLivePages(fetched.pages, to: folderID, source: source)
                if let title = fetched.title, tree.item(folderID)?.customTitle == Self.placeholderTitle(source) {
                    perform(.main, "titleLiveFolder", undoable: false) { try $0.rename(folderID, customTitle: title) }
                }
                liveStatus[folderID] = nil
            case .failure(let error):
                liveStatus[folderID] = (error as? LiveFetch.Failure) == .signedOut ? .signedOut : .failed
                log.info("Live folder refresh failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func applyLivePages(_ pages: [LivePage], to folderID: UUID, source: LiveSource) {
        // A dismissed page that left the source is forgotten, so it shows again if it returns.
        let dismissed = (device.liveDismissed?[folderID] ?? []).intersection(pages.map(\.url))
        setLiveDismissed(folderID, dismissed)
        let open = children(of: .folder(itemID: folderID)).map(\.id)
            .filter { session(for: $0) != nil || device.openPages[$0] != nil }
        let owns = owns(source, folderID: folderID, pages: pages)
        perform(.main, "reconcileLive", undoable: false) {
            try $0.reconcileLive(folderID, with: pages, dismissed: dismissed, keeping: Set(open), owns: owns)
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

    /// A page a live folder in the space owns committed: that folder may be out of date.
    func livePageCommitted(_ url: URL, itemID: UUID) {
        guard let spaceID = tree.spaceID(of: itemID) else { return }
        for folder in liveFolders(inSpace: spaceID) {
            guard let source = folder.live, owns(source, folderID: folder.id)(url) else { continue }
            refreshLiveFolder(folder.id)
        }
    }
}

private extension Result where Failure == Error {
    init(_ body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
