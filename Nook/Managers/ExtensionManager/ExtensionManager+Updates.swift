// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  ExtensionManager+Updates.swift
//  Nook
//
//  Automatic updates for extensions installed from the Chrome Web Store or Edge Add-ons.
//

import AppKit
import Foundation
import os
import SwiftData

extension ExtensionManager {

    private static let updateInterval: TimeInterval = 24 * 60 * 60

    /// Check store-installed extensions for new versions at most once a day. Runs after
    /// extensions load and when the app becomes active; there is no timer. Updates that
    /// request new permissions are skipped until the user reinstalls from the store.
    func checkForExtensionUpdatesIfDue() {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.double(forKey: Self.lastUpdateCheckKey)
        guard !isCheckingForUpdates,
              Date().timeIntervalSince1970 - lastCheck > Self.updateInterval
        else { return }

        let candidates: [(id: String, store: ExtensionStore, version: String, name: String)] =
            ((try? context.fetch(FetchDescriptor<ExtensionEntity>())) ?? []).compactMap { entity in
                guard let store = entity.sourceStore.flatMap(ExtensionStore.init(rawValue:)) else { return nil }
                return (entity.id, store, entity.version, entity.name)
            }
        guard !candidates.isEmpty else { return }

        isCheckingForUpdates = true
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastUpdateCheckKey)

        Task(priority: .utility) { @MainActor [weak self] in
            // Stay clear of launch and activation work.
            try? await Task.sleep(for: .seconds(30))
            for candidate in candidates {
                guard let newVersion = await WebStoreDownloader.availableUpdate(
                    extensionId: candidate.id, store: candidate.store, currentVersion: candidate.version
                ) else { continue }
                Self.logger.info("Updating '\(candidate.name, privacy: .public)' \(candidate.version, privacy: .public) -> \(newVersion, privacy: .public)")
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    guard let self else { return continuation.resume() }
                    self.installFromWebStore(
                        extensionId: candidate.id, store: candidate.store, interactive: false
                    ) { result in
                        if case .failure(let error) = result, !(error.isCancelled) {
                            Self.logger.error("Update failed for '\(candidate.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                        }
                        continuation.resume()
                    }
                }
            }
            self?.isCheckingForUpdates = false
        }
    }
}

private extension ExtensionError {
    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}
