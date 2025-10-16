//
//  TweakPanelWindowController.swift
//  Nook
//
//  Created by Claude Code on 16/10/2025.
//

import AppKit

class TweakPanelWindowController: NSObject {
    private var panel: TweakPanelWindow?
    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        super.init()
        self.browserManager = browserManager
    }

    func showTweakPanel() {
        if panel == nil {
            panel = TweakPanelWindow(browserManager: browserManager!)
        }

        panel?.showPanel()
    }

    func hideTweakPanel() {
        panel?.hidePanel()
    }

    func toggleTweakPanel() {
        if let panel = panel, panel.isVisible {
            hideTweakPanel()
        } else {
            showTweakPanel()
        }
    }

    func isPanelVisible() -> Bool {
        return panel?.isVisible ?? false
    }

    deinit {
        panel?.close()
        panel = nil
    }
}