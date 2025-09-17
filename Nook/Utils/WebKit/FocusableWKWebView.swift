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
                if (element && element.tagName === 'IMG') {
                    return element.src;
                }
                return null;
            })();
        """) { [weak self] result, error in
            DispatchQueue.main.async {
                if let imageURL = result as? String, !imageURL.isEmpty {
                    // Add "Save Image As..." menu item
                    let saveImageItem = NSMenuItem(title: "Save Image As...", action: #selector(self?.saveImageAs(_:)), keyEquivalent: "")
                    saveImageItem.target = self
                    saveImageItem.representedObject = imageURL
                    menu.insertItem(saveImageItem, at: 0)
                    menu.insertItem(NSMenuItem.separator(), at: 1)
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
}

