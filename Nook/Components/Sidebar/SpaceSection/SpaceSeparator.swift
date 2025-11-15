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
                .padding(.trailing, showClearButton ? 8 : 0)
                .animation(.easeInOut(duration: 0.05), value: showClearButton)
            
            if hasTabs {
                Button(action: onClear) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text("Clear")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(isClearHovered ? Color.white.opacity(0.8) : Color.white.opacity(0.3))
                    .padding(.horizontal, 4)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear all regular tabs")
                .opacity(showClearButton ? 1 : 0)
                .onHover { state in
                    withAnimation(.easeInOut(duration: 0.05)) {
                        isClearHovered = state
                    }
                }
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
    }
}
