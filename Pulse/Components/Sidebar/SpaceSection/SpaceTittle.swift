//
//  SpaceTittle.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI


struct SpaceTittle: View {
    var spaceName: String
    var spaceIcon: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: spaceIcon)
                .font(.system(size: 12))
            Text(spaceName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}
