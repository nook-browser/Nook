// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserManager+NookWeb.swift
//  Nook
//
//  What NookWeb asks of its host. The tab model and its live pages reach every AppKit-only
//  manager (web view pool, downloads, Peek, zoom, PiP, extensions, native panels) through
//  these four protocols and nothing else.
//

import AppKit
import Combine
import WebKit
import NookWeb

// MARK: - WebViewProvider

extension BrowserManager: WebViewProvider {
    func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        FocusableWKWebView(frame: .zero, configuration: configuration)
    }

    func webView(for itemID: UUID, in windowID: UUID) -> WKWebView? {
        webViewCoordinator?.getWebView(for: itemID, in: windowID)
    }

    func allWebViews(for itemID: UUID) -> [WKWebView] {
        webViewCoordinator?.getAllWebViews(for: itemID) ?? []
    }

    /// Every unload comes through here, so a sidebar showing the page lets go of it first.
    func releaseWebViews(for session: PageSession) {
        exitSidebarPiP(showing: session.itemID)
        webViewCoordinator?.removeAllWebViews(for: session)
    }

    func removeFromContainers(_ webView: WKWebView) {
        webViewCoordinator?.removeWebViewFromContainers(webView)
    }
}

// MARK: - PageSessionDelegate

extension BrowserManager: PageSessionDelegate {
    var currentProfilePublisher: AnyPublisher<Profile?, Never> {
        $currentProfile.eraseToAnyPublisher()
    }

    func navigateAcrossWindows(_ itemID: UUID, to url: URL) {
        navigateTabAcrossWindows(itemID, to: url)
    }

    func addDownload(_ download: WKDownload, originalURL: URL, suggestedFilename: String) {
        _ = downloadManager.addDownload(
            download, originalURL: originalURL, suggestedFilename: suggestedFilename)
    }

    func saveFile(_ data: Data, suggestedFilename: String, originalURL: URL, from webView: WKWebView) {
        downloadManager.saveCompletedFile(data, suggestedFilename: suggestedFilename, originalURL: originalURL, from: webView.window)
    }

    func toggleFullScreen(for webView: WKWebView) -> Bool {
        guard let window = webView.window else { return false }
        DispatchQueue.main.async { window.toggleFullScreen(nil) }
        return true
    }

    func presentPeek(url: URL, from session: PageSession) {
        peekManager.presentExternalURL(url, from: session)
    }

    func presentPopupWindow(_ session: PageSession) {
        externalMiniWindowManager.present(session)
    }

    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        for session: PageSession,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool {
        authenticationManager.handleAuthenticationChallenge(
            challenge, for: session, completionHandler: completionHandler)
    }

    func loadZoom(for itemID: UUID) { loadZoomForTab(itemID) }

    func cleanupZoom(for itemID: UUID) { cleanupZoomForTab(itemID) }

    func setMuteState(_ muted: Bool, for itemID: UUID) {
        setMuteState(muted, for: itemID, originatingWindowId: windowRegistry?.activeWindow?.id)
    }

    func requestPictureInPicture(for session: PageSession, webView: WKWebView?) {
        PiPManager.shared.requestPiP(for: session, webView: webView)
    }

    func configureShortcutDetection(in webView: WKWebView) {
        keyboardShortcutManager?.websiteShortcutDetector.configure(webView: webView)
    }

    func shortcutDetectorDidNavigate(to url: URL) {
        keyboardShortcutManager?.websiteShortcutDetector.updateCurrentURL(url)
    }

    func updateDetectedShortcuts(for url: String, shortcuts: Set<String>) {
        keyboardShortcutManager?.websiteShortcutDetector.updateJSDetectedShortcuts(
            for: url, shortcuts: shortcuts)
    }

    func installWebStoreScript(in webView: WKWebView) -> AnyObject? {
        guard let url = webView.url, WebStoreScriptHandler.store(for: url) != nil,
              let script = BrowserConfiguration.webStoreInjectorScript()
        else { return nil }
        let controller = webView.configuration.userContentController
        let world = WebStoreScriptHandler.contentWorld
        controller.removeScriptMessageHandler(forName: WebStoreScriptHandler.handlerName, contentWorld: world)
        let handler = WebStoreScriptHandler(browserManager: self)
        controller.add(handler, contentWorld: world, name: WebStoreScriptHandler.handlerName)
        webView.evaluateJavaScript(script.source, in: nil, in: world, completionHandler: nil)
        return handler
    }

