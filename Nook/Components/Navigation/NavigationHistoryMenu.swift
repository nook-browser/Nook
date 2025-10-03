//
//  NavigationHistoryMenu.swift
//  Nook
//
//  Created by Jonathan Caudill on 01/10/2025.
//

import SwiftUI
import WebKit

struct NavigationHistoryMenu: View {
    let windowState: BrowserWindowState
    let historyType: HistoryType
    @EnvironmentObject var browserManager: BrowserManager
    @State private var historyItems: [NavigationHistoryItem] = []
    @State private var isVisible = false

    enum HistoryType {
        case back
        case forward
    }

    var body: some View {
        if isVisible && !historyItems.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(historyItems.enumerated()), id: \.element.id) { index, item in
                    NavigationHistoryItemRow(
                        item: item,
                        index: index,
                        historyType: historyType,
                        action: {
                            navigateToHistoryItem(item)
                            hideMenu()
                        }
                    )

                    if index < historyItems.count - 1 {
                        Divider()
                            .padding(.horizontal, 8)
                    }
                }
            }
            .padding(8)
            .background(Color(.windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .frame(maxWidth: 300)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.9).combined(with: .opacity),
                removal: .scale(scale: 0.9).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.2), value: isVisible)
            .onAppear {
                loadHistoryItems()
            }
            .onDisappear {
                isVisible = false
            }
        }
    }

    private func loadHistoryItems() {
        guard let tab = browserManager.currentTab(for: windowState),
              let webView = browserManager.getWebView(for: tab.id, in: windowState.id) ?? tab.webView else {
            historyItems = []
            return
        }

        let backForwardList = webView.backForwardList
        var items: [NavigationHistoryItem] = []

        if historyType == .back {
            // Get back history (most recent first)
            let maxItems = min(10, backForwardList.backList.count)
            for i in stride(from: backForwardList.backList.count - 1, through: backForwardList.backList.count - maxItems, by: -1) {
                if let item = backForwardList.item(at: i) {
                    items.append(NavigationHistoryItem(from: item))
                }
            }
        } else {
            // Get forward history (oldest first)
            let maxItems = min(10, backForwardList.forwardList.count)
            for i in 0..<maxItems {
                if let item = backForwardList.item(at: -(i + 1)) {
                    items.append(NavigationHistoryItem(from: item))
                }
            }
        }

        historyItems = items
    }

    private func navigateToHistoryItem(_ item: NavigationHistoryItem) {
        guard let tab = browserManager.currentTab(for: windowState) else { return }

        if let url = item.url {
            tab.loadURL(url.absoluteString)
        }
    }

    func showMenu() {
        isVisible = true
        loadHistoryItems()
    }

    func hideMenu() {
        isVisible = false
        historyItems.removeAll()
    }
}

struct NavigationHistoryItem: Identifiable {
    let id: UUID
    let url: URL?
    let title: String
    let index: Int

    init(from backForwardItem: WKBackForwardListItem) {
        self.id = UUID()
        self.url = backForwardItem.url
        self.title = backForwardItem.title ?? backForwardItem.url.host ?? "Untitled"
        self.index = 0 // Will be set when creating the array
    }

    init(id: UUID = UUID(), url: URL?, title: String, index: Int) {
        self.id = id
        self.url = url
        self.title = title
        self.index = index
    }
}

struct NavigationHistoryItemRow: View {
    let item: NavigationHistoryItem
    let index: Int
    let historyType: NavigationHistoryMenu.HistoryType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Index indicator
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())

                // Directional icon
                Image(systemName: historyType == .back ? "arrow.backward" : "arrow.forward")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                // Title and URL
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let url = item.url {
                        Text(urlDisplayString(url))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.clear)
        .hoverEffect()
        .buttonStyle(PlainButtonStyle())
    }

    private func urlDisplayString(_ url: URL) -> String {
        if let host = url.host {
            return host
        }
        return url.absoluteString.prefix(50) + "..."
    }
}

extension View {
    func hoverEffect() -> some View {
        self.onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}