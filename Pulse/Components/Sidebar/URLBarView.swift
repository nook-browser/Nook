//
//  URLBarView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        ZStack {
            HStack {
                Text(
                    displayURL
                )
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .background(AppColors.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var displayURL: String {
            guard let url = browserManager.tabManager.currentTab?.url else {
                return ""
            }
            return formatURL(url)
        }
        
        private func formatURL(_ url: URL) -> String {
            guard let host = url.host else {
                return url.absoluteString
            }
            
            // Remove www prefix if it exists
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            
            return cleanHost
        }
}
