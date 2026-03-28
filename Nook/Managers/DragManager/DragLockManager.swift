//
//  DragLockManager.swift
//  Nook
//
//  Harsh drag locker to prevent multiple simultaneous drag operations
//

import SwiftUI
import AppKit

@MainActor
class DragLockManager: ObservableObject {
    // MARK: - Shared Instance
    static let shared = DragLockManager()

    // MARK: - Drag Lock State
    @Published var isLocked: Bool = false
    @Published var lockOwner: String? = nil
    @Published var lockStartTime: Date? = nil

    // MARK: - Lock Operations

    func attemptLock(ownerID: String = UUID().uuidString) -> Bool {
        if isLocked {
            return false
        }

        isLocked = true
        lockOwner = ownerID
        lockStartTime = Date()
        return true
    }

    func releaseLock(ownerID: String = UUID().uuidString) {
        guard isLocked else {
            return
        }

        guard lockOwner == ownerID else {
            return
        }

        isLocked = false
        lockOwner = nil
        lockStartTime = nil
    }

    func forceReleaseAll() {
        isLocked = false
        lockOwner = nil
        lockStartTime = nil
    }

    // MARK: - Convenience Methods

    func canStartAnyDrag() -> Bool {
        return !isLocked
    }

    func startDrag(ownerID: String = UUID().uuidString) -> Bool {
        return attemptLock(ownerID: ownerID)
    }

    func endDrag(ownerID: String = UUID().uuidString) {
        releaseLock(ownerID: ownerID)
    }

    // MARK: - Debug Info

    var debugInfo: String {
        if isLocked {
            return "🔒 LOCKED by \(lockOwner ?? "unknown") for \(String(format: "%.2f", lockStartTime.map { Date().timeIntervalSince($0) } ?? 0))s"
        } else {
            return "🔓 UNLOCKED"
        }
    }
}