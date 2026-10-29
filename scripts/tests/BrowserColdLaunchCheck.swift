// Licensed under GPL-3.0. See LICENSE.
// Runs the real SwiftUI application, launched by macOS with an external URL.
import AppKit
import SwiftUI
import NookSettings
import NookTabsCore
import NookWeb
@testable import Nook

@main
struct BrowserColdLaunchCheck {
    @MainActor
    static func main() {
        precondition(Bundle.main.bundleIdentifier?.hasPrefix("com.nook.window-check.") == true,
                     "Run through check-browser-windows.py to isolate application data")

        let defaults = UserDefaults.standard
        let report = URL(fileURLWithPath: defaults.string(forKey: "NookColdCheckReport")!)
        let scenario = defaults.string(forKey: "NookColdCheckCase")!
        let expectedWindows = scenario == "restored" ? 2 : 1
        let routed = scenario != "tabs"
        let incoming = URL(string: "https://window-check.invalid/\(scenario)")!
        let personal = UUID()
        let work = UUID()
        let settings = NookSettingsService()
        let store = TabStore(directory: TabsController.defaultDirectory)
        var tree = TabTree.firstLaunch(spaceID: personal, homeURL: URL(string: "about:blank")!)
        var device = DeviceState()

        settings.didFinishOnboarding = true
        settings.externalLinksInMiniWindow = routed
        tree.createSpace(id: work, name: "Work", icon: "briefcase", accentHex: "#777777", after: personal)
        settings.siteRoutingRules = routed ? [SiteRoutingRule(domain: "window-check.invalid", targetSpaceId: work)] : []
        device.firstLaunchCompleted = true
        device.windows = scenario == "no-windows" ? [] : (0..<expectedWindows).map { _ in WindowRecord(spaceID: personal) }
        store.save(tree, device)
        store.flush()

        _ = Task { @MainActor in
            // Wait for launch, URL delivery, restoration, and debounced persistence to settle.
            try await Task.sleep(for: .seconds(5))

            let state = store.load()
            let tabs = state.tree.items.values.filter { $0.url == incoming }
            let windows = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
            let minis = NSApp.windows.filter { $0.isVisible && $0 is MiniBrowserWindow }
            let nativeTabs = windows.contains { ($0.tabbedWindows?.count ?? 0) > 1 }
            let tabbingDisabled = !NSWindow.allowsAutomaticWindowTabbing && windows.allSatisfy { $0.tabbingMode == .disallowed }
            let targetCorrect = tabs.count == 1 && (!routed || state.tree.spaceID(of: tabs[0].id) == work)
            let passed = windows.count == expectedWindows && state.device.windows.count == expectedWindows
                && minis.isEmpty && targetCorrect && !nativeTabs && tabbingDisabled
            let result: [String: Any] = ["passed": passed, "scenario": scenario,
                "visibleWindows": windows.count, "savedWindows": state.device.windows.count,
                "urlOccurrences": tabs.count, "miniWindows": minis.count, "targetCorrect": targetCorrect,
                "nativeWindowTabs": nativeTabs, "nativeTabbingDisabled": tabbingDisabled]

            try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(to: report)
            exit(passed ? 0 : 1)
        }

        NookApp.main()
    }
}
