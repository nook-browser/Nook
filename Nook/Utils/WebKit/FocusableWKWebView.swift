// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import AppKit
import NookWeb
@preconcurrency import UserNotifications
import WebKit
import UniformTypeIdentifiers

// Simple subclass to ensure clicking a webview focuses its tab in the app state
@MainActor
final class FocusableWKWebView: WKWebView, SessionWebView {
    weak var owningSession: PageSession?
    var contextMenuBridge: WebContextMenuBridge?
    nonisolated private static let imageContentTypes: [UTType] = [
        .jpeg, .png, .gif, .bmp, .tiff, .webP, .heic, .heif
    ]

    deinit {
        // MEMORY LEAK FIX: Detach bridge deterministically. The primary cleanup now
        // happens in PageSession.cleanupClone(_:), but this is a safety net.
        if let bridge = contextMenuBridge {
            let bridge = bridge
            Task { @MainActor in
                bridge.detach()
            }
        }
        contextMenuBridge = nil
    }

    override func mouseDown(with event: NSEvent) {
        // Store Option key state for Peek functionality
        owningSession?.isOptionKeyDown = event.modifierFlags.contains(.option)

        owningSession?.activate()
        // Ensure this webview becomes first responder so it can receive menu events
        if window?.firstResponder != self {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        owningSession?.activate()
        // Ensure this webview becomes first responder so willOpenMenu gets called
        if window?.firstResponder != self {
            window?.makeFirstResponder(self)
        }
        super.rightMouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseUp(with event: NSEvent) {
        // Reset Option key state after mouse up
        owningSession?.isOptionKeyDown = false
        super.mouseUp(with: event)
    }
    private weak var pendingMenu: NSMenu?
    private var pendingPayload: WebContextMenuPayload?
    private var contextMenuFallbackWorkItem: DispatchWorkItem?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else {
            return nil
        }
        prepareMenu(menu)
        return menu
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        prepareMenu(menu)
    }

    private func prepareMenu(_ menu: NSMenu) {
        pendingMenu = menu
        pendingPayload = owningSession?.pendingContextMenuPayload

        contextMenuFallbackWorkItem?.cancel()
        let fallback = DispatchWorkItem { [weak self, weak menu] in
            guard let self, let menu, self.pendingMenu === menu else {
                return
            }
            self.sanitizeDefaultMenu(menu)
            self.pendingMenu = nil
            self.pendingPayload = nil
            self.contextMenuFallbackWorkItem = nil
            self.owningSession?.pendingContextMenuPayload = nil
        }
        contextMenuFallbackWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: fallback)

        _ = applyPendingContextMenuIfPossible()
    }

    func handleImageDownload(identifier: String, promptForLocation: Bool = false) {
        let destinationPreference: Download.DestinationPreference = promptForLocation ? .askUser : .automaticDownloadsFolder

        if identifier.hasPrefix("data:") {
            handleDataURL(identifier, destinationPreference: destinationPreference)
            return
        }

        guard let url = resolveImageURL(from: identifier),
              ["http", "https", "data", "blob"].contains(url.scheme?.lowercased() ?? "") else {
            return
        }

        prepareRequest(for: url) { [weak self] request in
            DispatchQueue.main.async {
                self?.initiateDownload(using: request, originalURL: url, destinationPreference: destinationPreference)
            }
        }
    }

    private func showSaveDialog(
        for localURL: URL,
        suggestedFilename: String,
        allowedContentTypes: [UTType] = FocusableWKWebView.imageContentTypes
    ) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = suggestedFilename

