// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  WebsiteLoadingIndicator.swift
//  Nook
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import SwiftUI
import NookDesign
import NookWeb

struct WebsiteLoadingIndicator: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    
    var body: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: indicatorWidth, height: 3)
                .animation(NookDesign.Motion.spring, value: indicatorWidth)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 8)
        .background(
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    zoomCurrentWindow()
                }
        )
        
        
    }
    
    private var indicatorWidth: CGFloat {
        switch browserManager.tabs.selectedSession(in: windowState)?.loadingState {
        case .idle:
            return 50
        case .didStartProvisionalNavigation:
            return 150
        case .didCommit:
            return 300
        case .didFinish:
            return 0
        case .didFail:
            return 0
        case .didFailProvisionalNavigation:
            return 0
        case .none:
            return 0
        }
    }
}
