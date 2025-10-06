//
//  HistorySuggestionItem.swift
//  Nook
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
    @Environment(\.colorScheme) var colorScheme
    
    // Color configuration
    private var colors: ColorConfig {
        ColorConfig(
            isDark: colorScheme == .dark,
            isSelected: isSelected,
            isHovered: isHovered
        )
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            ZStack {
                (resolvedFavicon ?? Image(systemName: "globe"))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(colors.faviconColor)
                    .frame(width: 14, height: 14)
            }
            .frame(width: 24, height: 24)
            .background(colors.faviconBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            
            HStack(spacing: 4) {
                Text(entry.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text("-")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.urlColor)
                
                Text(entry.displayURL)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.urlColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
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

// MARK: - Colors simplified
private struct ColorConfig {
    let isDark: Bool
    let isSelected: Bool
    let isHovered: Bool
    
    var titleColor: Color {
        if isSelected {
            return .white
        }
        return isDark ? .white : .black
    }
    
    var urlColor: Color {
        if isSelected {
            return .white.opacity(0.5)
        }
        return isDark ? .white.opacity(0.3) : .black.opacity(0.3)
    }
    
    var faviconColor: Color {
        return .white.opacity(0.5)
    }
    
    var faviconBackground: Color {
        return isSelected ? .white : .clear
    }
}
