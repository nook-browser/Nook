//
//  PinnedButtonView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct PinnedButtonView: View {
    var iconName: String
    var action: (() -> Void)?
    var isActive: Bool = false
    @State private var isHovered: Bool = false
    
    init(iconName: String, action: (() -> Void)? = nil, isActive: Bool) {
        self.iconName = iconName
        self.action = action
        self.isActive = isActive
    }
    
    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.4))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
