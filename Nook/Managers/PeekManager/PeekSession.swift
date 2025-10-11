//
//  PeekSession.swift
//  Nook
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import Foundation
import WebKit
import SwiftUI
import Observation

@MainActor
@Observable
class PeekSession: Identifiable {
    let id = UUID()
    let sourceTabId: UUID?
    let sourceURL: URL?
    let targetURL: URL
    let windowId: UUID
    let sourceProfileId: UUID?

    var currentURL: URL
    var title: String
    var isLoading: Bool = true
    var estimatedProgress: Double = 0
    var toolbarColor: NSColor?

    init(
        targetURL: URL,
        sourceTabId: UUID?,
        sourceURL: URL?,
        windowId: UUID,
        sourceProfileId: UUID? = nil
    ) {
        self.targetURL = targetURL
        self.sourceTabId = sourceTabId
        self.sourceURL = sourceURL
        self.windowId = windowId
        self.sourceProfileId = sourceProfileId
        self.currentURL = targetURL
        self.title = targetURL.absoluteString
    }

    func updateNavigationState(url: URL?, title: String?) {
        if let url { currentURL = url }
        if let title, !title.isEmpty { self.title = title }
    }

    func updateLoading(isLoading: Bool) {
        self.isLoading = isLoading
    }

    func updateProgress(_ progress: Double) {
        estimatedProgress = progress
    }

    func updateToolbarColor(hexString: String?) {
        guard let trimmed = hexString?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            toolbarColor = nil
            return
        }

        if let color = NSColor(hex: trimmed) {
            toolbarColor = color.usingColorSpace(.sRGB)
        } else {
            toolbarColor = nil
        }
    }
}
