// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionManager+Updates.swift
//  Nook
//
//  Automatic updates for extensions installed from the Chrome Web Store, Edge Add-ons or Firefox
//  Add-ons, and the same daily pass for Safari imports and installs from before stable IDs.
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
        let entities = (try? context.fetch(FetchDescriptor<ExtensionEntity>())) ?? []
        // The first launch that can migrate does not wait out the day.
        let legacyWaiting = !defaults.bool(forKey: Self.migrationTriedKey)
            && entities.contains { Self.isLegacy(id: $0.id, sourceStore: $0.sourceStore) }
        guard !isCheckingForUpdates,
              legacyWaiting || Date().timeIntervalSince1970 - lastCheck > Self.updateInterval
        else { return }

        let candidates: [(id: String, store: ExtensionStore, version: String, name: String)] =
            entities.compactMap { entity in
                guard let store = entity.sourceStore.flatMap(ExtensionStore.init(rawValue:)) else { return nil }
                return (entity.id, store, entity.version, entity.name)
            }
        guard !entities.isEmpty else { return }

        isCheckingForUpdates = true

        Task(priority: .utility) { @MainActor [weak self] in
            // Stay clear of launch and activation work.
            try? await Task.sleep(for: .seconds(30))
            // Marked once the pass starts, so a quit during the wait leaves it due.
            defaults.set(Date().timeIntervalSince1970, forKey: Self.lastUpdateCheckKey)
            defaults.set(true, forKey: Self.migrationTriedKey)
            await self?.migrateLegacyInstalls()
            await self?.refreshSafariImports()
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
