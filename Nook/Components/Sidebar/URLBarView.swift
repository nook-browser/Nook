// Licensed under GPL-3.0. See LICENSE.
//
//  URLBarView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import AppKit
import NookDesign
import NookWeb
import NookUI
import NookSettings

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject private var hoverManager: HoverSidebarManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering: Bool = false
    @State private var showCheckmark: Bool = false
    @State private var isEditing = false
    @State private var addressText = ""
    @State private var selectedSuggestion: SearchManager.SearchSuggestion?
    @State private var prefilledAddress = ""
    @State private var searchManager = SearchManager()
    @FocusState private var addressFocused: Bool
    var isSidebarHovered: Bool
    var splitItemID: UUID? = nil

    var body: some View {
        addressPresentation
        .onChange(of: addressText) { _, value in
            guard isEditing else { return }
            selectedSuggestion = nil
            guard value != prefilledAddress else {
                searchManager.clearSuggestions()
                return
            }
            searchManager.searchSuggestions(for: value, includeWebSuggestions: !isLikelyURL(value))
        }
        .onChange(of: searchManager.suggestions) { _, _ in
            if let selectedSuggestion, !inlineSuggestions.contains(selectedSuggestion) {
                self.selectedSuggestion = nil
            }
        }
        .onChange(of: addressFocused) { _, focused in
            if splitItemID == nil, !focused {
                // Let a suggestion button's click finish before removing its overlay.
                DispatchQueue.main.async {
                    if !addressFocused { cancelEditing() }
                }
            }
        }
        .onChange(of: windowState.selectedItemID) { _, _ in cancelEditing() }
        .onChange(of: windowState.split) { _, split in
            if let splitItemID, split?.leftItemID != splitItemID && split?.rightItemID != splitItemID {
                cancelEditing()
            }
        }
        .onChange(of: windowState.spaceID) { _, _ in cancelEditing() }
        .onChange(of: windowState.commandPalette?.isVisible) { _, visible in
            if visible == true { cancelEditing() }
        }
        .onDisappear { cancelEditing() }
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
                isHovering = hovering
            }
        }
        
    }
    
    @ViewBuilder
    private var addressPresentation: some View {
        let session = splitItemID == nil
            ? browserManager.tabs.selectedSession(in: windowState)
            : splitItemID.flatMap { browserManager.tabs.session(for: $0) }
        collapsedAddress(session: session)
        .frame(maxWidth: .infinity, minHeight: controlHeight, maxHeight: controlHeight)
        .overlay(alignment: .bottom) {
            if splitItemID == nil { PageLoadingProgressBar(session: session) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(splitItemID == nil ? (isHovering ? 0.10 : 0.15) : 0)
                      : Color.black.opacity(splitItemID == nil ? 0.08 : 0))
        }
        // Report the frame in the window space so we can overlay the mini palette above all content
        .background {
            if splitItemID == nil {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: URLBarFramePreferenceKey.self,
                        value: proxy.frame(in: .named("WindowSpace"))
                    )
                }
            }
        }
        .overlay(alignment: nookSettings.sidebarPosition == .right ? .topTrailing : .topLeading) {
            if isEditing, splitItemID == nil {
                expandedAddressPanel
                    .frame(width: expandedPanelWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(AddressOutsideClickRegion(onOutsideClick: cancelEditing))
            }
        }
        .background {
            if isEditing, splitItemID != nil {
                AddressAnchoredPanel(width: expandedPanelWidth) {
                    expandedAddressPanel
                        .frame(width: expandedPanelWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.colorScheme, colorScheme)
                        .background(AddressOutsideClickRegion(onOutsideClick: cancelEditing))
                }
            }
        }
        .zIndex(isEditing ? 100 : 0)
    }

    @ViewBuilder
    private func collapsedAddress(session: PageSession?) -> some View {
        ZStack {
            if let splitItemID, let item = browserManager.tabs.item(splitItemID) {
                HStack(spacing: NookDesign.Spacing.sm) {
                    ItemFavicon(item: item, session: session)
                        .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
                    Text(browserManager.tabs.title(for: item))
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, NookDesign.Spacing.rowPadding)
                .frame(height: NookDesign.Size.navRow)
                .contentShape(Rectangle())
                .pointerStyle(.horizontalText)
                .onTapGesture {
                    guard !isEditing else { return }
                    beginEditing(session?.url.absoluteString ?? item.url?.absoluteString ?? "")
                }
                .modifier(AddressActivationAccessibility(enabled: !isEditing) {
                    beginEditing(session?.url.absoluteString ?? item.url?.absoluteString ?? "")
                })
                .help("Search or Enter URL...")
                .nookFloatingSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
            } else {
                sidebarAddress(session: session)
            }
        }
    }

    private func sidebarAddress(session: PageSession?) -> some View {
        HStack(spacing: NookDesign.Spacing.sm) {
                // The address edits in place; the global command palette remains separate.
                Group {
                    if session != nil {
                        HStack(spacing: NookDesign.Spacing.xs) {
                            // HTTPS is the norm, so only a page that is not gets a mark.
                            if isInsecure(for: session) {
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            // Two texts so a narrow sidebar cuts the path first and then the
                            // host's head: `accounts.google.com.x.evil.tld` must keep `evil.tld`.
                            HStack(spacing: 0) {
                                Text(displayHost(for: session)).foregroundStyle(.primary)
                                    .truncationMode(.head)
                                    .layoutPriority(1)
                                Text(displayPath(for: session)).foregroundStyle(.tertiary)
                                    .truncationMode(.tail)
                            }
                            .font(.system(size: 14, weight: .regular))
                            .lineLimit(1)
                            if let errors = devErrorCount(for: session) {
                                Button {
                                    browserManager.toggleDevPanel(.console)
                                } label: {
                                    Text("\(errors)")
                                        .font(NookDesign.Font.micro.monospacedDigit())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, NookDesign.Spacing.xs)
                                        .background(Capsule().fill(.red))
                                }
                                .buttonStyle(.plain)
                                .help("Console")
                            }
                        }
                    } else {
                        HStack(spacing: NookDesign.Spacing.xs) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                                .foregroundStyle(textColor)
                            Text("Search or Enter URL...")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(textColor)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .pointerStyle(.horizontalText)
                .onTapGesture {
                    guard !isEditing else { return }
                    beginEditing(session?.url.absoluteString ?? "")
                }
                .modifier(AddressActivationAccessibility(enabled: !isEditing) {
                    beginEditing(session?.url.absoluteString ?? "")
                })

                // Copy link button (show on hover when tab is selected)
                if !isEditing, isHovering, let session {
                    Button("Copy Link", systemImage: showCheckmark ? "checkmark" : "link") {
                        copyURLToClipboard(session.url.absoluteString)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.iconButton, radius: NookDesign.Radius.sm))
                    .foregroundStyle(Color.primary)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .contentTransition(.symbolEffect(.replace))
                }

                // Pinned extension buttons + library button
                if !isEditing, let extensionManager = browserManager.extensionManager {
                    let pinnedIDs = browserManager.nookSettings?.pinnedExtensionIDs ?? []
                    let pinnedExtensions = extensionManager.installedExtensions.filter { pinnedIDs.contains($0.id) }

                    if !pinnedExtensions.isEmpty {
                        ExtensionActionView(extensions: pinnedExtensions)
                            .environmentObject(browserManager)
                    }

                    ExtensionLibraryButton()
                        .environmentObject(browserManager)
                        .onAppear {
                            let installedIDs = extensionManager.installedExtensions
                                .filter { $0.isEnabled }
                                .map { $0.id }
                            browserManager.nookSettings?.migrateExtensionPinStateIfNeeded(installedExtensionIDs: installedIDs)
                        }
                }
            }
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
    }

    private var controlHeight: CGFloat {
        splitItemID == nil ? NookDesign.Size.chromeControl : NookDesign.Size.navRow
    }

    private var isComposingAddress: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }

    private var inlineSuggestions: [SearchManager.SearchSuggestion] {
        let typed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty || addressText == prefilledAddress { return initialLocalSuggestions }
        let primary = SearchManager.SearchSuggestion(text: typed, type: isLikelyURL(typed) ? .url : .search)
        let found = searchManager.suggestions.filter {
            $0.text.caseInsensitiveCompare(typed) != .orderedSame
        }
        return [primary] + found.prefix(5)
    }

    private var selectedSuggestionIndex: Int {
        guard let selectedSuggestion else { return showsInitialSuggestions ? -1 : 0 }
        return inlineSuggestions.firstIndex(of: selectedSuggestion) ?? (showsInitialSuggestions ? -1 : 0)
    }

    private func moveSuggestionSelection(by direction: Int) {
        let suggestions = inlineSuggestions
        guard !suggestions.isEmpty else { return }
        let index = min(suggestions.count - 1, max(showsInitialSuggestions ? -1 : 0, selectedSuggestionIndex + direction))
        selectedSuggestion = index < 0 || (!showsInitialSuggestions && index == 0) ? nil : suggestions[index]
    }

    @ViewBuilder
    private var inlineAddressField: some View {
        if splitItemID != nil {
            SplitAddressSearchField(text: $addressText,
                                    onSubmit: { submitAddress() },
                                    onCancel: cancelEditing,
                                    onMove: moveSuggestionSelection,
                                    onEndEditing: cancelEditing)
                .frame(height: 22)
        } else {
            TextField("Search or Enter URL...", text: $addressText)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular))
                .focused($addressFocused)
                .onSubmit { submitAddress() }
                .onExitCommand { cancelEditing() }
                .onKeyPress(.downArrow) {
                    guard !isComposingAddress else { return .ignored }
                    moveSuggestionSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !isComposingAddress else { return .ignored }
                    moveSuggestionSelection(by: -1)
                    return .handled
                }
                .onAppear {
                    addressFocused = true
                    DispatchQueue.main.async {
                        guard isEditing, addressFocused,
                              let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                        editor.selectAll(nil)
                    }
                }
        }
    }

    private var showsInitialSuggestions: Bool {
        addressText == prefilledAddress || addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Local open pages make useful initial rows without disclosing the current URL to a
    /// suggestion provider. The currently displayed page is excluded instead of repeated.
    private var initialLocalSuggestions: [SearchManager.SearchSuggestion] {
        guard let spaceID = windowState.spaceID else { return [] }
        return browserManager.tabs.items(inSpace: spaceID)
            .filter { !$0.isFolder && $0.id != (splitItemID ?? windowState.selectedItemID) }
            .prefix(6).compactMap { item in
                let session = browserManager.tabs.session(for: item.id)
                guard let url = session?.url ?? item.url, url.absoluteString != prefilledAddress else { return nil }
                let title = item.customTitle ?? session?.title ?? item.displayTitle
                let favicon = session?.favicon ?? url.host.flatMap { FaviconCache.shared.swiftUIImage(for: $0) } ?? Image(systemName: "globe")
                let match = SearchManager.TabMatch(itemID: item.id, title: title, url: url, favicon: favicon)
                return SearchManager.SearchSuggestion(text: title, type: .tab(match))
            }
    }

    private var expandedPanelWidth: CGFloat {
        min(440, max(240, (NSApp.keyWindow?.contentView?.bounds.width ?? 480) - 32))
    }

    private var expandedAddressPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                inlineAddressField
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            if !inlineSuggestions.isEmpty {
                Divider().padding(.horizontal, 10)
                inlineSuggestionList
            }
        }
        .background(colorScheme == .dark ? Color(white: 24.0 / 255.0) : .white,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .strokeBorder(colorScheme == .dark ? Color(white: 75.0 / 255.0) : Color.black.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.23), radius: 24, y: 10)
    }

    private var inlineSuggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(inlineSuggestions.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    submitAddress(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        AddressSuggestionFavicon(suggestion: suggestion)
                            .frame(width: 20, height: 20)
                        HStack(spacing: 6) {
                            Text(suggestionTitle(suggestion))
                                .font(.system(size: 14, weight: .regular))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            if let host = suggestionURL(suggestion)?.host {
                                Text("— " + host)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 45, maxHeight: 45, alignment: .leading)
                    .background(index == selectedSuggestionIndex ? NookDesign.Surface.fillPressed : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(6)
    }

    private func suggestionURL(_ suggestion: SearchManager.SearchSuggestion) -> URL? {
        switch suggestion.type {
        case .history(let entry): return entry.url
        case .tab(let match): return match.url
        case .url: return URL(string: normalizeURL(suggestion.text, queryTemplate: SearchProvider.google.queryTemplate))
        case .search: return nil
        }
    }

    private func suggestionIcon(_ suggestion: SearchManager.SearchSuggestion) -> String {
        switch suggestion.type {
        case .history: return "clock"
        case .search: return "magnifyingglass"
        case .url, .tab: return "globe"
        }
    }

    private func suggestionTitle(_ suggestion: SearchManager.SearchSuggestion) -> String {
        if case .history(let entry) = suggestion.type { return entry.displayTitle }
        if case .tab(let match) = suggestion.type { return match.title }
        return suggestion.text
    }

    private func beginEditing(_ address: String) {
        searchManager.setTabs(browserManager.tabs, window: windowState)
        searchManager.setHistoryManager(browserManager.historyManager)
        prefilledAddress = address
        addressText = address
        selectedSuggestion = nil
        searchManager.clearSuggestions()
        isEditing = true
        windowState.isAddressEditing = true
        windowState.isSidebarResizeHovered = false
        hoverManager.setAddressEditing(true, in: windowState.id)
    }

    private func cancelEditing() {
        guard isEditing else { return }
        windowState.isAddressEditing = false
        hoverManager.setAddressEditing(false, in: windowState.id)
        isEditing = false
        addressFocused = false
        searchManager.clearSuggestions()
    }

    private func submitAddress(_ chosen: SearchManager.SearchSuggestion? = nil) {
        guard !isComposingAddress else { return }
        let suggestions = inlineSuggestions
        let selected = selectedSuggestion.flatMap { selection in suggestions.first { $0 == selection } }
        let typed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = typed.isEmpty ? nil : SearchManager.SearchSuggestion(text: typed, type: isLikelyURL(typed) ? .url : .search)
        guard let suggestion = chosen ?? selected ?? fallback else { return }
        if splitItemID == nil, case .tab(let match) = suggestion.type {
            guard browserManager.tabs.item(match.itemID) != nil else { return }
            cancelEditing()
            browserManager.tabs.select(match.itemID, in: windowState)
            return
        }
        let url: URL?
        switch suggestion.type {
        case .history(let entry): url = entry.url
        case .tab(let match): url = match.url
        case .url, .search:
            let template = browserManager.nookSettings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
            url = URL(string: normalizeURL(suggestion.text, queryTemplate: template))
        }
        guard let url else { return }
        cancelEditing()
        if let splitItemID {
            guard let split = windowState.split,
                  split.leftItemID == splitItemID || split.rightItemID == splitItemID,
                  !browserManager.tabs.isPageShownElsewhere(splitItemID, from: windowState),
                  let session = browserManager.tabs.ensureSession(for: splitItemID) else { return }
            session.load(url)
            browserManager.tabs.select(splitItemID, in: windowState)
            return
        }
        // Never navigate a live page owned by another window.
        let canReplace = browserManager.tabs.controllableSession(in: windowState) != nil
        browserManager.tabs.open(url: url, in: windowState,
                                 placement: canReplace ? .replaceCurrent : .newTab)
    }

    private var textColor: Color {
        .secondary
    }
    
    private func displayURL(for session: PageSession?) -> String {
        guard let session else { return "" }
        return formatURL(session.url)
    }

    private func isInsecure(for session: PageSession?) -> Bool { session?.url.scheme == "http" }
    /// The host, carrying the port when the URL names a non-default one. A development
    /// server at `localhost:3000` is a different origin from one at `localhost:8080`, so
    /// dropping the port left the bar showing the wrong thing. `URL.port` reports a port
    /// that was written out even when it is the scheme's default, so `https://x.com:443`
    /// still reads as `x.com`.
    private func displayHost(for session: PageSession?) -> String {
        guard let url = session?.url, let host = url.host else { return displayURL(for: session) }
        let defaultPort = url.scheme == "https" ? 443 : (url.scheme == "http" ? 80 : nil)
        guard let port = url.port, port != defaultPort else { return host }
        return "\(host):\(port)"
    }
    private func displayPath(for session: PageSession?) -> String {
        guard let url = session?.url, url.host != nil else { return "" }
        let path = url.path
        // A developer's own server shows its query too: it is usually what is being tested.
        if isDevPage(session), let query = url.query { return path + "?" + query }
        return path == "/" ? "" : path
    }

    private func isDevPage(_ session: PageSession?) -> Bool {
        guard let session, browserManager.nookSettings?.developerModeEnabled == true else { return false }
        return DevHosts.isDevHost(session.url)
    }

    /// Errors since load on a developer's own server, for the badge; nil hides it.
    private func devErrorCount(for session: PageSession?) -> Int? {
        guard isDevPage(session), let count = session?.devCapture?.errorCount, count > 0 else { return nil }
        return count
    }


        private func formatURL(_ url: URL) -> String {
            guard let host = url.host else {
                return url.absoluteString
            }
            
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            
            return cleanHost
        }
    
    private func copyURLToClipboard(_ urlString: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        
        // Show checkmark icon briefly
        withAnimation(NookDesign.Motion.standard) {
            showCheckmark = true
        }
        
        // Show toast notification
        windowState.isShowingCopyURLToast = true
        
        // Reset checkmark after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(NookDesign.Motion.standard) {
                showCheckmark = false
            }
        }
        
        // Hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            windowState.isShowingCopyURLToast = false
        }
    }
}