    func removeWebStoreHandler(from controller: WKUserContentController) {
        controller.removeScriptMessageHandler(
            forName: WebStoreScriptHandler.handlerName, contentWorld: WebStoreScriptHandler.contentWorld)
    }
}

// MARK: - TabEventObserver

extension BrowserManager: TabEventObserver {
    func tabOpened(_ session: PageSession) {
        ExtensionManager.shared.notifyTabOpened(session)
    }

    func tabActivated(new session: PageSession, previous: PageSession?) {
        zoomManager.showZoomLevel(for: session.itemID)
        ExtensionManager.shared.notifyTabActivated(new: session, previous: previous)
        // The loaded-page budget was only ever reached from startup warming and split view, so
        // opening tabs by hand never checked it and no cap could bind.
        compositorManager.pageActivated(session.itemID)
        updateSidebarPiP(new: session, previous: previous)
    }

    func tabClosed(itemID: UUID) {
        ExtensionManager.shared.notifyTabClosed(itemID: itemID)
        exitSidebarPiP(showing: itemID)
    }

    func tabMoved(itemID: UUID, from oldIndex: Int?, in oldWindow: BrowserWindowState?, pinnedChanged: Bool) {
        ExtensionManager.shared.notifyTabMoved(
            itemID: itemID, from: oldIndex, in: oldWindow, pinnedChanged: pinnedChanged)
    }

    func tabPropertiesChanged(_ session: PageSession, properties: WKWebExtension.TabChangedProperties) {
        ExtensionManager.shared.notifyTabPropertiesChanged(session, properties: properties)
    }

    func grantAccess(to url: URL) {
        ExtensionManager.shared.grantExtensionAccessToURL(url)
    }

    func wakeBackgroundWorkers() {
        ExtensionManager.shared.wakeBackgroundWorkers()
    }

    /// Leaving a playing video moves it into the sidebar panel; coming back puts it inline again.
    /// Runs before the compositor refreshes, so the outgoing web view is still mounted.
    private func updateSidebarPiP(new session: PageSession, previous: PageSession?) {
        let windows = Array(windowRegistry?.windows.values ?? [:].values)
        // The window that made the selection: a script or background window is not the key one.
        let active = windowRegistry?.activeWindow
        guard let windowState = active?.selectedItemID == session.itemID ? active
            : windows.first(where: { $0.selectedItemID == session.itemID })
        else { return }
        // Coming back to a tab brings its video home, from any window's sidebar or from the
        // system window Nook opened for it.
        exitSidebarPiP(showing: session.itemID)
        PiPManager.shared.leaveAutomatic(session)

        guard nookSettings?.autoPictureInPicture == true,
            let previous, previous.hasPlayingVideo, previous.hasPlayingAudio,
            !previous.isPrivate, !previous.hasPiPActive,
            // Another window or the other split pane may still be showing it.
            !tabs.isVisibleInAnyWindow(previous.itemID),
            SidebarPiPController.allowsAutomatic(previous.url),
            // A video already in picture-in-picture keeps it, and so does one playing in its tab.
            !windows.contains(where: { $0.sidebarPiPController?.isShowing == true }),
            !tabs.sessions.contains(where: {
                $0 !== previous && $0 !== session && ($0.hasPiPActive || ($0.hasPlayingVideo && $0.hasPlayingAudio))
            })
        else { return }

        guard let webView = getWebView(for: previous.itemID, in: windowState.id) ?? previous.assignedWebView
        else { return }

        // No sidebar means nothing to anchor to, so fall back to the system PiP window.
        guard windowState.isSidebarVisible, let controller = windowState.sidebarPiPController else {
            PiPManager.shared.enterAutomatically(previous, webView: webView, screened: true)
            return
        }
        controller.enter(session: previous, webView: webView, automatic: true) {
            PiPManager.shared.enterAutomatically(previous, webView: webView, screened: true)
        }
    }

    /// Ends any window's sidebar picture-in-picture of `itemID`.
    func exitSidebarPiP(showing itemID: UUID) {
        for window in windowRegistry?.windows.values ?? [:].values {
            window.sidebarPiPController?.exitIfShowing(itemID)
        }
    }

