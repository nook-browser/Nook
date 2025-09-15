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
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(.white.opacity(0.2))
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
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
    }
}