/// Expose the collapsed address as an actionable element without combining or overriding
/// the native text field's accessibility tree while editing.
private struct AddressActivationAccessibility: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
        } else {
            content
        }
    }
}

private struct AddressSuggestionFavicon: View {
    let suggestion: SearchManager.SearchSuggestion
    @State private var cached: NSImage?

    private var url: URL? {
        switch suggestion.type {
        case .history(let entry): return entry.url
        case .tab(let match): return match.url
        case .url: return URL(string: normalizeURL(suggestion.text, queryTemplate: SearchProvider.google.queryTemplate))
        case .search: return nil
        }
    }

    var body: some View {
        Group {
            if case .tab(let match) = suggestion.type {
                match.favicon.resizable().scaledToFit()
            } else if let cached {
                Image(nsImage: cached).resizable().scaledToFit()
            } else {
                Image(systemName: url == nil ? "magnifyingglass" : "globe")
                    .font(.system(size: 16)).foregroundStyle(.secondary)
            }
        }
        .task(id: url?.host) {
            cached = nil
            if let host = url?.host { cached = await FaviconCache.shared.cachedImage(for: host) }
        }
    }
}

/// A scoped local monitor dismisses the overlay without swallowing the outside click.
/// Its view covers the panel, so field and suggestion clicks stay inside.
private struct AddressOutsideClickRegion: NSViewRepresentable {
    let onOutsideClick: () -> Void

