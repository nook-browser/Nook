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
            Text(value).font(NookDesign.Font.heading)
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
    private static let width: CGFloat = 320
    private static let cell = CGSize(width: 28, height: 30)
    private static let gridHeight = cell.height * 6 + NookDesign.Spacing.sm * 5   // six rows
    @FocusState private var searchFocused: Bool
    let onSelect: () -> Void
    private let symbols = SpaceIconCatalog.symbols
    private let emojis = SpaceIconCatalog.emojis

    public init(icon: Binding<String>, onSelect: @escaping () -> Void = {}) {
        _icon = icon
        _category = State(initialValue: SpaceIcon.isEmoji(icon.wrappedValue) ? .emojis : .icons)
        self.onSelect = onSelect
    }
    private var query: Binding<String> {
        category == .icons ? $iconQuery : $emojiQuery
    }
    private var results: [String] {
        let words = query.wrappedValue.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let matches: [String]
        if words.isEmpty {
            matches = (category == .icons ? symbols : emojis).map(\.value)
        } else {
            matches = (category == .icons ? symbols : emojis).filter { entry in
                words.allSatisfy { entry.words.contains($0) }
            }.map(\.value)
        }
        // The dot is the first cell of both tabs.
        return words.isEmpty ? [""] + matches : matches
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.lg) {
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
                        .frame(maxWidth: .infinity, minHeight: Self.gridHeight)
                } else {
                    ScrollView(.vertical) { choices(results) }
                        .frame(height: Self.gridHeight)
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
        }
        .padding(NookDesign.Spacing.xl)
        .frame(width: Self.width)
        .onChange(of: emojiQuery) { _, value in
            guard category == .emojis,
                  let character = value.first(where: { SpaceIcon.isEmoji(String($0)) }) else { return }
            choose(String(character))
        }
    }
    private func choices(_ values: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell.width)), count: 8), spacing: NookDesign.Spacing.sm) {
            ForEach(values, id: \.self) { value in
                Button { choose(value) } label: {
                    SpaceIcon(value)
                        .frame(width: Self.cell.width, height: Self.cell.height)
                        .background(isSelected(value) ? Color.accentColor.opacity(0.2) : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.sm))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value.isEmpty ? "Dot" : value)
            }
        }
    }
    private func isSelected(_ value: String) -> Bool {
        value.isEmpty ? SpaceIcon.isDot(icon) : icon == value
    }
    private func choose(_ value: String) {
        icon = value
        onSelect()
    }
}

/// Picker entries: the value to store and the lowercase words a search matches.
struct SpaceIconEntry {
    let value: String
    let words: String
}

enum SpaceIconCatalog {
    static let symbols: [SpaceIconEntry] = symbolNames.map {
        SpaceIconEntry(value: $0, words: $0.replacingOccurrences(of: ".", with: " "))
    }

    /// Every emoji-presentation scalar, plus text-default emoji with U+FE0F, named by Unicode.
    static let emojis: [SpaceIconEntry] = {
        var out: [SpaceIconEntry] = []
        for range in [0x203C...0x3299, 0x1F000...0x1FAFF] {
            for v in range {
                guard let scalar = Unicode.Scalar(v), scalar.properties.isEmoji,
                      !scalar.properties.isEmojiModifier,
                      !(0x1F1E6...0x1F1FF).contains(v), !(0x1F9B0...0x1F9B3).contains(v),
                      scalar.properties.name != nil else { continue }
                let value = scalar.properties.isEmojiPresentation ? String(scalar) : String(scalar) + "\u{FE0F}"
                out.append(SpaceIconEntry(value: value, words: (scalar.properties.name ?? "").lowercased()))
            }
        }
        return out
    }()

    private static let symbolNames = [
        "house.fill", "square.grid.3x3", "briefcase", "building.2", "desktopcomputer", "laptopcomputer", "keyboard", "printer",
        "folder", "doc.text", "tray.full", "calendar", "clock", "alarm", "list.bullet", "checklist",
        "graduationcap", "book", "books.vertical", "pencil", "highlighter", "backpack", "studentdesk", "atom",
        "airplane", "car", "bus", "tram", "bicycle", "figure.walk", "map", "location",
        "globe", "suitcase", "tent", "binoculars", "sailboat", "fuelpump", "mountain.2", "beach.umbrella",
        "dollarsign.circle", "creditcard", "banknote", "chart.line.uptrend.xyaxis", "chart.pie", "cart", "bag", "gift",
        "curlybraces", "chevron.left.forwardslash.chevron.right", "terminal", "hammer", "wrench.and.screwdriver", "gearshape", "cpu", "memorychip",
        "paintpalette", "paintbrush", "pencil.and.ruler", "scribble", "camera", "photo", "film", "theatermasks",
        "music.note", "headphones", "guitars", "pianokeys", "mic", "radio", "speaker.wave.2", "play.rectangle",
        "gamecontroller", "dice", "puzzlepiece", "trophy", "flag", "target", "crown", "sparkles",
        "heart", "heart.text.square", "cross.case", "pills", "bandage", "brain.head.profile", "stethoscope", "lungs",
        "fork.knife", "cup.and.saucer", "wineglass", "birthday.cake", "carrot", "takeoutbag.and.cup.and.straw", "frying.pan", "refrigerator",
        "figure.run", "dumbbell", "soccerball", "basketball", "tennisball", "football", "figure.yoga", "figure.hiking",
        "leaf", "tree", "pawprint", "ladybug", "fish", "hare", "bird", "flame",
        "sun.max", "moon", "cloud", "cloud.rain", "snowflake", "wind", "bolt", "drop",
        "bubble.left", "message", "envelope", "phone", "video", "bell", "megaphone", "at",
        "person", "person.2", "person.3", "figure.2.and.child.holdinghands", "face.smiling", "hand.thumbsup", "hands.clap", "eyes",
        "lightbulb", "key", "lock", "shield", "star", "bookmark", "tag", "pin",
        "magnifyingglass", "link", "paperplane", "cube", "shippingbox", "tortoise", "umbrella", "scissors",
        "newspaper", "archivebox", "trash", "wifi", "battery.100", "externaldrive", "server.rack", "network",
    ]
}
