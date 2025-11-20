//
//  BoostZapButton.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import SwiftUI

struct BoostZapButton: View {
    @State private var isHovered: Bool = false
    @Binding var isActive: Bool
    var onClick: () -> Void

    var body: some View {
        Button {
            isActive.toggle()
            onClick()
        } label: {
            HStack {
                Text("Zap")
                    .font(
                        .system(size: 14, weight: .semibold, design: .rounded)
                    )
                    .foregroundStyle(
                        isActive ? .white.opacity(0.8) : .black.opacity(0.75)
                    )
                Spacer()
                Image(systemName: "bolt.fill")
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
    @Previewable @State var isActive = false
    BoostZapButton(isActive: $isActive, onClick: {})
        .frame(width: 300, height: 300)
}
