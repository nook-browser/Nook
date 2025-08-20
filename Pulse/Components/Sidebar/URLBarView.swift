//
//  URLBarView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var isHovering: Bool = false

    var body: some View {
        Button {
            browserManager.isCommandPaletteVisible = true
        } label: {
            ZStack {
                HStack(spacing: 8) {
                    if(browserManager.tabManager.currentTab != nil) {
                        Text(
                            displayURL
                        )
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.5))
                        Text("Search or Enter URL...")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    // Extension action buttons
                    if #available(macOS 15.5, *),
                       let extensionManager = browserManager.extensionManager {
                        ExtensionActionView(extensions: extensionManager.installedExtensions)
                            .environmentObject(browserManager)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
            .background(
                ZStack {
                    BlurEffectView(material: browserManager.settingsManager.currentMaterial, state: .active)
                    Color.white.opacity(isHovering ? 0.2 : 0.1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        
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
            
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            
            return cleanHost
        }
}
