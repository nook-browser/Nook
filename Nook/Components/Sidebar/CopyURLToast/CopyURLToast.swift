//
//  CopyURLToast.swift
//  Nook
//
//  Created on 2025-01-XX.
//

import SwiftUI

struct CopyURLToast: View {
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        ToastView {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
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

                Text("Copied Current URL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .transition(.toast)
        .onAppear {
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                windowState.isShowingCopyURLToast = false
            }
        }
        .onTapGesture {
            windowState.isShowingCopyURLToast = false
        }
    }
}