    /// A hidden sidebar has nowhere to dock, so a docked video carries on in the system window.
    func sidebarPiPSidebarHidden(in windowState: BrowserWindowState) {
        guard let controller = windowState.sidebarPiPController, controller.isDocked,
            let session = controller.session, let webView = controller.webView
        else { return }
        controller.exit()
        PiPManager.shared.enterAutomatically(session, webView: webView, screened: false)
    }

    /// The video follows the focused window, docked or floating, so its drop zone is always here.
    func moveSidebarPiP(to windowState: BrowserWindowState) {
        guard !windowState.isIncognito, let target = windowState.sidebarPiPController, !target.isShowing,
            let source = windowRegistry?.windows.values.compactMap(\.sidebarPiPController)
                .first(where: { $0 !== target && $0.isShowing }),
            source.session?.isPrivate == false, source.isReady,
            source.isFloating || windowState.isSidebarVisible
        else { return }
        target.adopt(from: source)
    }

    /// A closing window takes its pages' views with it, so no controller may keep showing one.
    func sidebarPiPWindowClosing(_ windowId: UUID) {
        for window in windowRegistry?.windows.values ?? [:].values {
            guard let controller = window.sidebarPiPController, let itemID = controller.itemID,
                window.id == windowId || getWebView(for: itemID, in: windowId) != nil
            else { continue }
            controller.exit()
        }
    }

    var nativeController: WKWebExtensionController? {
        ExtensionManager.shared.nativeController
    }

    func diagnose(for webView: WKWebView, url: URL) {
        #if DEBUG
        ExtensionManager.shared.diagnoseExtensionState(for: webView, url: url)
        #endif
    }
}

// MARK: - AlertPresenter

extension BrowserManager: AlertPresenter {
    /// A page dialog named for the frame that asked, so an iframe cannot speak as the site
    /// around it. `suppressible` adds the checkbox that ends an endless run of them.
    private func pageDialog(host: String, fallbackTitle: String, message: String, suppressible: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = host.isEmpty ? fallbackTitle : "\(host) says"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if suppressible {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't allow more dialogs from this page"
        }
        return alert
    }

    func presentAlert(
        message: String, host: String, over webView: WKWebView,
        onSuppress: (() -> Void)?, completion: @escaping () -> Void
    ) {
        let alert = pageDialog(
            host: host, fallbackTitle: "JavaScript Alert", message: message, suppressible: onSuppress != nil)
        guard let window = webView.window else { return completion() }
        alert.beginSheetModal(for: window) { _ in
            if alert.suppressionButton?.state == .on { onSuppress?() }
            completion()
        }
    }

    func presentConfirm(
        message: String, host: String, over webView: WKWebView,
        onSuppress: (() -> Void)?, completion: @escaping (Bool) -> Void
    ) {
        let alert = pageDialog(
            host: host, fallbackTitle: "JavaScript Confirm", message: message, suppressible: onSuppress != nil)
        alert.addButton(withTitle: "Cancel")
        guard let window = webView.window else { return completion(false) }
        alert.beginSheetModal(for: window) {
            if alert.suppressionButton?.state == .on { onSuppress?() }
            completion($0 == .alertFirstButtonReturn)
        }
    }

    func presentPrompt(
        prompt: String, defaultText: String?, host: String, over webView: WKWebView,
        onSuppress: (() -> Void)?, completion: @escaping (String?) -> Void
    ) {
        let alert = pageDialog(
            host: host, fallbackTitle: "JavaScript Prompt", message: prompt, suppressible: onSuppress != nil)
        alert.addButton(withTitle: "Cancel")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = defaultText ?? ""
        alert.accessoryView = textField
        guard let window = webView.window else { return completion(nil) }
        alert.beginSheetModal(for: window) {
            if alert.suppressionButton?.state == .on { onSuppress?() }
            completion($0 == .alertFirstButtonReturn ? textField.stringValue : nil)
        }
    }

    func presentOpenPanel(
        allowsMultipleSelection: Bool, allowsDirectories: Bool, over webView: WKWebView,
        completion: @escaping ([URL]?) -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = allowsMultipleSelection
        openPanel.canChooseDirectories = allowsDirectories
        openPanel.canChooseFiles = true
        openPanel.resolvesAliases = true
        openPanel.title = "Choose File"
        openPanel.prompt = "Choose"
        DispatchQueue.main.async {
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                completion(response == .OK ? openPanel.urls : nil)
            }
            if let window = webView.window {
                openPanel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                openPanel.begin(completionHandler: finish)
            }
        }
    }
}
