//
//  NookDragItem.swift
//  Nook
//
//  Custom pasteboard type and drag data model for AppKit-based tab dragging.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Custom UTType

extension UTType {
    static let nookTabItem = UTType(exportedAs: "com.nook.tab-drag-item")
}

// MARK: - NSPasteboard.PasteboardType

extension NSPasteboard.PasteboardType {
    static let nookTabItem = NSPasteboard.PasteboardType("com.nook.tab-drag-item")
}

// MARK: - Drop Zone Identity

enum DropZoneID: Hashable {
    case essentials
    case spacePinned(UUID)
    case spaceRegular(UUID)
    case folder(UUID)

    /// Convert to the existing DragContainer used by TabManager.handleDragOperation
    var asDragContainer: TabDragManager.DragContainer {
        switch self {
        case .essentials: return .essentials
        case .spacePinned(let id): return .spacePinned(id)
        case .spaceRegular(let id): return .spaceRegular(id)
        case .folder(let id): return .folder(id)
        }
    }

    var spaceId: UUID? {
        switch self {
        case .essentials: return nil
        case .spacePinned(let id): return id
        case .spaceRegular(let id): return id
        case .folder: return nil
        }
    }
}

// MARK: - Drag Item

struct NookDragItem: Codable, Equatable {
    let tabId: UUID
    var title: String
    var urlString: String

    init(tabId: UUID, title: String, urlString: String = "") {
        self.tabId = tabId
        self.title = title
        self.urlString = urlString
    }
}

// MARK: - Pasteboard Support

extension NookDragItem {
    func writeToPasteboard(_ pasteboard: NSPasteboard) {
        pasteboard.declareTypes([.nookTabItem, .string], owner: nil)
        if let data = try? JSONEncoder().encode(self) {
            pasteboard.setData(data, forType: .nookTabItem)
        }
        // Also write tab ID as string for backward compatibility
        pasteboard.setString(tabId.uuidString, forType: .string)
    }

    static func fromPasteboard(_ pasteboard: NSPasteboard) -> NookDragItem? {
        guard let data = pasteboard.data(forType: .nookTabItem) else { return nil }
        return try? JSONDecoder().decode(NookDragItem.self, from: data)
    }
}
