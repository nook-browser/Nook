//
//  IconPickerView.swift
//  Nook
//
//  Curated SF Symbols picker for profile icons with search and categories.
//

import SwiftUI
import AppKit

struct IconPickerView: View {
    @Binding var selectedIcon: String
    @State private var searchText: String = ""

    private let columns = Array(repeating: GridItem(.flexible(minimum: 28, maximum: 44), spacing: 8), count: 8)

    // Curated categories
    private let categories: [(title: String, icons: [String])] = [
        ("People", [
            "person", "person.fill", "person.circle", "person.circle.fill", "person.crop.circle",
            "person.crop.circle.fill", "person.badge.plus", "person.fill.checkmark", "person.2",
            "person.2.fill", "person.2.circle", "person.3", "person.3.fill", "person.and.arrow.left.and.arrow.right",
            "person.crop.square", "person.wave.2", "person.text.rectangle"
        ]),
        ("Work", [
            "laptopcomputer", "desktopcomputer", "briefcase", "folder", "folder.fill", "doc",
            "doc.fill", "calendar", "calendar.badge.clock", "tray", "tray.full"
        ]),
        ("Personal", [
            "house", "house.fill", "sparkles", "leaf", "bolt.heart", "paintbrush",
            "music.note", "camera", "gamecontroller", "book", "book.fill"
        ])
    ]

    // Combined list for search (availability filtered)
    private var allIcons: [String] {
        categories.flatMap { $0.icons }.filter { isSymbolAvailable($0) }
    }

    private var filteredIcons: [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.isEmpty == false else { return allIcons }
        return allIcons.filter { $0.contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NookTextField(text: $searchText, placeholder: "Search icons", variant: .default, iconName: "magnifyingglass")

            if searchText.isEmpty {
                // Show grouped categories
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(group.icons.filter { isSymbolAvailable($0) }, id: \.self) { icon in
                                    iconCell(icon)
                                }
                            }
                        }
                    }
                }
            } else {
                // Show filtered results only
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredIcons, id: \.self) { icon in
                        iconCell(icon)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Icon Picker")
    }

    @ViewBuilder
    private func iconCell(_ name: String) -> some View {
        Button(action: { selectedIcon = name }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedIcon == name ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedIcon == name ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selectedIcon == name ? 1.5 : 1)
                Image(systemName: name)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(selectedIcon == name ? Color.accentColor : Color.primary)
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selectedIcon == name ? .isSelected : [])
    }
}

// MARK: - Availability Helper
private func isSymbolAvailable(_ name: String) -> Bool {
    // Filter SF Symbols not present on current macOS
    return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
}
