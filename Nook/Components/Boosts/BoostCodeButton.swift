//
//  BoostCodeButton.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import SwiftUI

struct BoostCodeButton: View {
    @State private var isHovered: Bool = false
    var isActive: Bool
    var onClick: () -> Void

    var body: some View {
        Button {
            onClick()
        } label: {
            HStack {
                Text("Code")
                    .font(
                        .system(size: 14, weight: .semibold, design: .rounded)
                    )
                    .foregroundStyle(
                        isActive ? .white.opacity(0.8) : .black.opacity(0.75)
                    )
                Spacer()
                Text("{}")
                    .font(
                        .system(size: 14, weight: .semibold, design: .rounded)
                    )
                    .foregroundStyle(
                        isActive ? .white.opacity(0.8) : .black.opacity(0.75)
                    )

            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isActive
                    ? .black.opacity(0.8)
                    : isHovered ? .black.opacity(0.1) : .black.opacity(0.07)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .animation(.linear(duration: 0.1), value: isActive)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { state in
            isHovered = state
        }
    }
}

#Preview {
    BoostCodeButton(isActive: false, onClick: {})
        .frame(width: 300, height: 300)
}
