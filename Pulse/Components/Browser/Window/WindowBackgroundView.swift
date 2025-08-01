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


#if DEBUG
struct WindowBackgroundView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [.blue, .green]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            WindowBackgroundView()
                .padding()
            
            Text("hi there")
                .font(.custom("SF Pro", size: 20))
                .foregroundColor(.gray)
        }
        .frame(width: 300, height: 200)
        .previewLayout(.sizeThatFits)
    }
}
#endif

