//
//  DialogView.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct DialogView: View {
    @Environment(BrowserManager.self) private var browserManager

    var body: some View {
        ZStack {
            if browserManager.dialogManager.isVisible,
               let dialog = browserManager.dialogManager.activeDialog {
                overlayBackground
                dialogContent(dialog)
                    .transition(.asymmetric(
                        insertion: .offset(y: 30).combined(with: .opacity),
                        removal: .offset(y: -30).combined(with: .opacity)
                    ))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: browserManager.dialogManager.isVisible)
    }

    @ViewBuilder
    private var overlayBackground: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture {
                browserManager.dialogManager.closeDialog()
            }
            .transition(.opacity)
    }

    @ViewBuilder
    private func dialogContent(_ dialog: AnyView) -> some View {
        HStack {
            Spacer()
            dialog
            Spacer()
        }
    }
}
