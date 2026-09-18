// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  NookDragItem.swift
//  Nook
//

import Foundation
import AppKit
import NookTabsCore
import UniformTypeIdentifiers

extension UTType {
    static let nookTabItem = UTType(exportedAs: "com.nook.tab-drag-item")
}

extension NSPasteboard.PasteboardType {
    static let nookTabItem = NSPasteboard.PasteboardType("com.nook.tab-drag-item")
}

// MARK: - Drop Zone Identity

/// A place a dragged item can land.
enum DropZoneID: Hashable {
    /// A space's favorites grid.
    case favorites(spaceID: UUID)
    /// The rows of a sidebar section (`.pinned` or `.tabs`).
    case section(Parent)
    /// A target without rows (space title, space switcher) that receives the item as a whole.
    case target(Parent)
}

// MARK: - Drag Item

struct NookDragItem: Codable, Equatable {
    /// The dragged `Item` id (name kept for existing pasteboard readers).
    let tabId: UUID
    var title: String
    var urlString: String

    init(tabId: UUID, title: String, urlString: String = "") {
        self.tabId = tabId
        self.title = title
        self.urlString = urlString
    }
}

extension NookDragItem {
    func writeToPasteboard(_ pasteboard: NSPasteboard) {
        pasteboard.declareTypes([.nookTabItem, .string], owner: nil)
        do {
            let data = try JSONEncoder().encode(self)
            pasteboard.setData(data, forType: .nookTabItem)
        } catch {
            NSLog("NookDragItem encoding failed: %@", String(describing: error))
        }
        pasteboard.setString(tabId.uuidString, forType: .string)
    }

    static func fromPasteboard(_ pasteboard: NSPasteboard) -> NookDragItem? {
        guard let data = pasteboard.data(forType: .nookTabItem) else { return nil }
        return try? JSONDecoder().decode(NookDragItem.self, from: data)
    }
}
