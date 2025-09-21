//
//  WebsitePopup.swift
//  Nook
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI

enum WebsitePopupType {
    case copyCurrentURL
    case cleanUpTabs
}

struct WebsitePopup: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var browserManager: BrowserManager
    let type: WebsitePopupType

    var body: some View {
        HStack {
            content
        }
        .padding(12)
        .background(
            background
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 2)
        }
        .transition(.scale(scale: 0.0, anchor: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var background: some View {
        if #available(macOS 26.0, *) {
            LinearGradient(colors: [browserManager.gradientColorManager.primaryColor, Color(browserManager.gradientColorManager.primaryColor).exposureAdjust(0.1)], startPoint: .leading, endPoint: .trailing)
        } else {
            Color(browserManager.gradientColorManager.primaryColor)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch type {
        case .copyCurrentURL:
            HStack(spacing: 8) {
                Text("Copied current URL")
                    .font(.system(size: 12, weight: .medium))
                IconBadge(symbolName: "square.and.arrow.up")
            }
        case .cleanUpTabs:
            HStack(spacing: 2) {
                Text("Cleared Tabs!")
                    .font(.system(size: 14, weight: .medium))
                Text("Use")
                    .font(.system(size: 14, weight: .medium))
                HStack(spacing: 0) {
                    Image(systemName: "command")
                        .font(.system(size: 12, weight: .medium))
                    Text("Z")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(2)
                .background(.black.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("to undo.")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.black)
        }
    }
}

struct IconBadge: View {
    let symbolName: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .padding(4)
            .background(Color.white.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.4), lineWidth: 1)
            }
    }
}
