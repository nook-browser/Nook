//
//  WindowBackgroundView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//  Updated by Aether Aurelia on 12/10/2025.
//

import SwiftUI
import UniversalGlass
struct WindowBackgroundView: View {
    @Environment(BrowserManager.self) private var browserManager

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .blur(radius: 40)
            .universalGlassEffect(in: .rect(cornerRadius: 0))
            .clipped()
        .backgroundDraggable()
    }
}

