// Licensed under GPL-3.0. See LICENSE.
//
//  PeekSession.swift
//  Nook
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import Foundation
import SwiftUI
import NookWeb

@MainActor
class PeekSession: ObservableObject, Identifiable {
    let id = UUID()
    let sourceTabId: UUID?
    let sourceURL: URL?
    let targetURL: URL
    let windowId: UUID
    /// The source page's profile. A private page's ephemeral one has no space id to look up.
    let sourceProfile: Profile?

    @Published var currentURL: URL
    @Published var title: String
    @Published var isLoading: Bool = true
    @Published var estimatedProgress: Double = 0
    @Published var toolbarColor: NSColor?

    init(
        targetURL: URL,
        sourceTabId: UUID?,
        sourceURL: URL?,
        windowId: UUID,
        sourceProfile: Profile? = nil
    ) {
        self.targetURL = targetURL
        self.sourceTabId = sourceTabId
        self.sourceURL = sourceURL
        self.windowId = windowId
        self.sourceProfile = sourceProfile
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