    final class Region: NSView {
        var onOutsideClick: (() -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let window = self.window else { return event }
                if event.window !== window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.onOutsideClick?()
                }
                return event
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
    func makeNSView(context: Context) -> Region {
        let view = Region()
        view.onOutsideClick = onOutsideClick
        return view
    }
    func updateNSView(_ nsView: Region, context: Context) { nsView.onOutsideClick = onOutsideClick }
    static func dismantleNSView(_ nsView: Region, coordinator: ()) { nsView.stop() }
}

/// Mount above the web content in the same window: a pane's hosting view and mask would
/// otherwise clip the expanded editor. Its top edge stays aligned with the title.
private struct AddressAnchoredPanel<Content: View>: NSViewRepresentable {
    let width: CGFloat
    @ViewBuilder let content: () -> Content

    final class Anchor: NSView {
        var panelContent: Content?
        var panelWidth: CGFloat = 440
        private var hostingView: NSHostingView<Content>?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { removePanel() }
            else { updatePanel() }
        }

        override func layout() {
            super.layout()
            updatePanel()
        }

        func updatePanel() {
            guard let root = window?.contentView, let panelContent else { return }
            let host: NSHostingView<Content>
            if let hostingView {
                host = hostingView
            } else {
                host = NSHostingView(rootView: panelContent)
                host.safeAreaRegions = []
                hostingView = host
                root.addSubview(host, positioned: .above, relativeTo: nil)
            }
            let anchorRect = root.convert(bounds, from: self)
            let height = host.fittingSize.height
            let x = min(max(root.bounds.minX + 8, anchorRect.minX),
                        max(root.bounds.minX + 8, root.bounds.maxX - panelWidth - 8))
            let y = root.isFlipped ? anchorRect.minY : anchorRect.maxY - height
            host.frame = NSRect(x: x, y: y, width: panelWidth, height: height)
        }

