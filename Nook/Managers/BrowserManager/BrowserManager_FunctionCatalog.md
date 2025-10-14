# BrowserManager Function Catalog

This catalog enumerates the current top-level methods declared on `BrowserManager` (line numbers refer to `Managers/BrowserManager/BrowserManager.swift`).

## Compositor & Window Lifecycle

- L74: `func isActive(_ windowState: BrowserWindowState) -> Bool {`
- L104: `func setCompositorContainerView(_ view: NSView?, for windowId: UUID) {`
- L108: `func compositorContainerView(for windowId: UUID) -> NSView? {`
- L112: `func removeCompositorContainerView(for windowId: UUID) {`
- L116: `func removeWebViewFromContainers(_ webView: WKWebView) {`
- L125: `func removeAllWebViews(for tab: Tab) {`
- L195: `func compositorContainers() -> [(UUID, NSView)] {`
- L1567: `func presentExternalURL(_ url: URL) {`
- L1574: `func registerWindowState(_ windowState: BrowserWindowState) {`
- L1612: `func unregisterWindowState(_ windowId: UUID) {`
- L1646: `private func cleanupWebViewsForWindow(_ windowId: UUID) {`
- L1671: `private func performFallbackWebViewCleanup(_ webView: WKWebView, tabId: UUID) {`
- L1705: `func cleanupAllWebViews() {`
- L1739: `func setActiveWindowState(_ windowState: BrowserWindowState) {`
- L1874: `func refreshCompositor(for windowState: BrowserWindowState) {`
- L1879: `func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {`
- L1884: `func getAllWebViews(for tabId: UUID) -> [WKWebView] {`
- L1889: `func createWebView(for tabId: UUID, in windowId: UUID) -> WKWebView {`
- L1980: `func syncTabAcrossWindows(_ tabId: UUID) {`
- L2010: `func navigateTabAcrossWindows(_ tabId: UUID, to url: URL) {`
- L2027: `func reloadTabAcrossWindows(_ tabId: UUID) {`
- L2054: `func setActiveSpace(_ space: Space, in windowState: BrowserWindowState) {`
- L2102: `func validateWindowStates() {`
- L2234: `func selectNextSpaceInActiveWindow() {`
- L2246: `func selectPreviousSpaceInActiveWindow() {`
- L2258: `func createNewWindow() {`
- L2280: `func closeActiveWindow() {`
- L2286: `func toggleFullScreenForActiveWindow() {`
- L2292: `func showDownloads() {`
- L2298: `func showHistory() {`
- L2325: `func expandAllFoldersInSidebar() {`

## Tab Operations & Navigation

- L133: `private func enforceExclusiveAudio(for tab: Tab, activeWindowId: UUID, desiredMuteState: Bool? = nil) {`
- L666: `func createNewTab() {`
- L671: `func createNewTab(in windowState: BrowserWindowState) {`
- L681: `func duplicateCurrentTab() {`
- L726: `func closeCurrentTab() {`
- L902: `@objc private func handleTabUnloadTimeoutChange(_ notification: Notification) {`
- L1118: `func currentTabForActiveWindow() -> Tab? {`
- L1127: `func refreshCurrentTabInActiveWindow() {`
- L1132: `func toggleMuteCurrentTabInActiveWindow() {`
- L1137: `func requestPiPForCurrentTabInActiveWindow() {`
- L1142: `func currentTabHasVideoContent() -> Bool {`
- L1147: `func currentTabHasPiPActive() -> Bool {`
- L1152: `func currentTabIsMuted() -> Bool {`
- L1157: `func currentTabHasAudioContent() -> Bool {`
- L1162: `func copyCurrentURL() {`
- L1765: `func currentTab(for windowState: BrowserWindowState) -> Tab? {`
- L1771: `func selectTab(_ tab: Tab) {`
- L1780: `func selectTab(_ tab: Tab, in windowState: BrowserWindowState) {`
- L1836: `func tabsForDisplay(in windowState: BrowserWindowState) -> [Tab] {`
- L1869: `func isCurrentTabFrozen(in windowState: BrowserWindowState) -> Bool {`
- L2041: `func setMuteState(_ muted: Bool, for tabId: UUID, originatingWindowId: UUID?) {`
- L2189: `func selectNextTabInActiveWindow() {`
- L2202: `func selectPreviousTabInActiveWindow() {`
- L2215: `func selectTabByIndexInActiveWindow(_ index: Int) {`
- L2225: `func selectLastTabInActiveWindow() {`
- L2305: `func showTabClosureToast(tabCount: Int) {`
- L2315: `func hideTabClosureToast() {`
- L2320: `func undoCloseTab() {`

## Sidebar & Layout

- L432: `func updateSidebarWidth(_ width: CGFloat) {`
- L442: `func updateSidebarWidth(_ width: CGFloat, for windowState: BrowserWindowState) {`
- L453: `func saveSidebarWidthToDefaults() {`
- L457: `func toggleSidebar() {`
- L476: `func toggleSidebar(for windowState: BrowserWindowState) {`
- L498: `func toggleAISidebar() {`
- L505: `func toggleAISidebar(for windowState: BrowserWindowState) {`
- L520: `func getSavedSidebarWidth(for windowState: BrowserWindowState? = nil) -> CGFloat {`
- L876: `private func loadSidebarSettings() {`
- L897: `private func saveSidebarSettings() {`

