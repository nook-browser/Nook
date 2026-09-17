import AppKit
import NookSettings
import NookTabsCore
import WebKit

// MARK: - Tab Compositor Manager

/// Unloads pages no window shows: idle timeout, loaded-page budget, memory pressure and app
/// backgrounding, per the tab management mode. Visible panes, media, capture, pinned tabs and
/// favorites are exempt.
@MainActor
class TabCompositorManager: ObservableObject {
    private var unloadTimers: [UUID: Timer] = [:]
    private var lastAccessTimes: [UUID: Date] = [:]
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var appResignObserver: Any?
    private var lastMemoryPressureTime: Date?
    private var budgetRetryTimer: Timer?

    weak var browserManager: BrowserManager?

    var allowsBackgroundWarming: Bool {
        !ProcessInfo.processInfo.isLowPowerModeEnabled
            && (lastMemoryPressureTime.map { Date().timeIntervalSince($0) >= 60 } ?? true)
    }

    private(set) var mode: TabManagementMode = .standard

    private var tabs: TabsController? { browserManager?.tabs }

    init() {
        setupMemoryPressureMonitoring()
    }

    deinit {
        memoryPressureSource?.cancel()
        budgetRetryTimer?.invalidate()
        unloadTimers.values.forEach { $0.invalidate() }
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Mode Configuration

    func setMode(_ newMode: TabManagementMode) {
        mode = newMode
        restartAllTimers()
        if newMode.unloadsOnBackground {
            setupBackgroundMonitoring()
        } else {
            teardownBackgroundMonitoring()
        }
        enforceMaxLoadedTabs()
    }

    // MARK: - Access & Loading

    func markTabAccessed(_ itemID: UUID) {
        lastAccessTimes[itemID] = Date()
        // The compositor marks the selected page on every SwiftUI update (hover, resize).
        // A timer rescheduled within the last minute is close enough; handleTimeout re-arms
        // for any remaining time.
        if let timer = unloadTimers[itemID], timer.isValid,
           timer.fireDate.timeIntervalSinceNow > mode.unloadTimeout - 60 {
            return
        }
        restartTimer(for: itemID)
    }

    func load(_ session: PageSession) {
        markTabAccessed(session.itemID)
        session.loadWebViewIfNeeded()
        if mode.maxLoadedTabs != nil {
            enforceMaxLoadedTabs()
        }
    }

    /// Automatic eviction of a page no window shows.
    private func evict(_ session: PageSession) {
        forget(session.itemID)
        session.unload()
    }

    func forget(_ itemID: UUID) {
        unloadTimers[itemID]?.invalidate()
        unloadTimers.removeValue(forKey: itemID)
        lastAccessTimes.removeValue(forKey: itemID)
    }

    // MARK: - Timer Management

    private func restartTimer(for itemID: UUID, after interval: TimeInterval? = nil) {
        unloadTimers[itemID]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval ?? mode.unloadTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimeout(itemID)
            }
        }
        unloadTimers[itemID] = timer
    }

    private func restartAllTimers() {
        unloadTimers.values.forEach { $0.invalidate() }
        unloadTimers.removeAll()
        for itemID in lastAccessTimes.keys {
            restartTimer(for: itemID)
        }
    }

    private func handleTimeout(_ itemID: UUID) {
        unloadTimers.removeValue(forKey: itemID)
        // Closed or already unloaded: nothing to time out until the page is accessed again.
        guard let session = tabs?.session(for: itemID), !session.isUnloaded else {
            lastAccessTimes.removeValue(forKey: itemID)
            return
        }
        // Pinned tabs and favorites are never unloaded automatically, so re-arming would only
        // wake the app.
        if isPinned(itemID) { return }

        if let lastAccess = lastAccessTimes[itemID] {
            let remaining = mode.unloadTimeout - Date().timeIntervalSince(lastAccess)
            if remaining > 1 {
                restartTimer(for: itemID, after: remaining)
                return
            }
        }

        guard canUnloadInactive(session) else {
            restartTimer(for: itemID)
            return
        }
        evict(session)
    }

    // MARK: - Exemptions

    /// Pinned tabs and favorites (the synced sections).
    private func isPinned(_ itemID: UUID) -> Bool {
        switch tabs?.section(of: itemID) {
        case .pinned, .favorites: return true
        default: return false
        }
    }

    /// Shared eligibility for automatic eviction and bulk hidden-page unloading. A user
    /// unloading one page deliberately bypasses this policy.
    func canUnloadInactive(_ session: PageSession) -> Bool {
        guard let tabs, !session.isUnloaded, !tabs.isVisibleInAnyWindow(session.itemID) else { return false }
        if session.hasPiPActive || session.hasPlayingVideo || session.hasPlayingAudio || session.hasAudioContent {
            return false
        }
        var views = browserManager?.webViewCoordinator?.getAllWebViews(for: session.itemID) ?? []
        if let primary = session.webView { views.append(primary) }
        if views.contains(where: { $0.cameraCaptureState != .none || $0.microphoneCaptureState != .none }) {
            return false
        }
        return !isPinned(session.itemID)
    }

    /// Higher keeps the page longer.
    private func importance(_ session: PageSession) -> Int {
        var score = 0
        if tabs?.isVisibleInAnyWindow(session.itemID) == true { score += 1000 }
        if session.hasPlayingVideo || session.hasPlayingAudio || session.hasAudioContent { score += 500 }
        if isPinned(session.itemID) { score += 200 }
        if let lastAccess = lastAccessTimes[session.itemID] {
            let minutesAgo = Date().timeIntervalSince(lastAccess) / 60
            score += max(0, 100 - Int(minutesAgo))
        }
        return score
    }

    // MARK: - Memory Pressure

    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleMemoryPressure()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressure() {
        // Act at most once per 30 seconds.
        let now = Date()
        if let lastTime = lastMemoryPressureTime, now.timeIntervalSince(lastTime) < 30 { return }
        lastMemoryPressureTime = now

        guard let sessions = tabs?.sessions else { return }
        let candidates = sessions.filter(canUnloadInactive).sorted { importance($0) < importance($1) }
        guard !candidates.isEmpty else { return }

        let count: Int
        if let keepCount = mode.memoryPressureKeepCount {
            // Power Saving: unload all but the selected page and keepCount most recent.
            let loaded = sessions.filter { !$0.isUnloaded }.count
            count = max(0, loaded - 1 - keepCount)
        } else {
            count = Int(ceil(Double(candidates.count) * mode.memoryPressureUnloadFraction))
        }
        candidates.prefix(count).forEach(evict)
    }

    // MARK: - Background Unloading

    private func setupBackgroundMonitoring() {
        teardownBackgroundMonitoring()
        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidResignActive()
            }
        }
    }

    private func teardownBackgroundMonitoring() {
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }
    }

    private func handleAppDidResignActive() {
        guard mode.unloadsOnBackground, let sessions = tabs?.sessions else { return }
        sessions.filter(canUnloadInactive).forEach(evict)
    }

    // MARK: - Loaded Page Budget

    private func enforceMaxLoadedTabs() {
        budgetRetryTimer?.invalidate()
        budgetRetryTimer = nil
        guard let maxTabs = mode.maxLoadedTabs, let sessions = tabs?.sessions else { return }

        // canUnloadInactive already leaves pinned tabs and favorites out of the count.
        let loaded = sessions.filter(canUnloadInactive)
        guard loaded.count > maxTabs else { return }

        // Grace period: pages accessed within the last 30 seconds stay.
        let gracePeriod: TimeInterval = 30
        let now = Date()
        let eligible = loaded.filter { session in
            guard let lastAccess = lastAccessTimes[session.itemID] else { return true }
            return now.timeIntervalSince(lastAccess) > gracePeriod
        }
        let toUnload = eligible.sorted { importance($0) < importance($1) }.prefix(max(0, loaded.count - maxTabs))
        toUnload.forEach(evict)

        // A burst can exceed the budget while every page is inside its grace period. Retry once
        // at the next expiry rather than waiting for another user action.
        if loaded.count - toUnload.count > maxTabs,
           let nextExpiry = loaded.compactMap({ session -> Date? in
               guard let accessed = lastAccessTimes[session.itemID] else { return nil }
               let expiry = accessed.addingTimeInterval(gracePeriod)
               return expiry > now ? expiry : nil
           }).min() {
            budgetRetryTimer = Timer.scheduledTimer(
                withTimeInterval: max(0.05, nextExpiry.timeIntervalSinceNow), repeats: false
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.enforceMaxLoadedTabs() }
            }
        }
    }
}
