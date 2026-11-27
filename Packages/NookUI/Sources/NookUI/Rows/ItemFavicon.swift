// Licensed under GPL-3.0. See LICENSE.
//
//  ItemFavicon.swift
//  NookUI
//
//  The favicon every row and tile draws, and the inline-rename state the rows and the
//  context menu share.
//

import SwiftUI
import NookTabsCore
import NookWeb

// MARK: - Rename State

/// The row being renamed inline. Shared so a context menu can start a rename on its row.
@MainActor
@Observable
final class SidebarRenameState {
    static let shared = SidebarRenameState()
    var itemID: UUID?
}

extension TabsController {
    /// Creates a "New Folder" under `parent` after `after` and starts renaming it inline.
    public func createFolderForRename(in parent: Parent, after: UUID?) {
        guard let folderID = createFolder(title: "New Folder", in: parent, after: after) else { return }
        if case .folder(let outer) = parent { openFolder(outer) }
        SidebarRenameState.shared.itemID = folderID
    }
}

// MARK: - Favicon

/// A row or tile favicon: the live page's, else the cached one for the item's host, else a globe.
public struct ItemFavicon: View {
    let item: Item
    let session: PageSession?
    @State private var cached: Image?
    @State private var isDarkMonochrome = false
    @Environment(\.colorScheme) private var colorScheme

    public init(item: Item, session: PageSession?) {
        self.item = item
        self.session = session
    }

    public var body: some View {
        let base = (session?.favicon ?? cached ?? Image(systemName: "globe"))
            .resizable()
            .scaledToFit()
        Group {
            if colorScheme == .dark && isDarkMonochrome {
                base.colorInvert()
            } else {
                base
            }
        }
        // Keyed on the session too: closing a pinned tab or favorite ends its page but keeps
        // the row, and the cached icon must be loaded then.
        .task(id: "\(item.url.flatMap(FaviconCache.key) ?? "")|\(session == nil)") {
            session?.ensureFaviconLoaded()
            guard let host = item.url.flatMap(FaviconCache.key),
                  let image = await FaviconCache.shared.cachedImage(for: host) else { return }
            cached = Image(platformImage: image)
            isDarkMonochrome = Self.detectDarkMonochrome(image)
        }
    }

    /// True when visible pixels are nearly black and uncolored, so dark mode can invert them to white.
    private static func detectDarkMonochrome(_ image: PlatformImage) -> Bool {
        #if os(macOS)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        #else
        guard let cg = image.cgImage else { return false }
        #endif
        let size = 16
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

        var opaqueCount = 0
        var totalLum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255.0
            guard a > 0.2 else { continue }
            let r = Double(pixels[i]) / 255.0 / a
            let g = Double(pixels[i + 1]) / 255.0 / a
            let b = Double(pixels[i + 2]) / 255.0 / a
            if max(r, g, b) - min(r, g, b) > 0.18 { return false }
            totalLum += 0.299 * r + 0.587 * g + 0.114 * b
            opaqueCount += 1
        }
        return opaqueCount > 0 && (totalLum / Double(opaqueCount)) < 0.28
    }
}
