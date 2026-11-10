// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatIdle.swift
//  Nook
//
//  `chrome.idle`: whether the person is at the Mac, away from it, or has locked it. Password
//  managers lock their vault on this. While an extension listens and the person is active, one
//  timer runs per detection interval. Idle or locked, or with no listener, no timer runs.
//

import CoreGraphics
import Foundation
import WebKit

@MainActor
final class ExtensionCompatIdle: ExtensionCompatAPI {
    let name = "idle"
    let permission: String? = "idle"
    private weak var bridge: ExtensionCompatBridge?

    enum State: String { case active, idle, locked }
    static let event = "idle.onStateChanged"
    /// Chrome's bounds for a detection interval, in seconds, and its default.
    static let intervalRange: ClosedRange<TimeInterval> = 15...14_400
    static let defaultInterval: TimeInterval = 60

    /// Seconds since the last key, pointer or scroll input anywhere on the Mac.
    var idleSeconds: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
    /// Whether the screen is locked.
    var isLocked: () -> Bool = {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    }
    /// Calls back at the next input and returns how to stop waiting. The app supplies an event
    /// monitor: it is the only thing that ends the idle state short of a lock.
    var onNextInput: ((@escaping () -> Void) -> () -> Void)?
    /// Runs a closure once after a delay, in wall time so a sleeping Mac does not stretch it.
    /// A tenth of the wait is the system's to move, so the wakeup can share one with others.
    var after: (TimeInterval, @escaping () -> Void) -> () -> Void = { delay, work in
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + delay, leeway: .milliseconds(Int(delay * 100)))
        timer.setEventHandler(handler: DispatchWorkItem(block: work))
        timer.resume()
        return { timer.cancel() }
    }

    private final class Watch {
        weak var context: WKWebExtensionContext?
        var state: State
        init(_ context: WKWebExtensionContext, _ state: State) { self.context = context; self.state = state }
    }
    /// Extensions with an `onStateChanged` listener, by context identifier, with the state each was last told.
    private var watches: [String: Watch] = [:]
    private var intervals: [String: TimeInterval] = [:]
    private var observers: [NSObjectProtocol] = []
    /// What the lock notifications last said. They arrive before the session dictionary changes.
    private var lockSeen: Bool?
    private var cancelTimer: (() -> Void)?
    private var stopInput: (() -> Void)?

    init(bridge: ExtensionCompatBridge) { self.bridge = bridge }

    /// Whether anything is armed: a notification observer, the timer or the input monitor. For the harness and diagnostics.
    var isWatching: Bool { !observers.isEmpty || cancelTimer != nil || stopInput != nil }

    // MARK: - Rules

    static func state(locked: Bool, idleFor seconds: TimeInterval, interval: TimeInterval) -> State {
        locked ? .locked : seconds >= interval ? .idle : .active
    }

    /// An interval an extension asked for, inside Chrome's bounds. Nil when it is not a number.
    static func interval(_ value: Any?) -> TimeInterval? {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
        return min(max(number.doubleValue, intervalRange.lowerBound), intervalRange.upperBound)
    }

    /// Seconds until the earliest active watcher would turn idle. Nil when none is active: the
    /// input monitor ends the idle state, and the unlock notification the locked one.
    static func nextCheck(_ watchers: [(state: State, interval: TimeInterval)], idleFor seconds: TimeInterval) -> TimeInterval? {
        watchers.filter { $0.state == .active }.map { max($0.interval - seconds, 0) + 0.5 }.min()
    }

    // MARK: - ExtensionCompatAPI

    func call(_ method: String, _ arguments: [Any], from context: WKWebExtensionContext,
              reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void) {
        let id = context.uniqueIdentifier
        switch method {
        case "queryState":
            guard let interval = Self.interval(arguments.first) else {
                return reply(.failure(ExtensionCompatError("A detection interval in seconds is required.")))
            }
            reply(.success(Self.state(locked: locked, idleFor: idleSeconds(), interval: interval).rawValue))
        case "setDetectionInterval":
            guard let interval = Self.interval(arguments.first) else {
                return reply(.failure(ExtensionCompatError("A detection interval in seconds is required.")))
            }
            intervals[id] = interval
            if watches[id] != nil { evaluate() }
            reply(.success(nil))
        case "getAutoLockDelay":
            // ChromeOS only; Chrome answers 0 elsewhere.
            reply(.success(0))
        default:
            reply(.failure(ExtensionCompatError("idle.\(method) is not available")))
        }
    }

    func listenersChanged(_ context: WKWebExtensionContext) {
        let id = context.uniqueIdentifier
        let listening = bridge?.isListening(context, for: Self.event) == true
            && ExtensionCompatBridge.declares("idle", in: context)
        if !listening {
            watches[id] = nil
        } else if watches[id] == nil {
            // The state it starts from is not news.
            watches[id] = Watch(context, Self.state(locked: locked, idleFor: idleSeconds(), interval: interval(for: id)))
        }
        watchingChanged()
    }

    func contextUnloaded(_ context: WKWebExtensionContext) {
        watches[context.uniqueIdentifier] = nil
        intervals[context.uniqueIdentifier] = nil
        watchingChanged()
    }

    // MARK: - Watching

    private var locked: Bool { lockSeen ?? isLocked() }
    private func interval(for id: String) -> TimeInterval { intervals[id] ?? Self.defaultInterval }

    /// The lock notifications, the timer and the input monitor exist only while an extension listens.
    private func watchingChanged() {
        guard !watches.isEmpty else {
            observers.forEach(DistributedNotificationCenter.default().removeObserver)
            observers = []
            lockSeen = nil
            cancelTimer?(); cancelTimer = nil
            stopInput?(); stopInput = nil
            return
        }
        if observers.isEmpty {
            observers = [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)].map { name, locked in
                DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.screenLockChanged(locked) }
                }
            }
        }
        evaluate()
    }

    /// The screen locked or unlocked.
    func screenLockChanged(_ locked: Bool) {
        guard !watches.isEmpty else { return }
        lockSeen = locked
        evaluate()
    }

    /// Tells each watcher a change of state, then waits for the next moment one could change.
    private func evaluate() {
        let locked = self.locked, seconds = idleSeconds()
        for (id, watch) in watches {
            guard let context = watch.context else { watches[id] = nil; continue }
            let now = Self.state(locked: locked, idleFor: seconds, interval: interval(for: id))
            guard now != watch.state else { continue }
            watch.state = now
            bridge?.emit(Self.event, [now.rawValue], to: context)
        }
        cancelTimer?(); cancelTimer = nil
        if let delay = Self.nextCheck(watches.map { ($0.value.state, interval(for: $0.key)) }, idleFor: seconds) {
            cancelTimer = after(delay) { [weak self] in self?.evaluate() }
        }
        guard !watches.isEmpty else { return watchingChanged() }
        // While a watcher is idle, the next input is what makes it active again.
        if watches.values.contains(where: { $0.state == .idle }) {
            if stopInput == nil, let onNextInput { stopInput = onNextInput { [weak self] in self?.inputSeen() } }
        } else {
            stopInput?(); stopInput = nil
        }
    }

    private func inputSeen() {
        guard stopInput != nil else { return }
        stopInput?(); stopInput = nil
        evaluate()
    }
}
