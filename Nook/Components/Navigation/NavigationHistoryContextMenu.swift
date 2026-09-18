// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  NavigationHistoryContextMenu.swift
//  Nook
//
//  Created by Jonathan Caudill on 01/10/2025.
//

import SwiftUI
import WebKit
import NookDesign
import NookWeb

struct NavigationHistoryContextMenu: View {
    let historyType: HistoryType
    let windowState: BrowserWindowState
    @EnvironmentObject var browserManager: BrowserManager
    @State private var historyItems: [NavigationHistoryContextMenuItem] = []
    @State private var refreshID = UUID()

    enum HistoryType {
        case back
        case forward
    }

    var body: some View {
        Group {
            if !historyItems.isEmpty {
                ForEach(Array(historyItems.enumerated()), id: \.element.id) { index, item in
                    Button(action: {
                        navigateToHistoryItem(item)
                    }) {
                        HStack(spacing: 8) {
                            // Directional icon
                            Image(systemName: historyType == .back ? "arrow.backward" : "arrow.forward")
                                .font(NookDesign.Font.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 12)

                            // Title and URL
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(NookDesign.Font.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                if let url = item.url {
                                    Text(urlDisplayString(url))
                                        .font(NookDesign.Font.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            } else {
                Button(action: {}) {
                    Text("No \(historyType == .back ? "back" : "forward") history")
                        .foregroundColor(.secondary)
                }
                .disabled(true)
            }
        }
        .id(refreshID) // Force view refresh
        .onAppear {
            loadHistoryItems()
        }
        .onChange(of: windowState.selectedItemID) { _, _ in
            refreshHistory()
        }
    }

    private func loadHistoryItems() {
        historyItems = loadHistoryItemsFresh()
    }

    private func loadHistoryItemsFresh() -> [NavigationHistoryContextMenuItem] {
        guard let tab = browserManager.tabs.controllableSession(in: windowState),
              // Use assignedWebView as fallback to avoid triggering lazy initialization
              let webView = browserManager.webViewCoordinator?.getWebView(for: tab.itemID, in: windowState.id) ?? tab.assignedWebView else {
            return []
        }

        let backForwardList = webView.backForwardList
        var items: [NavigationHistoryContextMenuItem] = []

        if historyType == .back {
            // Get back history (most recent first, get ALL available entries)
            let backList = backForwardList.backList
            for item in backList.reversed() {
                items.append(NavigationHistoryContextMenuItem(from: item))
            }
        } else {
            // Get forward history (oldest first, get ALL available entries)
            let forwardList = backForwardList.forwardList
            for item in forwardList {
                items.append(NavigationHistoryContextMenuItem(from: item))
            }
        }

        return items
    }

    private func refreshHistory() {
        // Force refresh by changing the ID and reloading data
        refreshID = UUID()
        loadHistoryItems()
    }

    private func navigateToHistoryItem(_ item: NavigationHistoryContextMenuItem) {
        guard let tab = browserManager.tabs.controllableSession(in: windowState),
              // Use assignedWebView as fallback to avoid triggering lazy initialization
              let webView = browserManager.webViewCoordinator?.getWebView(for: tab.itemID, in: windowState.id) ?? tab.assignedWebView else { return }

        // Use WebKit's proper navigation history API to jump to the specific item
        // This preserves the back/forward state correctly
        webView.go(to: item.backForwardItem)

        // Force a refresh of navigation button states after a brief delay
        // to ensure the UI updates with the new navigation state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            refreshHistory()
        }
    }

    private func urlDisplayString(_ url: URL) -> String {
        if let host = url.host {
            return host
        }
        return url.absoluteString.prefix(50) + "..."
    }
}

// MARK: - Navigation History Context Menu Item

/// A wrapper around WKBackForwardListItem that preserves the original WebKit navigation item
/// for proper navigation state management when jumping through history
struct NavigationHistoryContextMenuItem: Identifiable {
    let id: UUID
    let url: URL?
    let title: String
    let backForwardItem: WKBackForwardListItem

    init(from backForwardItem: WKBackForwardListItem) {
        self.id = UUID()
        self.url = backForwardItem.url
        self.title = backForwardItem.title ?? backForwardItem.url.host ?? "Untitled"
        self.backForwardItem = backForwardItem
    }
}