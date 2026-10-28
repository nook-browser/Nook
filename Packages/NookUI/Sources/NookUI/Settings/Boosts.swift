// Licensed under GPL-3.0. See LICENSE.
//
//  Boosts.swift
//  Nook
//

import SwiftUI
import UniformTypeIdentifiers
import NookDesign
import NookTabsCore
import NookSettings

/// The panel that opens over a page from the site menu.
///
/// It edits a draft. The host app shows the draft on the open page through `onPreview`, and
/// nothing reaches settings until Save, so a slider drag never writes. Several Boosts can match
/// one site: each has its own on switch, all the enabled ones apply together in list order, and
/// the header menu chooses which one is being edited.
public struct BoostPanel: View {
    let settings: NookSettingsService
    let host: String
    let onPreview: (Boost) -> Void
    /// Lets the person click an element on the page; returns its selector, or nil if cancelled.
    let onZap: () async -> String?
    let onCancelZap: () -> Void
    /// Called when the panel should go away; the host re-applies the saved state.
    let onFinish: () -> Void

    @State private var draft: Boost
    /// What the draft started from, to tell an edited draft from an untouched one.
    @State private var baseline: Boost
    @State private var showingAdjust = false
    @State private var showingCode = false
    @State private var renaming = false
    @State private var showingLibrary = false
    @State private var zapping = false
    @State private var lastZap: String?  // the selector Zap added last
    @State private var importing = false
    @State private var exporting = false
    @State private var pending: [Boost] = []
    @State private var message: String?
    @State private var baitWarning = false

    @Environment(\.colorScheme) private var colorScheme

    private let width: CGFloat = 264
    private let maxHeight: CGFloat = 680
    private let tileHeight: CGFloat = 40

    public init(
        settings: NookSettingsService, host: String,
        onPreview: @escaping (Boost) -> Void,
        onZap: @escaping () async -> String?, onCancelZap: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.settings = settings
        self.host = host
        self.onPreview = onPreview
        self.onZap = onZap
        self.onCancelZap = onCancelZap
        self.onFinish = onFinish
        let first = settings.boosts.first { $0.host == host }
            ?? Boost(name: "Boost 1", host: host)
        _draft = State(initialValue: first)
        _baseline = State(initialValue: first)
    }

    // MARK: - State

