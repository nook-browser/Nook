//
//  EmptyWebsiteView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct EmptyWebsiteView: View {
    var body: some View {
        ZStack {
            BlurEffectView(material: .headerView, state: .active)
            Image(systemName: "moon.stars")
                .font(.system(size: 32, weight: .medium))
                .blendMode(.overlay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
