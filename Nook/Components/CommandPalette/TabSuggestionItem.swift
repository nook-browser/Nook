//
//  TabSuggestionItem.swift
//  Nook
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI

struct TabSuggestionItem: View {
    let tab: Tab
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            tab.favicon
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.white.opacity(0.2))
                .padding(6)
                .background(isSelected ? .white : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(tab.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            HStack(spacing: 6) {
                Text("Switch to Tab")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.3))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        isSelected ? Color(hex: "4148D7") : .white.opacity(0.5)
                    )
                    .frame(width: 14, height: 14)
                    .padding(5)
                    .background(isSelected ? .white : .white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

}
