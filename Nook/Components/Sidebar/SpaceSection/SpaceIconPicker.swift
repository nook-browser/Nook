//
//  SpaceIconPicker.swift
//  Nook
//
//  Curated SF Symbol grid shown in a popover. Replaces the emoji picker.
//

import SwiftUI

struct SpaceIconPicker: View {
    let selected: String
    let onPick: (String) -> Void

    static let symbols: [String] = [
        "square.grid.2x2", "briefcase", "house", "star", "book", "cart", "gamecontroller", "music.note",
        "film", "graduationcap", "heart", "leaf", "flame", "bolt", "globe", "chevron.left.forwardslash.chevron.right",
        "terminal", "hammer", "wrench.and.screwdriver", "paintbrush", "camera", "photo", "map", "airplane",
        "car", "building.2", "person", "person.2", "envelope", "message", "phone", "calendar",
        "clock", "folder", "tray", "doc", "note.text", "chart.bar", "dollarsign.circle", "creditcard",
        "tag", "bookmark", "flag", "mappin", "bell", "gearshape", "sparkles", "eye",
    ]

    private let columns = Array(repeating: GridItem(.fixed(NookDesign.Size.iconButton), spacing: NookDesign.Spacing.xs), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: NookDesign.Spacing.xs) {
            ForEach(Self.symbols, id: \.self) { symbol in
                Button {
                    onPick(symbol)
                } label: {
                    Image(systemName: symbol)
                        .font(NookDesign.Font.title)
                        .foregroundStyle(symbol == selected ? Color.accentColor : .primary)
                        .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
                        .background(
                            NookDesign.Radius.shape(NookDesign.Radius.sm)
                                .fill(symbol == selected ? NookDesign.Surface.fillPressed : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(symbol)
            }
        }
        .padding(NookDesign.Spacing.lg)
    }
}
