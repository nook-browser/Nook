//
//  BackgroundStage.swift
//  Nook
//
//  Created by Maciek Bagiński on 17/02/2026.
//

import SwiftUI


struct BackgroundStage: View {
    struct MaterialItem: Identifiable {
        let id: String
        let label: String
        let material: NSVisualEffectView.Material
    }

    @Binding var selectedMaterial: NSVisualEffectView.Material

    let materials: [MaterialItem] = [
        .init(id: "hud", label: "Arc", material: .hudWindow),
        .init(id: "underWindow", label: "Under Window", material: .underWindowBackground),
        .init(id: "titlebar", label: "Titlebar", material: .titlebar),
        .init(id: "selection", label: "Selection", material: .selection),
        .init(id: "menu", label: "Menu", material: .menu),
        .init(id: "popover", label: "Popover", material: .popover),
        .init(id: "sidebar", label: "Sidebar", material: .sidebar),
        .init(id: "header", label: "Header", material: .headerView),
        .init(id: "sheet", label: "Sheet", material: .sheet),
        .init(id: "windowBg", label: "Window Background", material: .windowBackground),
        .init(id: "underPage", label: "Under Page", material: .underPageBackground),
        .init(id: "tooltip", label: "Tooltip", material: .toolTip),
        .init(id: "content", label: "Content", material: .contentBackground),
        .init(id: "fullscreen", label: "Full Screen UI", material: .fullScreenUI),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Text("Background")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .center, spacing: 8) {
                ForEach(Array(stride(from: 0, to: materials.count, by: 3)), id: \.self) { i in
                    HStack(alignment: .center, spacing: 8) {
                        ForEach(materials[i..<min(i + 3, materials.count)]) { item in
                            Button {
                                selectedMaterial = item.material
                            } label: {
                                Text(item.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selectedMaterial == item.material ? .black : .black.opacity(0.6))
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 20)
                                    .background(selectedMaterial == item.material ? .white : .white.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