        // Set the default directory to Downloads
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloads
        }

        // Set allowed file types for images
        savePanel.allowedContentTypes = allowedContentTypes

        // Set the title and message
        savePanel.title = "Save Image"
        savePanel.message = "Choose where to save the image"

        // Show the save dialog
        savePanel.begin { [weak self] result in
            if result == .OK, let destinationURL = savePanel.url {
                do {
                    // Move the downloaded file to the chosen location
                    try FileManager.default.moveItem(at: localURL, to: destinationURL)

                    // Show a success notification
                    self?.showSaveSuccessNotification(for: destinationURL)
                } catch {
                    self?.showSaveErrorNotification(error: error)
                }
            } else {
                // User cancelled, clean up the temporary file
                try? FileManager.default.removeItem(at: localURL)
            }
        }
    }

    private func showSaveSuccessNotification(for url: URL) {
        postUserNotification(
            title: "Image Saved",
            message: "Saved to \(url.lastPathComponent)"
        )
    }

    private func showSaveErrorNotification(error: Error) {
        postUserNotification(
            title: "Save Failed",
            message: error.localizedDescription
        )
    }

    private func postUserNotification(title: String, message: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            guard granted == true else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "focusable-webview-\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            )
            try? await center.add(request)
        }
    }

    private func resolveImageURL(from rawValue: String) -> URL? {
        if let absoluteURL = URL(string: rawValue),
           let scheme = absoluteURL.scheme,
           !scheme.isEmpty {
            return absoluteURL
        }

        if rawValue.hasPrefix("//"),
           let scheme = owningSession?.url.scheme {
            return URL(string: "\(scheme):\(rawValue)")
        }

        if let base = owningSession?.url,
           let resolved = URL(string: rawValue, relativeTo: base)?.absoluteURL {
            return resolved
        }

        return nil
    }

    private func prepareRequest(for url: URL, completion: @escaping (URLRequest) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // The page chose this URL. Cookies for any other site would make the save a credentialed
        // cross-site GET; public CDN media does not need them.
        guard Self.isSameSite(url.host, self.url?.host) else {
            completion(request)
            return
        }

        configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var decoratedRequest = request
            let filteredCookies = Self.relevantCookies(for: url, from: cookies)
            if !filteredCookies.isEmpty {
                let headers = HTTPCookie.requestHeaderFields(with: filteredCookies)
                headers.forEach { key, value in
                    decoratedRequest.setValue(value, forHTTPHeaderField: key)
                }
            }
            completion(decoratedRequest)
        }
    }

    private func initiateDownload(
        using request: URLRequest,
        originalURL: URL,
        destinationPreference: Download.DestinationPreference
    ) {
        guard let tab = owningSession else {
            return
        }

        var enrichedRequest = request
        // Origin only, and nothing on an https to http downgrade: the page's path and query stay private.
        var origin = URLComponents()
        origin.scheme = tab.url.scheme
        origin.host = tab.url.host
        origin.port = tab.url.port
        origin.path = "/"
        if enrichedRequest.value(forHTTPHeaderField: "Referer") == nil,
           tab.url.host != nil,
           tab.url.scheme == "http" || originalURL.scheme == "https",
           let referer = origin.string {
            enrichedRequest.setValue(referer, forHTTPHeaderField: "Referer")
        }

        // Call WKWebView's startDownload method (inherited from WKWebView)
        self.startDownload(using: enrichedRequest) { [weak self] wkDownload in
            guard let self else { return }
            DispatchQueue.main.async {
                self.registerDownload(wkDownload, originalURL: originalURL, destinationPreference: destinationPreference)
            }
        }
    }

    private func registerDownload(
        _ download: WKDownload,
        originalURL: URL,
        destinationPreference: Download.DestinationPreference
    ) {
        guard owningSession != nil else { return }
        let manager = DownloadManager.shared

        let proposedName = originalURL.lastPathComponent.isEmpty ? "image" : originalURL.lastPathComponent
        _ = manager.addDownload(
            download,
            originalURL: originalURL,
            suggestedFilename: proposedName,
            destinationPreference: destinationPreference,
            allowedContentTypes: Self.imageContentTypes,
            mediaOnly: true
        )
    }

    // No public suffix list: hosts match when one equals or contains the other, so a page on a
    // bare shared suffix (github.io) would match its subdomains. Use a PSL if that proves too loose.
    private static func isSameSite(_ lhs: String?, _ rhs: String?) -> Bool {
        func bare(_ host: String?) -> String {
            let host = host?.lowercased() ?? ""
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let a = bare(lhs), b = bare(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasSuffix(".\(b)") || b.hasSuffix(".\(a)")
    }

    private static func relevantCookies(for url: URL, from cookies: [HTTPCookie]) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        let requestPath = url.path.isEmpty ? "/" : url.path

        return cookies.filter { cookie in
            var cookieDomain = cookie.domain.lowercased()
            if cookieDomain.hasPrefix(".") {
                cookieDomain.removeFirst()
            }

            guard !cookieDomain.isEmpty else { return false }
            let domainMatches = host == cookieDomain || host.hasSuffix(".\(cookieDomain)")
            guard domainMatches else { return false }

            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            guard requestPath.hasPrefix(cookiePath) else { return false }

            if cookie.isSecure && url.scheme != "https" {
                return false
            }

            return true
        }
    }

    private func handleDataURL(
        _ dataURLString: String,
        destinationPreference: Download.DestinationPreference
    ) {
        guard let commaIndex = dataURLString.firstIndex(of: ",") else {
            return
        }

        let metadata = dataURLString[..<commaIndex]
        let payload = String(dataURLString[dataURLString.index(after: commaIndex)...])
        let isBase64 = metadata.contains(";base64")

        let mimeType = metadata
            .replacingOccurrences(of: "data:", with: "")
            .components(separatedBy: ";")
            .first?
            .lowercased()

        // The page wrote this URL; without the check "Save Image" would write a .dmg or .command.
        guard let mimeType, mimeType.hasPrefix("image/") else {
            return
        }

        let fileExtension = mimeTypeToExtension(mimeType)
        let suggestedFilename = "image.\(fileExtension)"

        let imageData: Data?
        if isBase64 {
            imageData = Data(base64Encoded: payload)
        } else {
            imageData = payload.removingPercentEncoding?.data(using: .utf8)
        }

        guard let data = imageData else {
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        do {
            try data.write(to: tempURL, options: .atomic)
            // Same quarantine as a network download; the move below carries the attribute along.
            DownloadManager.setQuarantineAttribute(on: tempURL)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch destinationPreference {
                case .askUser:
                    self.showSaveDialog(
                        for: tempURL,
                        suggestedFilename: suggestedFilename
                    )
                case .automaticDownloadsFolder:
                    self.saveTempFileToDownloads(tempURL, suggestedName: suggestedFilename)
                }
            }
        } catch {
        }
    }

    private func saveTempFileToDownloads(_ tempURL: URL, suggestedName: String) {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return
        }

        var destination = downloads.appendingPathComponent(suggestedName)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            let newName = "\(base)-\(counter)" + (ext.isEmpty ? "" : ".\(ext)")
            destination = downloads.appendingPathComponent(newName)
            counter += 1
        }

        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
            showSaveSuccessNotification(for: destination)
        } catch {
        }
    }

    private func mimeTypeToExtension(_ mimeType: String) -> String {
        if let type = UTType(mimeType: mimeType),
           let ext = type.preferredFilenameExtension {
            return ext
        }

        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        default: return "img"
        }
    }

    func contextMenuPayloadDidUpdate(_ payload: WebContextMenuPayload?) {
        pendingPayload = payload
        _ = applyPendingContextMenuIfPossible()
    }

    private func applyPendingContextMenuIfPossible() -> Bool {
        guard let payload = pendingPayload,
              payload.shouldProvideCustomMenu,
              let menu = pendingMenu else {
            return false
        }

        let items = WebContextMenuItem.buildMenuItems(for: payload, on: self, baseMenu: menu)
        guard !items.isEmpty else {
            return false
        }

        menu.items = items
        pendingMenu = nil
        pendingPayload = nil
        contextMenuFallbackWorkItem?.cancel()
        contextMenuFallbackWorkItem = nil
        owningSession?.pendingContextMenuPayload = nil
        return true
    }

    private func sanitizeDefaultMenu(_ menu: NSMenu) {
        let identifiersToRemove: [NSUserInterfaceItemIdentifier] = [
            .webKitCopyImage,
            NSUserInterfaceItemIdentifier("WKMenuItemIdentifierDownloadImage"),
            NSUserInterfaceItemIdentifier("WKMenuItemIdentifierDownloadLinkedFile"),
            NSUserInterfaceItemIdentifier("WKMenuItemIdentifierDownloadLinkedFileAs")
        ]

        menu.items = menu.items.filter { item in
            guard let id = item.identifier else { return true }
            return !identifiersToRemove.contains(id)
        }
        owningSession?.pendingContextMenuPayload = nil
    }
}
