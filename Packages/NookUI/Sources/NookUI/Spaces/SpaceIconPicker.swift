// Licensed under GPL-3.0. See LICENSE.
import SwiftUI
import NookDesign
#if os(macOS)
import AppKit
#endif

/// Existing space icon strings store either an SF Symbol name or one emoji grapheme.
public struct SpaceIcon: View {
    let value: String
    public init(_ value: String) { self.value = value }
    /// Empty, or one of the placeholder icons spaces carried before the picker existed: all draw
    /// as the plain accent dot.
    public static func isDot(_ value: String) -> Bool {
        value.isEmpty || ["square.grid.2x2", "house", "person.fill"].contains(value)
    }
    public static func isEmoji(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 127 }
    }
    public var body: some View {
        if Self.isDot(value) {
            Circle().frame(width: NookDesign.Spacing.sm, height: NookDesign.Spacing.sm)
        } else if Self.isEmoji(value) {
            Text(value).font(.system(size: 17))
        } else {
            Image(systemName: value).font(.system(size: 15, weight: .medium))
        }
    }
}

public struct SpaceIconPicker: View {
    @Binding var icon: String
    private enum Category: String, CaseIterable { case icons = "Icons", emojis = "Emojis" }
    @State private var category: Category = .icons
    @State private var iconQuery = ""
    @State private var emojiQuery = ""
    @FocusState private var searchFocused: Bool
    let onSelect: () -> Void
    private let symbols = ["house", "briefcase", "book", "globe", "heart", "star", "leaf", "airplane", "gamecontroller", "music.note", "paintpalette", "curlybraces", "camera", "cup.and.saucer", "cart", "square.grid.2x2"]
    private let emojis = ["🏠", "💼", "📚", "🌍", "❤️", "⭐️", "🌿", "✈️", "🎮", "🎵", "🎨", "🚀", "🐈", "☕️", "🌈", "🧠"]
    private let symbolNames = ["maison home", "travail bureau work office", "livre lecture reading", "monde internet world", "coeur amour love", "étoile favori favorite", "feuille nature plant", "avion voyage travel", "jeu jeux gaming", "musique audio", "peinture art couleurs", "code développement development", "photo appareil", "café coffee", "achats shopping", "grille applications apps"]
    private let emojiNames = ["maison home house", "travail bureau work office briefcase", "livres lecture books reading", "monde terre earth world", "coeur amour heart love", "étoile star favori", "feuille plante leaf nature", "avion voyage airplane travel", "jeux games gaming", "musique music", "peinture art paint", "fusée rocket espace space", "chat cat", "café coffee", "arc-en-ciel rainbow", "cerveau brain"]

    public init(icon: Binding<String>, onSelect: @escaping () -> Void = {}) {
        _icon = icon
        _category = State(initialValue: SpaceIcon.isEmoji(icon.wrappedValue) ? .emojis : .icons)
        self.onSelect = onSelect
    }
    private var query: Binding<String> {
        category == .icons ? $iconQuery : $emojiQuery
    }
    private var results: [String] {
        let values = category == .icons ? symbols : emojis
        let names = category == .icons ? symbolNames : emojiNames
        let words = query.wrappedValue.split(whereSeparator: \.isWhitespace).map(String.init)
        return values.enumerated().compactMap { index, value in
            let searchable = value + " " + names[index]
            return words.allSatisfy { searchable.localizedStandardContains($0) } ? value : nil
        }
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Space icon").font(.headline)
            Picker("Category", selection: $category) {
                Text("Icons").tag(Category.icons)
                Text("Emojis").tag(Category.emojis)
            }
            .pickerStyle(.segmented)
            TextField(category == .icons ? "Search icons…" : "Search or paste an emoji…", text: query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            Group {
                if results.isEmpty {
                    Text("No results").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 66)
                } else {
                    choices(results).frame(minHeight: 66, alignment: .top)
                }
            }
            if category == .emojis {
                #if os(macOS)
                Button("Emoji & Symbols…", systemImage: "face.smiling") {
                    searchFocused = true
                    DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
                }
                .buttonStyle(.plain)
                #endif
            }
            Divider()
            Button("Use a dot") { choose("") }
                .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 320)
        .onChange(of: emojiQuery) { _, value in
            guard category == .emojis,
                  let character = value.first(where: { SpaceIcon.isEmoji(String($0)) }) else { return }
            choose(String(character))
        }
    }
    private func choices(_ values: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 8), spacing: 6) {
            ForEach(values, id: \.self) { value in
                Button { choose(value) } label: {
                    SpaceIcon(value)
                        .frame(width: 28, height: 30)
                        .background(icon == value ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value)
            }
        }
    }
    private func choose(_ value: String) {
        icon = value
        onSelect()
    }
}
