#!/usr/bin/env python3
"""Run production lifecycle methods against lightweight WebView/window fixtures."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]

def method(path, signature):
    source = (root / path).read_text()
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end] + '\n'

tab = 'Nook/Models/Tab/Tab.swift'
compositor = 'Nook/Components/Browser/Window/TabCompositorView.swift'
source = r'''
import Foundation

enum Capture { case none, active }
class BackForwardList { var currentItem: Int? = 1 }
class View {
    var cameraCaptureState = Capture.none, microphoneCaptureState = Capture.none
    var reloadCount = 0, loadCount = 0
    let backForwardList = BackForwardList()
    func reload() -> Int? { reloadCount += 1; return 1 }
}
class Cancellable { func cancel() {} }
struct Signposter {
    func beginInterval(_ name: String) -> Int { 0 }
    func endInterval(_ name: String, _ state: Int) {}
}
enum BrowserPerformance { static let signposter = Signposter() }
class Coordinator {
    var views: [UUID: [View]] = [:]
    func getAllWebViews(for id: UUID) -> [View] { views[id] ?? [] }
    func removeAllWebViews(for tab: Tab) { views[tab.id] = nil }
}
struct Window { let id: UUID; var currentTabId: UUID? }
class WindowState { var currentTabId: UUID?; var refreshes = 0; func refreshCompositor() { refreshes += 1 } }
struct Split { var isSplit: Bool; let leftTabId: UUID; let rightTabId: UUID }
class Registry { var allWindows: [Window] = []; var windows: [UUID: WindowState] = [:] }
class SplitManager {
    var states: [UUID: Split] = [:]
    func getSplitState(for id: UUID) -> Split? { states[id] }
}
class Browser {
    var windowRegistry: Registry? = Registry()
    var webViewCoordinator: Coordinator? = Coordinator()
    let splitManager = SplitManager()
}
class Tab {
    let id = UUID()
    var browserManager: Browser?
    let url = URL(string: "https://popup.example/destination")!
    var loadedURLs: [URL] = []
    func loadURL(_ url: URL) { loadedURLs.append(url) }
    static func loadPage(_ url: URL, in view: View) { view.loadCount += 1 }
    var recreated = 0
    func loadWebViewIfNeeded() { recreated += 1; _webView = View() }
    var _webView: View?, _existingWebView: View?
    var existingWebView: View? { _webView }
    var isUnloaded: Bool { _webView == nil }
    var primaryWindowId: UUID?
    var isPopupHost = false, isCurrentTab = false, isPinned = false, isSpacePinned = false
    var hasPiPActive = false, hasPlayingVideo = false, hasPlayingAudio = false
    var hasAudioContent = false, hasVideoContent = false
    var spaPersistDebounceTask: Cancellable?, profileAwaitCancellable: Cancellable?, extensionAwaitCancellable: Cancellable?
    var webStoreHandler: String?
    enum Loading { case idle, didStartProvisionalNavigation }
    var loadingState = Loading.idle
    func stopNativeAudioMonitoring() {}
    func cleanupCloneWebView(_ view: View) {}
'''
source += method(tab, '    func unloadWebView()')
source += method(tab, '    func refresh()')
source += method(tab, '    public func performComprehensiveWebViewCleanup()')
# Run the exact navigation decision at the end of successful production setup.
# WebKit construction/delegate registration itself remains outside this fixture.
setup = method(tab, '    private func setupWebView()')
source += '    func finishSetup() {\n' + setup[setup.index('        // Consume popup suppression'):]

source += '\n}\nclass Compositor {\n var browserManager: Browser?\n'
source += method(compositor, '    func canUnloadInactiveTab(')
source += method(compositor, '    private func isCurrentTabInAnyWindow(')
source += '\n}\n'
source += r'''
let browser = Browser(), compositor = Compositor()
compositor.browserManager = browser
let tab = Tab(), other = Tab(), splitTab = Tab()
for item in [tab, other, splitTab] { item._webView = View(); item.browserManager = browser }
let first = UUID(), second = UUID()
browser.windowRegistry!.allWindows = [Window(id: first, currentTabId: other.id), Window(id: second, currentTabId: tab.id)]
precondition(!compositor.canUnloadInactiveTab(tab), "The second window's current tab must survive")
browser.splitManager.states[first] = Split(isSplit: true, leftTabId: other.id, rightTabId: splitTab.id)
precondition(!compositor.canUnloadInactiveTab(splitTab), "The nonfocused split pane must survive")
browser.windowRegistry!.allWindows[0].currentTabId = tab.id
precondition(compositor.canUnloadInactiveTab(splitTab), "A split no longer displayed must not protect hidden tabs")
browser.windowRegistry!.allWindows.removeAll()
tab.isCurrentTab = true
precondition(!compositor.canUnloadInactiveTab(tab), "An empty registry must honor startup selection")
tab.isCurrentTab = false
precondition(compositor.canUnloadInactiveTab(tab))
for flag in [\Tab.hasPiPActive, \Tab.hasPlayingVideo, \Tab.hasPlayingAudio, \Tab.hasAudioContent, \Tab.isPinned, \Tab.isSpacePinned] {
    tab[keyPath: flag] = true
    precondition(!compositor.canUnloadInactiveTab(tab), "Media and pinned tabs must survive")
    tab[keyPath: flag] = false
}
let clone = View()
browser.webViewCoordinator!.views[tab.id] = [tab._webView!, clone]
clone.microphoneCaptureState = .active
precondition(!compositor.canUnloadInactiveTab(tab), "Capture in any clone must protect the tab")
clone.microphoneCaptureState = .none
tab._webView!.cameraCaptureState = .active
precondition(!compositor.canUnloadInactiveTab(tab))
tab._webView!.cameraCaptureState = .none
tab.refresh()
precondition(tab._webView!.reloadCount == 1 && clone.reloadCount == 1, "A pooled primary must reload exactly once")
browser.webViewCoordinator!.views[tab.id] = [clone]
tab.refresh()
precondition(tab._webView!.reloadCount == 2 && clone.reloadCount == 2, "An unpooled primary must still reload")
clone.backForwardList.currentItem = nil
tab.refresh()
precondition(clone.loadCount == 1 && clone.reloadCount == 2, "A view with no committed page must load the saved URL instead of reloading")
clone.backForwardList.currentItem = 1
tab.isPopupHost = true
tab.finishSetup()
precondition(tab.loadedURLs.isEmpty, "The initial popup must let WebKit drive navigation")
precondition(!tab.isPopupHost, "Successful setup must consume popup suppression")
tab.performComprehensiveWebViewCleanup()
tab._webView = View()
tab.finishSetup()
precondition(tab.loadedURLs == [tab.url], "Undoing popup close must load its saved URL")
tab.unloadWebView()
tab._webView = View()
tab.finishSetup()
precondition(tab.loadedURLs == [tab.url, tab.url], "Resuming an evicted popup must load its saved URL")
tab._existingWebView = tab._webView
tab.finishSetup()
precondition(tab.loadedURLs.count == 2, "An adopted Peek view must retain its existing navigation")
// The popup delegate can also adopt a WebView directly, bypassing setup.
tab.isPopupHost = true
tab.unloadWebView()
precondition(!tab.isPopupHost, "Popup suppression must end when the original view is discarded")
precondition(tab._webView == nil && tab._existingWebView == nil)
precondition(browser.webViewCoordinator!.getAllWebViews(for: tab.id).isEmpty)
precondition(!compositor.canUnloadInactiveTab(tab), "Already unloaded tabs should be skipped")
let shown = WindowState(); shown.currentTabId = tab.id
browser.windowRegistry!.windows[UUID()] = shown
tab.refresh()
precondition(tab.recreated == 1 && tab._webView != nil && shown.refreshes == 1, "Refreshing an unloaded tab must recreate it and redraw its window")
print("PASS: all-window/split visibility, media/capture/pin exemptions, empty registry, popup initial navigation/close undo/eviction, Peek adoption, reload deduplication, uncommitted and unloaded refresh")
'''
with tempfile.TemporaryDirectory(prefix='nook-tab-lifecycle-') as directory:
    swift = Path(directory) / 'main.swift'
    binary = Path(directory) / 'regression'
    swift.write_text(source)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