    private var saved: Boost? { settings.boosts.first { $0.id == draft.id } }
    private var isDirty: Bool { draft != baseline }
    private var siblings: [Boost] { settings.boosts.filter { $0.host == draft.host } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showingLibrary {
                library.padding(NookDesign.Spacing.lg)
            } else {
                header
                Divider()
                ScrollView {
                    VStack(spacing: NookDesign.Spacing.md) {
                        colorPad
                        colorTiles
                        if showingAdjust { adjustments.transition(.opacity.combined(with: .move(edge: .top))) }
                        fontGrid
                        HStack(spacing: NookDesign.Spacing.sm) {
                            sizeButton
                            caseButton
                        }
                        zapRow
                        codeRow
                        if showingCode { codeTab.transition(.opacity.combined(with: .move(edge: .top))) }
                    }
                    .padding(NookDesign.Spacing.lg)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: width)
        .frame(maxHeight: maxHeight)
        .animation(NookDesign.Motion.standard, value: showingAdjust)
        .animation(NookDesign.Motion.standard, value: showingCode)
        .onChange(of: draft) { _, new in onPreview(new) }
        // As in Arc there is no Save button: an edit is kept a moment after it stops, and on close.
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled, isDirty { save() }
        }
        .onExitCommand { zapping ? cancelZap() : requestClose() }
        .onDisappear {
            if zapping { onCancelZap() }
            if isDirty { save() }
        }
        .fileExporter(isPresented: $exporting, document: BoostFile(data: BoostBundle.export(settings.boosts) ?? Data()),
                      contentType: .json, defaultFilename: "Nook Boosts") { _ in }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard let url = try? result.get() else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                pending = try BoostBundle.parse(Data(contentsOf: url))
            } catch let failure as BoostBundle.Failure {
                message = failure.message
            } catch {
                message = "The file could not be read."
            }
        }
        .alert("Import Boosts?", isPresented: Binding(get: { !pending.isEmpty }, set: { if !$0 { pending = [] } })) {
            Button("Import") {
                settings.boosts.append(contentsOf: pending.prefix(max(0, Boost.maxCount - settings.boosts.count)))
                pending = []
            }
            Button("Cancel", role: .cancel) { pending = [] }
        } message: {
            let hosts = Set(pending.map(\.host)).sorted().joined(separator: ", ")
            let scripts = pending.contains { !$0.script.isEmpty } ? " Scripts are imported turned off." : ""
            Text("\(pending.count) Boost(s) for \(hosts).\(scripts)")
        }
        .alert("CSS Not Saved", isPresented: $baitWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Rules that mention player-ads were removed. Hiding it makes YouTube refuse to play.")
        }
        .alert("Can't Import", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            Button(action: requestClose) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .font(NookDesign.Font.title)
                .foregroundStyle(.secondary)
                .help("Close")
                .accessibilityLabel("Close Boost panel")
            Spacer(minLength: 0)
            if renaming {
                TextField("Boost name", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(NookDesign.Font.label)
                    .multilineTextAlignment(.center)
                    .onSubmit { renaming = false }
            } else {
                boostMenu
            }
            Spacer(minLength: 0)
            Button { draft.resetVisuals() } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.plain)
                .font(NookDesign.Font.title)
                .foregroundStyle(.secondary)
                .help("Reset to the site's own look")
                .accessibilityLabel("Reset Boost")
        }
        .padding(.horizontal, NookDesign.Spacing.md)
        .frame(height: NookDesign.Size.bottomBar)
    }

    /// The Boost's name, opening everything about it: this site's other Boosts, on and off, rename,
    /// presets, the library, import and export.
    private var boostMenu: some View {
        Menu {
            ForEach(siblings) { boost in
                Button {
                    select(boost)
                } label: {
                    let title = boost.name.isEmpty ? boost.host : boost.name
                    let text = boost.isEnabled ? title : "\(title) (off)"
                    if boost.id == draft.id { Label(text, systemImage: "checkmark") } else { Text(text) }
                }
            }
            Button("New Boost") {
                select(Boost(name: "Boost \(siblings.count + 1)", host: draft.host))
            }
            Divider()
            Button(draft.isEnabled ? "Turn Off Boost" : "Turn On Boost") { draft.isEnabled.toggle() }
            Button("Rename…") { renaming = true }
            Toggle("Include subdomains", isOn: $draft.includeSubdomains)
            Menu("Presets") {
                ForEach(Boost.Preset.allCases, id: \.self) { preset in
                    Button(preset.rawValue) { draft.apply(preset) }
                }
            }
            Divider()
            Button("All Boosts…") { showingLibrary = true }
            Button("Import Boosts…") { importing = true }
            Button("Export Boosts…") { exporting = true }.disabled(settings.boosts.isEmpty)
            Divider()
            Button("Delete Boost", role: .destructive, action: delete)
        } label: {
            HStack(spacing: NookDesign.Spacing.xs) {
                Text(draft.name.isEmpty ? "My Boost" : draft.name)
                    .font(NookDesign.Font.label)
                    .lineLimit(1)
                    .opacity(draft.isEnabled ? 1 : 0.5)
                Image(systemName: "chevron.down")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help(draft.host)
        .accessibilityLabel("Boost options")
    }

    // MARK: - Color

    /// The color pad: the dot's direction is the page's color, its distance from the middle how
    /// strongly it tints; the middle is no color.
    private var colorPad: some View {
        ThemeCanvas(theme: colorPoint, isDark: colorScheme == .dark, showsControls: false)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel("Page color")
    }

    private var colorPoint: Binding<SpaceTheme> {
        let range = Boost.tintStrengthRange
        return Binding(
            get: {
                guard Boost.isHexColor(draft.tint) else { return SpaceTheme(points: [.center]) }
                let hue = SpaceTheme(accentHex: draft.tint).points[0].hue
                let strength = (draft.tintStrength - range.lowerBound) / (range.upperBound - range.lowerBound)
                return SpaceTheme(points: [SpaceTheme.Point(hue: hue, saturation: max(strength, 0.08))])
            },
            set: { theme in
                let point = theme.points[0]
                // A dot let go near the middle means no color at all.
                guard point.saturation > 0.06 else { draft.tint = ""; return }
                draft.tint = SpaceTheme.accentColor(SpaceTheme.Point(hue: point.hue, saturation: 1)).hex
                draft.tintStrength = range.lowerBound + (range.upperBound - range.lowerBound) * point.saturation
            })
    }

    private var hasColorChanges: Bool {
        !draft.tint.isEmpty || draft.darkPage || draft.brightness != 1 || draft.contrast != 1
    }

    /// Arc's three keys under the pad: dark page, light adjustments, clear colors.
    private var colorTiles: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            tile(draft.darkPage ? "lightbulb.fill" : "lightbulb", "Dark page", isOn: draft.darkPage) { draft.darkPage.toggle() }
            tile("slider.horizontal.3", "Brightness and contrast", isOn: showingAdjust || draft.brightness != 1 || draft.contrast != 1) {
                showingAdjust.toggle()
            }
            tile("nosign", "Clear colors", isOn: false, enabled: hasColorChanges) {
                draft.tint = ""; draft.darkPage = false; draft.brightness = 1; draft.contrast = 1
            }
        }
    }

    private var adjustments: some View {
        VStack(spacing: NookDesign.Spacing.sm) {
            slider("sun.max", "Brightness", $draft.brightness, Boost.brightnessRange, percent: true)
            slider("circle.lefthalf.filled", "Contrast", $draft.contrast, Boost.contrastRange, percent: true)
        }
        .padding(NookDesign.Spacing.md)
        .background(NookDesign.Surface.fill, in: NookDesign.Radius.shape(NookDesign.Radius.lg))
    }

    private func tile(_ symbol: String, _ help: String, isOn: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(enabled ? .primary : .tertiary)
                .font(.system(size: NookDesign.Size.spaceIcon + 2, weight: .regular))
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity)
                .frame(height: tileHeight)
                .background(isOn ? NookDesign.Surface.fillPressed : NookDesign.Surface.fill,
                            in: NookDesign.Radius.shape(NookDesign.Radius.lg))
                .contentShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
        }
        .buttonStyle(BoostPress())
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Font

    /// `css` is the font-family written to the page. Each tile draws its own specimen so the
    /// choice can be made by eye; a face the Mac lacks falls back and looks like the system font.
    private struct FontChoice: Identifiable {
        let label: String
        let css: String
        var id: String { css }
    }

    private static let fonts: [FontChoice] = [
        FontChoice(label: "Site font", css: ""),
        FontChoice(label: "System", css: "-apple-system"),
        FontChoice(label: "Helvetica Neue", css: "Helvetica Neue"), FontChoice(label: "Avenir Next", css: "Avenir Next"),
        FontChoice(label: "Optima", css: "Optima"), FontChoice(label: "Futura", css: "Futura"),
        FontChoice(label: "Gill Sans", css: "Gill Sans"), FontChoice(label: "Verdana", css: "Verdana"),
        FontChoice(label: "Trebuchet MS", css: "Trebuchet MS"), FontChoice(label: "Georgia", css: "Georgia"),
        FontChoice(label: "Palatino", css: "Palatino"), FontChoice(label: "Charter", css: "Charter"),
        FontChoice(label: "Baskerville", css: "Baskerville"), FontChoice(label: "Hoefler Text", css: "Hoefler Text"),
        FontChoice(label: "Didot", css: "Didot"), FontChoice(label: "Times New Roman", css: "Times New Roman"),
        FontChoice(label: "Rockwell", css: "Rockwell"), FontChoice(label: "American Typewriter", css: "American Typewriter"),
        FontChoice(label: "Menlo", css: "Menlo"), FontChoice(label: "Courier New", css: "Courier New"),
    ]

    private func specimen(_ choice: FontChoice) -> Font {
        choice.css == "-apple-system" ? .system(size: 20) : .custom(choice.css, size: 20)
    }

    /// Arc's type card: every face as an "Aa" in itself; the first keeps the site's own font.
    private var fontGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5), spacing: NookDesign.Spacing.xs) {
            ForEach(Self.fonts) { choice in
                let selected = draft.fontFamily == choice.css
                Button { draft.fontFamily = choice.css } label: {
                    Group {
                        if choice.css.isEmpty {
                            Image(systemName: "nosign").font(NookDesign.Font.body)
                        } else {
                            Text("Aa").font(specimen(choice))
                        }
                    }
                    .foregroundStyle(selected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: tileHeight - NookDesign.Spacing.xs)
                    .background(selected ? NookDesign.Surface.selection : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.md))
                    .contentShape(Rectangle())
                }
                .buttonStyle(BoostPress())
                .help(choice.label)
                .accessibilityLabel(choice.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(NookDesign.Spacing.sm)
        .background(NookDesign.Surface.previewCard, in: NookDesign.Radius.shape(NookDesign.Radius.lg))
        .nookElevation(.raised)
    }

    // MARK: - Size and case

    private static let sizes: [Double] = [1, 1.1, 1.25, 1.5, 0.9]
    private static let cases: [Boost.TextCase] = [.none, .uppercase, .lowercase, .capitalize]

    /// Each press steps to the next size, as Arc's does; the value shows beside the word.
    private var sizeButton: some View {
        let next = Self.sizes.first { $0 > draft.fontScale + 0.001 } ?? Self.sizes.last!
        return wideButton("Size", value: draft.fontScale == 1 ? nil : "\(Int((draft.fontScale * 100).rounded()))%") {
            draft.fontScale = draft.fontScale >= Self.sizes[3] ? Self.sizes[4] : (draft.fontScale < 1 ? 1 : next)
        }
    }

    private var caseButton: some View {
        let index = Self.cases.firstIndex(of: draft.textCase) ?? 0
        let label: String? = switch draft.textCase {
        case .none: nil
        case .uppercase: "AB"
        case .lowercase: "ab"
        case .capitalize: "Ab"
        }
        return wideButton("Case", value: label) { draft.textCase = Self.cases[(index + 1) % Self.cases.count] }
    }

    private func wideButton(_ title: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: NookDesign.Spacing.xs) {
                Text(title).font(NookDesign.Font.title)
                if let value { Text(value).font(NookDesign.Font.body).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
            .background(NookDesign.Surface.fill, in: NookDesign.Radius.shape(NookDesign.Radius.lg))
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
        }
        .buttonStyle(BoostPress())
    }

    // MARK: - Code

    private var codeTab: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.sm) {
            sectionTitle("CSS")
            editor($draft.css, limit: Boost.maxCSSBytes)

            sectionTitle("Script")
            Toggle("Run this script on the site", isOn: $draft.scriptEnabled)
                .disabled(draft.script.isEmpty)
            editor($draft.script, limit: Boost.maxScriptBytes)
                .onChange(of: draft.script) { _, new in if new.isEmpty { draft.scriptEnabled = false } }
            Text("A script runs on the main page after it loads, apart from the page's own scripts. It can still change the page and what you see on logged-in sites, so run only code you trust. Scripts start on the next load once saved. Off by default.")
                .font(NookDesign.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func editor(_ text: Binding<String>, limit: Int) -> some View {
        TextEditor(text: text)
            .font(.system(.caption, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(NookDesign.Spacing.xs)
            .frame(height: 120)
            .background(NookDesign.Surface.fill, in: NookDesign.Radius.shape(NookDesign.Radius.md))
            .onChange(of: text.wrappedValue) { _, new in
                if new.utf8.count > limit { text.wrappedValue = String(new.prefix(limit)) }
            }
    }

    // MARK: - Zap and code

    private static let zapRule = " { display: none !important; }"

    /// How many elements Zap has hidden on this site.
    private var zapCount: Int { draft.zaps.count + draft.css.components(separatedBy: Self.zapRule).count - 1 }

    private var zapRow: some View {
        rowButton(zapping ? "Click an element" : "Zap", trailing: zapping ? "esc" : "\(zapCount)") {
            zapping ? cancelZap() : startZap()
        }
        .contextMenu {
            Button("Undo Last Zap") {
                if let lastZap, let i = draft.zaps.lastIndex(of: lastZap) { draft.zaps.remove(at: i) }
                lastZap = nil
            }
            .disabled(lastZap == nil)
        }
    }

    private var codeRow: some View {
        rowButton("Code", trailing: "{}") { showingCode.toggle() }
    }

    private func rowButton(_ title: String, trailing: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(NookDesign.Font.title)
                Spacer()
                Text(trailing).font(NookDesign.Font.title).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, NookDesign.Spacing.lg)
            .frame(height: tileHeight)
            .background(NookDesign.Surface.fill, in: NookDesign.Radius.shape(NookDesign.Radius.lg))
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
        }
        .buttonStyle(BoostPress())
    }

    // MARK: - Library

    /// Every Boost on every site. Switches and deletes here take effect at once, since this is
    /// managing the collection, not editing one Boost.
    private var library: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.md) {
            HStack {
                Button { showingLibrary = false } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                Spacer()
                Text("All Boosts").font(NookDesign.Font.body)
                Spacer()
                Button(action: requestClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Close Boost panel")
            }
            if settings.boosts.isEmpty {
                Text("No Boosts yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: NookDesign.Spacing.xs) {
                        ForEach(settings.boosts) { boost in
                            libraryRow(boost)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
            HStack {
                Button("Import…") { importing = true }
                Button("Export…") { exporting = true }.disabled(settings.boosts.isEmpty)
            }
            .controlSize(.small)
        }
    }

    private func libraryRow(_ boost: Boost) -> some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            Toggle("Boost on", isOn: Binding(
                get: { boost.isEnabled },
                set: { on in
                    if let i = settings.boosts.firstIndex(where: { $0.id == boost.id }) { settings.boosts[i].isEnabled = on }
                    if boost.id == draft.id { draft.isEnabled = on; baseline.isEnabled = on }
                }
            ))
            .toggleStyle(.switch).controlSize(.mini).labelsHidden()

            Button {
                select(boost)
                showingLibrary = false
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(boost.name.isEmpty ? boost.host : boost.name).font(NookDesign.Font.label)
                    Text(boost.scriptEnabled ? "\(boost.host) · runs a script" : boost.host)
                        .font(NookDesign.Font.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                settings.boosts.removeAll { $0.id == boost.id }
                if boost.id == draft.id { select(Boost(name: "Boost 1", host: host)) }
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(boost.name.isEmpty ? boost.host : boost.name)")
        }
        .padding(NookDesign.Spacing.sm)
        .background(NookDesign.Surface.fill, in: NookDesign.Radius.shape(NookDesign.Radius.md))
    }

    // MARK: - Actions

    private func select(_ boost: Boost) {
        if isDirty { save() }
        draft = boost
        baseline = boost
        lastZap = nil
        onPreview(boost)
    }

    private func save() {
        // Edits made before the file loads would be overwritten by the load.
        guard settings.boostsLoaded else { return }
        var boost = draft
        boost.updated = Date()
        let cleaned = Boost.removingBaitRules(boost.css)
        if cleaned != boost.css {
            boost.css = cleaned
            baitWarning = true
        }
        if let i = settings.boosts.firstIndex(where: { $0.id == boost.id }) {
            settings.boosts[i] = boost
        } else if settings.boosts.count < Boost.maxCount {
            settings.boosts.append(boost)
        }
        draft = boost
        baseline = boost
        lastZap = nil
    }

    private func delete() {
        settings.boosts.removeAll { $0.id == draft.id }
        if let next = siblings.first { select(next) } else { onFinish() }
    }

    private func requestClose() {
        if isDirty { save() }
        onFinish()
    }

    private func startZap() {
        zapping = true
        Task {
            let selector = await onZap()
            zapping = false
            guard let selector else { return }
            // Hides it on this site from now on once saved; "Undo last Zap" takes it back. A selector
            // Nook refuses (YouTube's ad-block bait) is dropped.
            guard Boost.isAllowedZap(selector), !draft.zaps.contains(selector), draft.zaps.count < 200 else { return }
            draft.zaps.append(selector)
            lastZap = selector
        }
    }

    private func cancelZap() {
        onCancelZap()
        zapping = false
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(NookDesign.Font.captionStrong).foregroundStyle(.secondary)
    }

    private func slider(_ icon: String, _ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, percent: Bool) -> some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Slider(value: value, in: range).accessibilityLabel(title)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .font(NookDesign.Font.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// Arc's keys press in a little.
private struct BoostPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(NookDesign.Motion.quick, value: configuration.isPressed)
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

private struct BoostFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
