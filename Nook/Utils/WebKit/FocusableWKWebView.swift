import AppKit
import WebKit
import UserNotifications

// Simple subclass to ensure clicking a webview focuses its tab in the app state
final class FocusableWKWebView: WKWebView {
    weak var owningTab: Tab?

    override func mouseDown(with event: NSEvent) {
        // Store Option key state for Peek functionality
        owningTab?.isOptionKeyDown = event.modifierFlags.contains(.option)

        owningTab?.activate()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        owningTab?.activate()
        super.rightMouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        // Reset Option key state after mouse up
        owningTab?.isOptionKeyDown = false
        super.mouseUp(with: event)
    }
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // Get the element under the mouse cursor
        let point = convert(event.locationInWindow, from: nil)
        evaluateJavaScript("""
            (function() {
                var element = document.elementFromPoint(\(point.x), \(point.y));
                var imageSrc = null;
                var linkHref = null;

                if (element) {
                    if (element.tagName === 'IMG' && element.src) {
                        imageSrc = element.src;
                    }

                    var anchor = element.closest ? element.closest('a') : null;
                    if (anchor && anchor.href) {
                        linkHref = anchor.href;
                    }
                }

                return {
                    image: imageSrc,
                    href: linkHref
                };
            })();
        """) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, let info = result as? [String: Any] else { return }

                var customItems: [NSMenuItem] = []

                  if let href = info["href"] as? String, !href.isEmpty, let url = URL(string: href) {
                    // Check if this is an external domain and we're not in a mini window
                    if let currentHost = self.owningTab?.url.host,
                       let newHost = url.host,
                       currentHost != newHost,
                       self.owningTab?.browserManager != nil {

                        let openPeekItem = NSMenuItem(
                            title: "Peek Link",
                            action: #selector(self.openLinkInPeek(_:)),
                            keyEquivalent: ""
                        )
                        openPeekItem.target = self
                        openPeekItem.representedObject = url
                        customItems.append(openPeekItem)
                    }

#if DEBUG
                    let openMiniWindowItem = NSMenuItem(
                        title: "Open Link in Mini Window",
                        action: #selector(self.openLinkInMiniWindow(_:)),
                        keyEquivalent: ""
                    )
                    openMiniWindowItem.target = self
                    openMiniWindowItem.representedObject = url
                    customItems.append(openMiniWindowItem)
#endif
                }

                if let imageURL = info["image"] as? String, !imageURL.isEmpty {
                    let saveImageItem = NSMenuItem(
                        title: "Save Image As...",
                        action: #selector(self.saveImageAs(_:)),
                        keyEquivalent: ""
                    )
                    saveImageItem.target = self
                    saveImageItem.representedObject = imageURL
                    customItems.append(saveImageItem)
                }

                if !customItems.isEmpty {
                    customItems.append(NSMenuItem.separator())
                    for (index, item) in customItems.enumerated() {
                        menu.insertItem(item, at: index)
                    }
                }
            }
        }
    }
    
    @objc private func saveImageAs(_ sender: NSMenuItem) {
        guard let imageURL = sender.representedObject as? String,
              let url = URL(string: imageURL) else { return }
        
        // Create a download task
        let task = URLSession.shared.downloadTask(with: url) { [weak self] localURL, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔽 [FocusableWKWebView] Download failed: \(error.localizedDescription)")
                    return
                }
                
                guard let localURL = localURL else {
                    print("🔽 [FocusableWKWebView] No local URL returned")
                    return
                }
                
                // Show the save dialog
                self?.showSaveDialog(for: localURL, originalURL: url, response: response)
            }
        }
        
        task.resume()
    }
    
    private func showSaveDialog(for localURL: URL, originalURL: URL, response: URLResponse?) {
        let savePanel = NSSavePanel()
        
        // Set the suggested filename
        let suggestedFilename = response?.suggestedFilename ?? originalURL.lastPathComponent
        savePanel.nameFieldStringValue = suggestedFilename
        
        // Set the default directory to Downloads
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloads
        }
        
        // Set allowed file types for images
        savePanel.allowedContentTypes = [
            .jpeg, .png, .gif, .bmp, .tiff, .webP, .heic, .heif
        ]
        
        // Set the title and message
        savePanel.title = "Save Image"
        savePanel.message = "Choose where to save the image"
        
        // Show the save dialog
        savePanel.begin { [weak self] result in
            if result == .OK, let destinationURL = savePanel.url {
                do {
                    // Move the downloaded file to the chosen location
                    try FileManager.default.moveItem(at: localURL, to: destinationURL)
                    print("🔽 [FocusableWKWebView] Image saved to: \(destinationURL.path)")
                    
                    // Show a success notification
                    self?.showSaveSuccessNotification(for: destinationURL)
                } catch {
                    print("🔽 [FocusableWKWebView] Failed to save image: \(error.localizedDescription)")
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
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "focusable-webview-\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            )
            center.add(request, withCompletionHandler: nil)
        }
    }

  @objc private func openLinkInPeek(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        Task { @MainActor [weak self] in
            guard let tab = self?.owningTab else { return }
            tab.browserManager?.peekManager.presentExternalURL(url, from: tab)
        }
    }

#if DEBUG
    @objc private func openLinkInMiniWindow(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        Task { @MainActor [weak self] in
            guard let tab = self?.owningTab else { return }
            tab.browserManager?.presentExternalURL(url)
        }
    }
#endif
}
