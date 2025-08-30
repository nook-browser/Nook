//
//  SpaceSeparator.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct SpaceSeparator: View {
    @State private var isHovering: Bool = false
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 100)
                .fill(Color.white.opacity(0.1))
                .frame(height: 2)
            if(isHovering) {
                Button {
                    
                } label: {
                    Text("↓ Clear")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.2))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        
        
    }
}
