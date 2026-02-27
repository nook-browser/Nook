//
//  NookDragItem.swift
//  Nook
//

import Foundation
import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let nookTabItem = UTType(exportedAs: "com.nook.tab-drag-item")
}

extension NSPasteboard.PasteboardType {
    static let nookTabItem = NSPasteboard.PasteboardType("com.nook.tab-drag-item")
}

// MARK: - Drop Zone Identity

enum DropZoneID: Hashable {
    case essentials
    case spacePinned(UUID)
    case spaceRegular(UUID)
    case folder(UUID)

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
