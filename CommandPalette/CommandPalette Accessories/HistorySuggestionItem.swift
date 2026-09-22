// Licensed under GPL-3.0. See LICENSE.
//
//  HistorySuggestionItem.swift
//  Nook
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI
import NookDesign
import NookWeb
import FaviconFinder
import NookUI

struct HistorySuggestionItem: View {
    let entry: HistoryEntry
    var isSelected: Bool = false
    
    @State private var isHovered: Bool = false
    @State private var resolvedFavicon: SwiftUI.Image? = nil

    // Color configuration
    private var colors: ColorConfig {
        ColorConfig(
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
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
            
            HStack(spacing: 4) {
                Text(entry.displayTitle)
                    .font(NookDesign.Font.label)
                    .foregroundStyle(colors.titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text("-")
                    .font(NookDesign.Font.label)
                    .foregroundStyle(colors.urlColor)
                
                Text(entry.displayURL)
                    .font(NookDesign.Font.label)
                    .foregroundStyle(colors.urlColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
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
        if let cachedFavicon = await FaviconCache.shared.cachedImage(for: cacheKey).map(SwiftUI.Image.init(nsImage:)) {
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
                
                FaviconCache.shared.store(nsImage, for: cacheKey)
                
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
    let isSelected: Bool
    let isHovered: Bool

    var titleColor: Color {
        if isSelected {
            return .white
        }
        return .primary
    }

    var urlColor: Color {
        if isSelected {
            return .white.opacity(0.5)
        }
        return .secondary
    }
    
    var faviconColor: Color {
        return isSelected ? .white.opacity(0.7) : .secondary
    }
    
    var faviconBackground: Color {
        return isSelected ? .white : NookDesign.Surface.fill
    }
}
