//
//  GenericSuggestionItem.swift
//  Nook
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI

struct GenericSuggestionItem: View {
    let icon: Image
    let text: String
    var isSelected: Bool = false
    
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(isSelected ? .white : isDark ? .white.opacity(0.7) : .black.opacity(0.7))
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : isDark ? .white.opacity(0.6) : .black.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
