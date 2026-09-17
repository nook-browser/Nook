//
//  TabClosureToast.swift
//  Nook
//
//  Created by Jonathan Caudill on 02/10/2025.
//

import SwiftUI
import NookDesign

struct TabClosureToast: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        ToastView {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
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

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(browserManager.tabClosureToastCount) tab\(browserManager.tabClosureToastCount > 1 ? "s" : "") closed")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.white)

                    Text("Press ⌘Z to undo")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .transition(.toast)
        .onAppear {
            // Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                browserManager.hideTabClosureToast()
            }
        }
        .onTapGesture {
            browserManager.hideTabClosureToast()
        }
    }
}