        func setContent(_ content: Content) {
            panelContent = content
            hostingView?.rootView = content
            updatePanel()
        }

        func removePanel() {
            hostingView?.removeFromSuperview()
            hostingView = nil
        }
    }

    func makeNSView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.panelWidth = width
        anchor.panelContent = content()
        return anchor
    }

    func updateNSView(_ nsView: Anchor, context: Context) {
        nsView.panelWidth = width
        nsView.setContent(content())
    }

    static func dismantleNSView(_ nsView: Anchor, coordinator: ()) {
        nsView.removePanel()
    }
}

/// The expanded split editor lives in a separate hosting view, so give its native
/// field focus after attachment rather than sharing FocusState across hosting roots.
private struct SplitAddressSearchField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onMove: (Int) -> Void
    let onEndEditing: () -> Void

    final class Field: NSTextField {
        private var didRequestFocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !didRequestFocus else { return }
            didRequestFocus = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                if window.makeFirstResponder(self) {
                    self.currentEditor()?.selectAll(nil)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SplitAddressSearchField
        init(_ parent: SplitAddressSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in self?.parent.onEndEditing() }
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            default: return false
            }
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.placeholderString = "Search or Enter URL..."
        field.font = .systemFont(ofSize: 14)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.stringValue = text
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search or Enter URL...")
        return field
    }

    func updateNSView(_ nsView: Field, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text { nsView.stringValue = text }
    }
}
