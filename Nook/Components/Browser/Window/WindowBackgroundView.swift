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
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .universalGlassEffect(in: .rect(cornerRadius: 0))
            .clipped()
        .backgroundDraggable()
    }
}

