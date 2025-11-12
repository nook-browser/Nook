//
//  SpaceSeparator.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct SpaceSeparator: View {
    var isHovering: Bool = false
    let onClear: () -> Void
    @State private var isClearHovered: Bool = false
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        let hasTabs = !browserManager.tabManager.tabs(in: browserManager.tabManager.currentSpace!).isEmpty
        let showClearButton = isHovering && hasTabs
        
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 100)
                .fill(Color.white.opacity(0.1))
                .frame(height: 2)
                .frame(maxWidth: showClearButton ? .infinity : .infinity)
                .padding(.trailing, showClearButton ? 8 : 0)
                .animation(.easeInOut(duration: 0.15), value: showClearButton)
            
            if hasTabs {
                Button(action: onClear) {
                    Text("↓ Clear")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isClearHovered ? Color.white.opacity(0.6) : Color.white.opacity(0.2))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear all regular tabs")
                .opacity(showClearButton ? 1 : 0)
                .offset(x: showClearButton ? 0 : 20)
                .frame(width: showClearButton ? nil : 0)
                .animation(.easeInOut(duration: 0.15), value: showClearButton)
                .onHover { state in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isClearHovered = state
                    }
                }
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
    }
}
