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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.white.opacity(0.2))
                .padding(6)
                .background(isSelected ? .white : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}
