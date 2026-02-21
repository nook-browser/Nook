//
//  AiChatStage.swift
//  Nook
//
//  Created by Maciek Bagiński on 17/02/2026.
//

import SwiftUI

struct AiChatStage: View {
    @Binding var aiChatEnabled: Bool

    var body: some View {
        VStack(spacing: 24){
            Text("AI Chat")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 24) {
                layoutOption(image: "ai-chat-on", label: "On", enabled: true)
                layoutOption(image: "ai-chat-off", label: "Off", enabled: false)
            }
        }
    }

    @ViewBuilder
    private func layoutOption(image: String, label: String, enabled: Bool) -> some View {
        VStack(spacing: 12) {
            Button {
                aiChatEnabled = enabled
            } label: {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.black.opacity(0.2), lineWidth: aiChatEnabled == enabled ? 4 : 0)
                    }
                    .animation(.easeInOut(duration: 0.1), value: aiChatEnabled == enabled)
            }
            .buttonStyle(.plain)

            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
