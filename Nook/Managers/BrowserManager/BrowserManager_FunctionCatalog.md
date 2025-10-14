# BrowserManager Function Catalog

This catalog enumerates the current top-level methods declared on `BrowserManager` (line numbers refer to `Managers/BrowserManager/BrowserManager.swift`).

## Compositor & Window Lifecycle

- L1729: `func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {`
- L1469: `func unregisterWindowState(_ windowId: UUID) {`
- L119: `func removeAllWebViews(for tab: Tab) {`
- L106: `func removeCompositorContainerView(for windowId: UUID) {`
- L1877: `func reloadTabAcrossWindows(_ tabId: UUID) {`
- L1431: `func registerWindowState(_ windowState: BrowserWindowState) {`
- L68: `func isActive(_ windowState: BrowserWindowState) -> Bool {`
- L2130: `func closeActiveWindow() {`
- L1593: `func setActiveWindowState(_ windowState: BrowserWindowState) {`
- L2136: `func toggleFullScreenForActiveWindow() {`
- L1500: `private func cleanupWebViewsForWindow(_ windowId: UUID) {`
- L98: `func setCompositorContainerView(_ view: NSView?, for windowId: UUID) {`
- L2173: `func expandAllFoldersInSidebar() {`
- L110: `func removeWebViewFromContainers(_ webView: WKWebView) {`
- L1559: `func cleanupAllWebViews() {`
- L1830: `func syncTabAcrossWindows(_ tabId: UUID) {`
- L2084: `func selectNextSpaceInActiveWindow() {`
- L2108: `func createNewWindow() {`
- L1734: `func getAllWebViews(for tabId: UUID) -> [WKWebView] {`
- L2142: `func showDownloads() {`
- L2147: `func showHistory() {`
- L189: `func compositorContainers() -> [(UUID, NSView)] {`
- L1860: `func navigateTabAcrossWindows(_ tabId: UUID, to url: URL) {`
- L2096: `func selectPreviousSpaceInActiveWindow() {`
- L1525: `private func performFallbackWebViewCleanup(_ webView: WKWebView, tabId: UUID) {`
- L1952: `func validateWindowStates() {`
- L102: `func compositorContainerView(for windowId: UUID) -> NSView? {`
- L1724: `func refreshCompositor(for windowState: BrowserWindowState) {`
- L1739: `func createWebView(for tabId: UUID, in windowId: UUID) -> WKWebView {`
- L1904: `func setActiveSpace(_ space: Space, in windowState: BrowserWindowState) {`
- L1424: `func presentExternalURL(_ url: URL) {`

## Tab Operations & Navigation

- L127: `private func enforceExclusiveAudio(for tab: Tab, activeWindowId: UUID, desiredMuteState: Bool? = nil) {`
- L984: `func refreshCurrentTabInActiveWindow() {`
- L1630: `func selectTab(_ tab: Tab, in windowState: BrowserWindowState) {`
- L1615: `func currentTab(for windowState: BrowserWindowState) -> Tab? {`
- L2075: `func selectLastTabInActiveWindow() {`
- L1009: `func currentTabIsMuted() -> Bool {`
- L2163: `func hideTabClosureToast() {`
- L1686: `func tabsForDisplay(in windowState: BrowserWindowState) -> [Tab] {`
- L546: `func duplicateCurrentTab() {`
- L2153: `func showTabClosureToast(tabCount: Int) {`
- L975: `func currentTabForActiveWindow() -> Tab? {`
- L989: `func toggleMuteCurrentTabInActiveWindow() {`
- L994: `func requestPiPForCurrentTabInActiveWindow() {`
- L591: `func closeCurrentTab() {`
- L2039: `func selectNextTabInActiveWindow() {`
- L1019: `func copyCurrentURL() {`
- L1014: `func currentTabHasAudioContent() -> Bool {`
- L999: `func currentTabHasVideoContent() -> Bool {`
- L536: `func createNewTab(in windowState: BrowserWindowState) {`
- L1719: `func isCurrentTabFrozen(in windowState: BrowserWindowState) -> Bool {`
- L2052: `func selectPreviousTabInActiveWindow() {`
- L2065: `func selectTabByIndexInActiveWindow(_ index: Int) {`
- L759: `@objc private func handleTabUnloadTimeoutChange(_ notification: Notification) {`
- L1004: `func currentTabHasPiPActive() -> Bool {`
- L2168: `func undoCloseTab() {`
- L1891: `func setMuteState(_ muted: Bool, for tabId: UUID, originatingWindowId: UUID?) {`

## Sidebar & Layout

