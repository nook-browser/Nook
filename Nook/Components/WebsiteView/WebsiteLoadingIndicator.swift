//
//  WebsiteLoadingIndicator.swift
//  Nook
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import SwiftUI

struct WebsiteLoadingIndicator: View {
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 100)
                .fill(Color.white.opacity(0.3))
                .frame(width: indicatorWidth, height: 3)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: indicatorWidth)
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
        switch browserManager.tabManager.currentTab?.loadingState {
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
