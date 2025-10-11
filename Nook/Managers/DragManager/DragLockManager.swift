//
//  DragLockManager.swift
//  Nook
//
//  Harsh drag locker to prevent multiple simultaneous drag operations
//

import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
class DragLockManager {
    // MARK: - Shared Instance
    static let shared = DragLockManager()

    // MARK: - Drag Lock State
    var isLocked: Bool = false
    var lockOwner: String? = nil
    var lockStartTime: Date? = nil

    // MARK: - Lock Operations

    func attemptLock(ownerID: String = UUID().uuidString) -> Bool {
        if isLocked {
            print("🔒 [DragLockManager] Lock DENIED - Already locked by \(lockOwner ?? "unknown")")
            return false
        }

        print("🔒 [DragLockManager] Universal Lock ACQUIRED [\(ownerID)]")
        isLocked = true
        lockOwner = ownerID
        lockStartTime = Date()
        return true
    }

    func releaseLock(ownerID: String = UUID().uuidString) {
        guard isLocked else {
            print("🔓 [DragLockManager] Lock RELEASE - No active lock")
            return
        }

        guard lockOwner == ownerID else {
            print("⚠️ [DragLockManager] Lock RELEASE DENIED - Current owner: \(lockOwner ?? "unknown"), Requester: \(ownerID)")
            return
        }

        let lockDuration = lockStartTime.map { Date().timeIntervalSince($0) } ?? 0
        print("🔓 [DragLockManager] Universal Lock RELEASED [\(ownerID)] after \(String(format: "%.2f", lockDuration))s")

        isLocked = false
        lockOwner = nil
        lockStartTime = nil
    }

    func forceReleaseAll() {
        if isLocked {
            print("💥 [DragLockManager] FORCE RELEASE all locks (was locked by \(lockOwner ?? "unknown"))")
        }
        isLocked = false
        lockOwner = nil
        lockStartTime = nil
    }

    // MARK: - Convenience Methods

    func canStartAnyDrag() -> Bool {
        let canStart = !isLocked
        if !canStart {
            print("🚫 [DragLockManager] Drag BLOCKED - Already locked by \(lockOwner ?? "unknown")")
        }
        return canStart
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