## Command Palette & Search

- L531: `private func showCommandPalette(in windowState: BrowserWindowState, prefill: String, navigateCurrentTab: Bool) {`
- L550: `func openCommandPalette() {`
- L563: `func openCommandPaletteWithCurrentURL() {`
- L572: `func closeCommandPalette(for windowState: BrowserWindowState? = nil) {`
- L601: `func toggleCommandPalette() {`
- L613: `private func showMiniCommandPalette(in windowState: BrowserWindowState, prefill: String) {`
- L631: `func hideMiniCommandPalette(for windowState: BrowserWindowState? = nil) {`
- L652: `func showFindBar() {`
- L660: `func updateFindManagerCurrentTab() {`
- L742: `func focusURLBar() {`

## Appearance & Theme

- L151: `private func updateGradient(for windowState: BrowserWindowState, to newGradient: SpaceGradient, animate: Bool) {`
- L174: `func refreshGradientsForSpace(_ space: Space, animate: Bool) {`
- L595: `func toggleTopBarAddressView() {`
- L783: `func showGradientEditor() {`

## Dialogs & Feedback

- L752: `func showQuitDialog() {`
- L768: `func showDialog<Content: View>(_ dialog: Content) {`
- L772: `func showDialog<Content: View>(@ViewBuilder builder: () -> Content) {`
- L855: `func closeDialog() {`
- L859: `private func quitApplication() {`
- L865: `func cleanupAllTabs() {`

## Privacy & Data Cleanup

- L914: `func clearCurrentPageCookies() {`
- L923: `func clearAllCookies() {`
- L929: `func clearExpiredCookies() {`
- L937: `func clearCurrentPageCache() {`
- L947: `func hardReloadCurrentPage() {`
- L963: `func clearStaleCache() {`
- L969: `func clearDiskCache() {`
- L975: `func clearMemoryCache() {`
- L981: `func clearAllCache() {`
- L989: `func clearThirdPartyCookies() {`
- L995: `func clearHighRiskCookies() {`
- L1001: `func performPrivacyCleanup() {`
- L1009: `func clearCurrentProfileCookies() {`
- L1015: `func clearCurrentProfileCache() {`
- L1021: `func clearAllProfilesCookies() {`
- L1033: `func performPrivacyCleanupAllProfiles() {`
- L1049: `func migrateUnassignedDataToDefaultProfile() {`
- L1054: `func assignDefaultProfileToExistingData(_ profileId: UUID) {`
- L1071: `func clearPersonalDataCache() {`
- L1077: `func clearFaviconCache() {`

## OAuth & Assist

- L304: `func maybeShowOAuthAssist(for url: URL, in tab: Tab) {`
- L326: `func hideOAuthAssist() { oauthAssist = nil }`
- L328: `func oauthAssistAllowForThisTab(duration: TimeInterval = 15 * 60) {`
- L335: `func oauthAssistAlwaysAllowDomain() {`
- L341: `private func isLikelyOAuthURL(_ url: URL) -> Bool {`

## Profiles & Migration

- L180: `private func adoptProfileIfNeeded(for windowState: BrowserWindowState, context: ProfileSwitchContext) {`
- L376: `func switchToProfile(_ profile: Profile, context: ProfileSwitchContext = .userInitiated, in windowState: BrowserWindowState? = nil) async {`
- L1244: `func showProfileSwitchToast(from: Profile?, to: Profile, in windowState: BrowserWindowState?) {`
- L1257: `func hideProfileSwitchToast(for windowState: BrowserWindowState? = nil) {`
- L1262: `private func hideProfileSwitchToast(forWindowId windowId: UUID) {`
- L1290: `func detectLegacySharedData() async -> LegacyDataSummary {`
- L1333: `func migrateCookiesToCurrentProfile() async throws {`
- L1362: `func migrateCacheToCurrentProfile() async throws {`
- L1375: `func clearSharedDataAfterMigration() async {`
- L1396: `func createFreshProfileStores() async {`
- L1408: `func startMigrationToCurrentProfile() {`
- L1452: `private func resetMigrationState() {`
- L1458: `func validateProfileIntegrity() {`
- L1468: `func recoverFromProfileError(_ error: Error, profile: Profile?) {`
- L1498: `func deleteProfile(_ profile: Profile) {`

## Extensions

- L1083: `func showExtensionInstallDialog() {`
- L1097: `func enableExtension(_ extensionId: String) {`
- L1103: `func disableExtension(_ extensionId: String) {`
- L1109: `func uninstallExtension(_ extensionId: String) {`

## Dev Tools

- L1189: `func openWebInspector() {`
- L1218: `private func presentInspectorContextMenu(for webView: WKWebView) {`
- L2393: `func setAsDefaultBrowser() {`

## Imports

- L2163: `func importArcData() {`

## Update Handling

- L2358: `func handleUpdaterFoundValidUpdate(_ item: SUAppcastItem) {`
- L2365: `func handleUpdaterFinishedDownloading(_ item: SUAppcastItem) {`
- L2374: `func handleUpdaterDidNotFindUpdate() {`
- L2378: `func handleUpdaterAbortedUpdate() {`
- L2382: `func handleUpdaterWillInstallOnQuit(_ item: SUAppcastItem) {`
- L2386: `func installPendingUpdateIfAvailable() {`
