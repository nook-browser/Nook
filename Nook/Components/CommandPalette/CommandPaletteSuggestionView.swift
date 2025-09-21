//
//  CommandPaletteSuggestionView.swift
//  Nook
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import FaviconFinder
import SwiftUI

struct CommandPaletteSuggestionView: View {
    var favicon: SwiftUI.Image
    var text: String
    var secondaryText: String? = nil
    var isTabSuggestion: Bool = false
    var isSelected: Bool = false
    var historyURL: URL? = nil
    @State private var isHovered: Bool = false
    @State private var resolvedFavicon: SwiftUI.Image? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            (resolvedFavicon ?? favicon)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.white.opacity(0.2))
                .padding(6)
                .background(isSelected ? .white : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            if let secondary = secondaryText, !secondary.isEmpty {
                HStack(spacing: 6) {
                    Text(text)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("-")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(secondary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color(hex: "4148D7") : .clear)
        .onAppear {
            guard let url = historyURL else { return }
            Task { await fetchFavicon(for: url) }
        }
    }

    // MARK: - Favicon Fetching (for history items)

    private func fetchFavicon(for url: URL) async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        // Skip favicon fetching for non-web schemes
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
