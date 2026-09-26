// Licensed under GPL-3.0. See LICENSE.
//
//  DialogView.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI
import NookUI
import NookWeb

struct DialogView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        let dialogs = browserManager.dialogManager.presentations(in: windowState.id)

        ZStack {
            ForEach(Array(dialogs.enumerated()), id: \.element.id) { index, presentation in
                NookModalOverlay(isPresented: presentation.isPresented, onDismiss: {
                    browserManager.dialogManager.dismiss(presentation.id)
                }) {
                    presentation.content
                }
                .allowsHitTesting(index == dialogs.count - 1)
                .disabled(index != dialogs.count - 1)
                .accessibilityHidden(index != dialogs.count - 1)
            }
        }
        .onChange(of: dialogs.map(\.id)) { old, new in
            if new.count > old.count {
                // Resign WebView first responder so keyboard events reach the dialog
                if let window = NSApp.keyWindow {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }
}
