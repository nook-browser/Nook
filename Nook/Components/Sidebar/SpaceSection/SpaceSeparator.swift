//
//  SpaceSeparator.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct SpaceSeparator: View {
    @Binding var isHovering: Bool
    let onClear: () -> Void
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        let hasTabs = !browserManager.tabManager.tabs(in: browserManager.tabManager.currentSpace!).isEmpty
        let _ = print("SpaceSeparator isHovering: \(isHovering), hasTabs: \(hasTabs)")

        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 100)
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.trailing, isHovering ? 8 : 0)
                .animation(.smooth(duration: 0.1), value: isHovering)
            
            if hasTabs && isHovering {
                Button(action: onClear) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text("Clear")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(.horizontal, 4)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear all regular tabs")
                .transition(.blur.animation(.smooth(duration: 0.1)))
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
    }
}
