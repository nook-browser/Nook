//
//  HistorySuggestionItem.swift
//  Pulse
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI
import FaviconFinder

struct HistorySuggestionItem: View {
    let entry: HistoryEntry
    var isSelected: Bool = false
    
    @State private var isHovered: Bool = false
    @State private var resolvedFavicon: SwiftUI.Image? = nil
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            (resolvedFavicon ?? Image(systemName: "globe"))
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(.white.opacity(0.2))
            HStack(spacing: 6) {
                Text(entry.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("-")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                Text(entry.displayURL)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            Task { await fetchFavicon(for: entry.url) }
        }
    }
    
    private func fetchFavicon(for url: URL) async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        guard url.scheme == "http" || url.scheme == "https", url.host != nil else {
            await MainActor.run { self.resolvedFavicon = defaultFavicon }
            return
        }
        
        // Check cache first
        let cacheKey = url.host ?? url.absoluteString
        if let cachedFavicon = Tab.getCachedFavicon(for: cacheKey) {
            await MainActor.run { self.resolvedFavicon = cachedFavicon }
            return
        }
        
        do {
            let favicon = try await FaviconFinder(url: url)
                .fetchFaviconURLs()
                .download()
                .largest()
            if let faviconImage = favicon.image {
                let nsImage = faviconImage.image
                let swiftUIImage = SwiftUI.Image(nsImage: nsImage)
                
                // Cache the favicon
                Tab.cacheFavicon(swiftUIImage, for: cacheKey)
                
                await MainActor.run { self.resolvedFavicon = swiftUIImage }
            } else {
                await MainActor.run { self.resolvedFavicon = defaultFavicon }
            }
        } catch {
            await MainActor.run { self.resolvedFavicon = defaultFavicon }
        }
    }
}

