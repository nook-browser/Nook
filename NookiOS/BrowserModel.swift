// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  BrowserModel.swift
//  NookiOS
//
//  The iOS stand-in for BrowserManager: owns the managers, one window state, and the
//  conformances the packages need (BrowserModel+Seams.swift). One scene, one WKWebView
//  per session, no extensions.
//

import Combine
import OSLog
import SwiftUI
import WebKit
import NookBlocker
import NookSettings
import NookTweaks
import NookWeb

@MainActor
final class BrowserModel: ObservableObject {
    let settings: NookSettingsService
    let windowRegistry = WindowRegistry()
    let blocker: ContentBlockerManager
    let sponsorBlock: SponsorBlockManager
    let siteRouting: SiteRoutingManager
    let tabs: TabsController
    let window = BrowserWindowState()

    /// The active space's data store; PageSession waits on the publisher when this is nil.
    @Published var currentProfileValue: Profile?

    // MARK: - Chrome

    @Published var sheet: ChromeSheet?
    @Published var dialog: ChromeDialog?
    /// Where the settings sheet opens. Nil is its root list.
    @Published var settingsRoute: SettingsRoute?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "BrowserModel")

    init() {
        let settings = NookSettingsService()
        self.settings = settings
        let blocker = ContentBlockerManager(settings: settings)
        let sponsorBlock = SponsorBlockManager(settings: settings)
        let siteRouting = SiteRoutingManager(settings: settings)
        self.blocker = blocker
        self.sponsorBlock = sponsorBlock
        self.siteRouting = siteRouting
        self.tabs = TabsController(
            settings: settings, windowRegistry: windowRegistry, blocker: blocker,
            sponsorBlock: sponsorBlock, siteRouting: siteRouting)

        tabs.webViews = self
        tabs.sessionDelegate = self
        tabs.alerts = self
        blocker.attach(host: self)
        siteRouting.host = self
        SocialImageTweaks.downloader = self

        windowRegistry.register(window)
        windowRegistry.setActive(window)
        tabs.attach(window: window)
        currentProfileValue = window.spaceID.flatMap { tabs.profile(forSpace: $0) }

        // Ad blocking is a core feature on the phone: on unless the user has turned it off.
        // The settings service registers false as the default, so only the persisted domain
        // says whether the user ever chose.
        let persisted = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        if persisted?["settings.adBlockerEnabled"] == nil {
            settings.adBlockerEnabled = true
        }
        blocker.setEnabled(settings.blockCrossSiteTracking || settings.adBlockerEnabled)
        log.notice("Model ready: \(self.tabs.orderedSpaces.count) spaces, selected \(String(describing: self.window.selectedItemID), privacy: .public)")
    }

    /// Loads the window's selected page once the blocker has had up to two seconds to activate,
    /// the same wait BrowserManager.applyStartupLoadMode makes on macOS.
    func start() async {
        if !blocker.isEnabled, let activation = blocker.activationTask {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await activation.value }
                group.addTask { try? await Task.sleep(for: .seconds(2)) }
                await group.next()
                group.cancelAll()
            }
        }
        if let selected = window.selectedItemID {
            tabs.select(selected, in: window)
        }
        #if DEBUG
        // Hands-off checks: `xcrun simctl launch <udid> com.gstudios.nook -NookStartURL <url>`.
        // http links opened from outside go to the default browser, which Nook cannot be
        // until Apple grants the web-browser entitlement.
        if let start = UserDefaults.standard.string(forKey: "NookStartURL") {
            navigate(start)
        }
        #endif
        objectWillChange.send()
    }

    var selectedSession: PageSession? { tabs.selectedSession(in: window) }

    func navigate(_ input: String) {
        if let session = selectedSession {
            session.navigate(to: input)
        } else if let url = URL(string: normalizeURL(input, queryTemplate: settings.resolvedSearchEngineTemplate)) {
            tabs.open(url: url, in: window, placement: .newTab)
            objectWillChange.send()
        }
    }
}
