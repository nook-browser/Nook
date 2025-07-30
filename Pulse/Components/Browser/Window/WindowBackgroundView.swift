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
        ZStack {
            BlurEffectView(material: .hudWindow, state: .active)
        }
        .gesture(dragWindow)
    }
}
