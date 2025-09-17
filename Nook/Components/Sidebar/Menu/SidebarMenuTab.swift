//
//  SidebarMenuTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 17/09/2025.
//

import SwiftUI

struct SidebarMenuTab: View {
    var image: String
    var title: String
    var isActive: Bool = true
    let action: () -> Void
    @State private var isHovering: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: image)
                .font(.system(size: 16, weight: .medium))
            Text(title)
                .font(.system(size: 10, weight: .medium))
        }
        .frame(width: 64, height: 64)
        .background(isActive ?.white.opacity(0.2) : isHovering ? .white.opacity(0.1) : .clear)
        .animation(.linear(duration: 0.1), value: isHovering)
        .animation(.linear(duration: 0.2), value: isActive)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.4), lineWidth: isActive ? 1  :0)
                .animation(.easeInOut(duration: 0.25), value: isActive)
        }
        .onHover { state in
            isHovering = state
        }
        .onTapGesture {
            action()
        }
    }
}
