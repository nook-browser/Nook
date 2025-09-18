import AppKit
import WebKit

// Simple subclass to ensure clicking a webview focuses its tab in the app state
final class FocusableWKWebView: WKWebView {
    weak var owningTab: Tab?

    override func mouseDown(with event: NSEvent) {
        owningTab?.activate()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        owningTab?.activate()
        super.rightMouseDown(with: event)
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

#if DEBUG
                if let href = info["href"] as? String, !href.isEmpty, let url = URL(string: href) {
                    let openMiniWindowItem = NSMenuItem(
                        title: "Open Link in Mini Window",
                        action: #selector(self.openLinkInMiniWindow(_:)),
                        keyEquivalent: ""
                    )
                    openMiniWindowItem.target = self
                    openMiniWindowItem.representedObject = url
                    customItems.append(openMiniWindowItem)
                }
#endif

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
        let notification = NSUserNotification()
        notification.title = "Image Saved"
        notification.informativeText = "Saved to \(url.lastPathComponent)"
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func showSaveErrorNotification(error: Error) {
        let notification = NSUserNotification()
        notification.title = "Save Failed"
        notification.informativeText = error.localizedDescription
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
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
