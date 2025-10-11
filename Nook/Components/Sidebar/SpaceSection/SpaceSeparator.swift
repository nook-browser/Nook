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
    @Environment(BrowserManager.self) private var browserManager

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 100)
                .fill(Color.white.opacity(0.1))
                .frame(height: 2)
            if(isHovering && !browserManager.tabManager.tabs(in: browserManager.tabManager.currentSpace!).isEmpty) {
                Button(action: onClear) {
                    Text("↓ Clear")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isClearHovered ? Color.white.opacity(0.6) : Color.white.opacity(0.2))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear all regular tabs")
                .onHover { state in
                    isClearHovered = state
                    
                }
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
    }
}
