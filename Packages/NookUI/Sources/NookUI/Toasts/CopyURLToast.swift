// Licensed under GPL-3.0. See LICENSE.
//
//  CopyURLToast.swift
//  Nook
//
//  Created on 2025-01-XX.
//

import SwiftUI
import NookDesign
import NookWeb

public struct CopyURLToast: View {
    @Environment(BrowserWindowState.self) private var windowState

    public init() {}

    public var body: some View {
        ToastView {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .padding(4)
                    .background(Color.white.opacity(0.2))
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                    .overlay {
                        NookDesign.Radius.shape(NookDesign.Radius.sm)
                            .stroke(.white.opacity(0.4), lineWidth: 1)
                    }

                Text("Copied Current URL")
                    .font(NookDesign.Font.secondary)
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

