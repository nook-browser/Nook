import SwiftUI

@MainActor
@Observable
final class CommandPaletteCoordinator {
    static let shared = CommandPaletteCoordinator()
    private init() {}

    var isCommandPaletteVisible: Bool = false
    var isMiniCommandPaletteVisible: Bool = false
    var commandPalettePrefilledText: String = ""
    var shouldNavigateCurrentTab: Bool = false
    var urlBarFrame: CGRect = .zero

    // MARK: - Public API

    func openCommandPalette(using browserManager: BrowserManager) {
        guard let target = browserManager.activeWindow ?? browserManager.windowStateManager.windowStates.values.first else {
            commandPalettePrefilledText = ""
            shouldNavigateCurrentTab = false
            isMiniCommandPaletteVisible = false
            DispatchQueue.main.async { self.isCommandPaletteVisible = true }
            return
        }
        showCommandPalette(in: target, prefill: "", navigateCurrentTab: false, using: browserManager)
    }

    func openCommandPaletteWithCurrentURL(using browserManager: BrowserManager) {
        guard let target = browserManager.activeWindow ?? browserManager.windowStateManager.windowStates.values.first else {
            openCommandPalette(using: browserManager)
            return
        }
        let prefill = browserManager.currentTab(for: target)?.url.absoluteString ?? ""
        showCommandPalette(in: target, prefill: prefill, navigateCurrentTab: true, using: browserManager)
    }

    func closeCommandPalette(using browserManager: BrowserManager, windowState: BrowserWindowState? = nil) {
        let targets: [BrowserWindowState]
        if let windowState {
            targets = [windowState]
        } else {
            targets = Array(browserManager.windowStateManager.windowStates.values)
        }

        for state in targets {
            state.isCommandPaletteVisible = false
            state.isMiniCommandPaletteVisible = false
            state.shouldNavigateCurrentTab = false
            state.commandPalettePrefilledText = ""
        }

        if windowState == nil || windowState?.id == browserManager.activeWindow?.id {
            isCommandPaletteVisible = false
            isMiniCommandPaletteVisible = false
            shouldNavigateCurrentTab = false
            commandPalettePrefilledText = ""
        }
    }

    func toggleCommandPalette(using browserManager: BrowserManager) {
        if let target = browserManager.activeWindow {
            if target.isCommandPaletteVisible {
                closeCommandPalette(using: browserManager, windowState: target)
            } else {
                openCommandPalette(using: browserManager)
            }
        } else {
            openCommandPalette(using: browserManager)
        }
    }

    func showMiniCommandPalette(using browserManager: BrowserManager, in windowState: BrowserWindowState, prefill: String) {
        for state in browserManager.windowStateManager.windowStates.values where state.id != windowState.id {
            state.isMiniCommandPaletteVisible = false
        }

        windowState.commandPalettePrefilledText = prefill
        windowState.shouldNavigateCurrentTab = true
        windowState.isCommandPaletteVisible = false
        DispatchQueue.main.async {
            windowState.isMiniCommandPaletteVisible = true
        }

        commandPalettePrefilledText = prefill
        shouldNavigateCurrentTab = true
        isCommandPaletteVisible = false
        isMiniCommandPaletteVisible = true
    }

    func hideMiniCommandPalette(using browserManager: BrowserManager, windowState: BrowserWindowState? = nil) {
        let targets: [BrowserWindowState]
        if let windowState {
            targets = [windowState]
        } else {
            targets = Array(browserManager.windowStateManager.windowStates.values)
        }

        for state in targets {
            state.isMiniCommandPaletteVisible = false
            state.shouldNavigateCurrentTab = false
            state.commandPalettePrefilledText = ""
        }

        if windowState == nil || windowState?.id == browserManager.activeWindow?.id {
            isMiniCommandPaletteVisible = false
            shouldNavigateCurrentTab = false
            commandPalettePrefilledText = ""
        }
    }

    func showFindBar(using browserManager: BrowserManager) {
        if browserManager.findManager.isFindBarVisible {
            browserManager.findManager.hideFindBar()
        } else {
            browserManager.findManager.showFindBar(for: browserManager.currentTabForActiveWindow())
        }
    }

    func updateFindManagerCurrentTab(using browserManager: BrowserManager) {
        browserManager.findManager.updateCurrentTab(browserManager.currentTabForActiveWindow())
    }

    func focusURLBar(using browserManager: BrowserManager) {
        guard let target = browserManager.activeWindow ?? browserManager.windowStateManager.windowStates.values.first else { return }
        let prefill = browserManager.currentTab(for: target)?.url.absoluteString ?? ""
        showMiniCommandPalette(using: browserManager, in: target, prefill: prefill)
    }

    func sync(from windowState: BrowserWindowState?) {
        isCommandPaletteVisible = windowState?.isCommandPaletteVisible ?? false
        isMiniCommandPaletteVisible = windowState?.isMiniCommandPaletteVisible ?? false
        commandPalettePrefilledText = windowState?.commandPalettePrefilledText ?? ""
        shouldNavigateCurrentTab = windowState?.shouldNavigateCurrentTab ?? false
        urlBarFrame = windowState?.urlBarFrame ?? .zero
    }

    func updateURLBarFrame(_ frame: CGRect, for windowState: BrowserWindowState, browserManager: BrowserManager) {
        urlBarFrame = frame
        windowState.urlBarFrame = frame
    }

    // MARK: - Private helpers

    private func showCommandPalette(in windowState: BrowserWindowState, prefill: String, navigateCurrentTab: Bool, using browserManager: BrowserManager) {
        for state in browserManager.windowStateManager.windowStates.values where state.id != windowState.id {
            state.isCommandPaletteVisible = false
            state.isMiniCommandPaletteVisible = false
        }

        windowState.commandPalettePrefilledText = prefill
        windowState.shouldNavigateCurrentTab = navigateCurrentTab
        windowState.isMiniCommandPaletteVisible = false
        DispatchQueue.main.async {
            windowState.isCommandPaletteVisible = true
        }

        commandPalettePrefilledText = prefill
        shouldNavigateCurrentTab = navigateCurrentTab
        isMiniCommandPaletteVisible = false
        isCommandPaletteVisible = true
    }
}

// MARK: - Environment Support

@MainActor
private struct NookCommandPaletteKey: EnvironmentKey {
    static let defaultValue: CommandPaletteCoordinator = .shared
}

extension EnvironmentValues {
    @MainActor var nookCommandPalette: CommandPaletteCoordinator {
        get { self[NookCommandPaletteKey.self] }
        set { self[NookCommandPaletteKey.self] = newValue }
    }
}
