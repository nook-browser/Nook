//
//  WindowBackgroundView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct WindowBackgroundView: View {
    @GestureState var isDraggingWindow = false

    var dragWindow: some Gesture {
        WindowDragGesture()
            .updating($isDraggingWindow) { _, state, _ in
                state = true
            }
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                Rectangle()
                    .fill(Color.clear)
                    .blur(radius: 40)
                    .glassEffect(in: .rect(cornerRadius: 0))
            } else {
                BlurEffectView(material: .hudWindow, state: .active)
            }
        }
        .gesture(dragWindow)
    }
}
