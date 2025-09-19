//
//  SpaceSeparator.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct SpaceSeparator: View {
    var isHovering: Bool
    @State private var isClearHovered: Bool = false
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 100)
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
            if(isHovering) {
                Button {
                } label: {
                    Text("􀄩 Clear")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isClearHovered ? .white : Color.white.opacity(0.3))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { state in
                    isClearHovered = state
                }
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
    }
}