- L733: `private func loadSidebarSettings() {`
- L447: `func saveSidebarWidthToDefaults() {`
- L754: `private func saveSidebarSettings() {`
- L499: `func toggleAISidebar(for windowState: BrowserWindowState) {`
- L436: `func updateSidebarWidth(_ width: CGFloat, for windowState: BrowserWindowState) {`
- L470: `func toggleSidebar(for windowState: BrowserWindowState) {`
- L514: `func getSavedSidebarWidth(for windowState: BrowserWindowState? = nil) -> CGFloat {`

## Appearance & Theme

- L640: `func showGradientEditor() {`
- L524: `func toggleTopBarAddressView() {`
- L145: `private func updateGradient(for windowState: BrowserWindowState, to newGradient: SpaceGradient, animate: Bool) {`
- L168: `func refreshGradientsForSpace(_ space: Space, animate: Bool) {`

## Dialogs & Feedback

- L712: `func closeDialog() {`
- L716: `private func quitApplication() {`
- L722: `func cleanupAllTabs() {`
- L629: `func showDialog<Content: View>(@ViewBuilder builder: () -> Content) {`
- L609: `func showQuitDialog() {`

## Privacy & Data Cleanup

- L826: `func clearDiskCache() {`
- L804: `func hardReloadCurrentPage() {`
- L780: `func clearAllCookies() {`
- L820: `func clearStaleCache() {`
- L846: `func clearThirdPartyCookies() {`
- L878: `func clearAllProfilesCookies() {`
- L771: `func clearCurrentPageCookies() {`
- L794: `func clearCurrentPageCache() {`
- L832: `func clearMemoryCache() {`
- L911: `func assignDefaultProfileToExistingData(_ profileId: UUID) {`
- L928: `func clearPersonalDataCache() {`
- L890: `func performPrivacyCleanupAllProfiles() {`
- L838: `func clearAllCache() {`
- L858: `func performPrivacyCleanup() {`
- L906: `func migrateUnassignedDataToDefaultProfile() {`
- L934: `func clearFaviconCache() {`
- L866: `func clearCurrentProfileCookies() {`
- L786: `func clearExpiredCookies() {`
- L852: `func clearHighRiskCookies() {`
- L872: `func clearCurrentProfileCache() {`

## OAuth & Assist

- L322: `func oauthAssistAllowForThisTab(duration: TimeInterval = 15 * 60) {`
- L320: `func hideOAuthAssist() { oauthAssist = nil }`
- L329: `func oauthAssistAlwaysAllowDomain() {`
- L298: `func maybeShowOAuthAssist(for url: URL, in tab: Tab) {`
- L335: `private func isLikelyOAuthURL(_ url: URL) -> Bool {`

## Profiles & Migration

- L1101: `func showProfileSwitchToast(from: Profile?, to: Profile, in windowState: BrowserWindowState?) {`
- L1147: `func detectLegacySharedData() async -> LegacyDataSummary {`
- L1190: `func migrateCookiesToCurrentProfile() async throws {`
- L1119: `private func hideProfileSwitchToast(forWindowId windowId: UUID) {`
- L1325: `func recoverFromProfileError(_ error: Error, profile: Profile?) {`
- L174: `private func adoptProfileIfNeeded(for windowState: BrowserWindowState, context: ProfileSwitchContext) {`
- L1265: `func startMigrationToCurrentProfile() {`
- L1355: `func deleteProfile(_ profile: Profile) {`
- L1219: `func migrateCacheToCurrentProfile() async throws {`
- L1309: `private func resetMigrationState() {`
- L370: `func switchToProfile(_ profile: Profile, context: ProfileSwitchContext = .userInitiated, in windowState: BrowserWindowState? = nil) async {`
- L1232: `func clearSharedDataAfterMigration() async {`
- L1253: `func createFreshProfileStores() async {`
- L1315: `func validateProfileIntegrity() {`

## Extensions

- L954: `func enableExtension(_ extensionId: String) {`
- L940: `func showExtensionInstallDialog() {`
- L960: `func disableExtension(_ extensionId: String) {`
- L966: `func uninstallExtension(_ extensionId: String) {`

## Dev Tools

- L2241: `func setAsDefaultBrowser() {`
- L1075: `private func presentInspectorContextMenu(for webView: WKWebView) {`
- L1046: `func openWebInspector() {`

## Imports

- L2013: `func importArcData() {`

## Update Handling

- L2226: `func handleUpdaterAbortedUpdate() {`
- L2206: `func handleUpdaterFoundValidUpdate(_ item: SUAppcastItem) {`
- L2234: `func installPendingUpdateIfAvailable() {`
- L2230: `func handleUpdaterWillInstallOnQuit(_ item: SUAppcastItem) {`
- L2213: `func handleUpdaterFinishedDownloading(_ item: SUAppcastItem) {`
- L2222: `func handleUpdaterDidNotFindUpdate() {`
