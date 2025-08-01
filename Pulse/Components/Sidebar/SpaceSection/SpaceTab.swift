//
//  SpaceTab.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct SpaceTab: View {
    var tabName: String
    var tabURL: String
    var tabIcon: SwiftUI.Image // Changed from String to SwiftUI.Image
    var isActive: Bool
    var action: () -> Void
    var onClose: () -> Void
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                tabIcon // Directly use the SwiftUI.Image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(tabName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.textPrimary)
                            .padding(4)
                            .background(AppColors.controlBackgroundHover)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(
                backgroundColor
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle()) // Removes default button styling
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private var backgroundColor: Color {
        if isActive {
            return AppColors.controlBackgroundActive
        } else if isHovering {
            return AppColors.controlBackgroundHover
        } else {
            return Color.clear
        }
    }
}

