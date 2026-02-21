//
//  URLBarStage.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import SwiftUI

struct URLBarStage: View {
    @Binding var topBarAddressView: Bool

    var body: some View {
        VStack(spacing: 24){
            Text("URL Bar")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 24) {
                layoutOption(image: "url-in-sidebar", label: "In Sidebar", isTopBar: false)
                layoutOption(image: "url-top-of-website", label: "Top of website", isTopBar: true)
            }
        }
    }

    @ViewBuilder
    private func layoutOption(image: String, label: String, isTopBar: Bool) -> some View {
        VStack(spacing: 12) {
            Button {
                topBarAddressView = isTopBar
            } label: {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.black.opacity(0.2), lineWidth: topBarAddressView == isTopBar ? 4 : 0)
                    }
                    .animation(.easeInOut(duration: 0.1), value: topBarAddressView == isTopBar)
            }
            .buttonStyle(.plain)

            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
