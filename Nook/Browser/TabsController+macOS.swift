//
//  TabsController+macOS.swift
//  Nook
//
//  The AppKit half of the tab model: the alert shown when the tab files could not be read.
//

import AppKit
import NookWeb

extension TabsController {
    private static var launchObserver: NSObjectProtocol?

    /// Shown once the app has finished launching, so it never blocks startup.
    static func presentReadOnlyAlert(reason: String, directory: URL) {
        let show = { @MainActor in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Tabs could not be loaded"
            alert.informativeText = "Nook is running without saving tab changes because \(reason). The files are in \(directory.path)."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        if NSRunningApplication.current.isFinishedLaunching {
            Task { @MainActor in show() }
            return
        }
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if let observer = launchObserver { NotificationCenter.default.removeObserver(observer) }
                launchObserver = nil
                show()
            }
        }
    }
}
