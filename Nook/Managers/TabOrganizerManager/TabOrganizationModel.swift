// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  TabOrganizationModel.swift
//  Nook
//
//  Tab grouping and renaming on the system language model (Apple Intelligence).
//  Every response is schema-constrained, so there is no output parsing.
//

import Foundation
import FoundationModels

// MARK: - TabOrganizationModel

enum TabOrganizationModel {

    /// Titles at or under this length are left alone.
    static let cleanTitleLength = 30

    private static let unrelated = "Unrelated"
    private static let maxFolderNameLength = 40
    private static let maxTitleLength = 60

    /// Most tabs one run takes. A run holds the tab list, a topic and a folder per tab in one
    /// session, which at 60 tabs does not fit the 4096-token context of macOS 26.
    static var maxTabs: Int { model.contextSize >= 8192 ? 60 : 40 }

    /// Observable: views reading this update when Apple Intelligence is turned on or off.
    static var isAvailable: Bool { model.isAvailable }

    /// Why the feature is hidden, for Settings; nil when the model is usable.
    static var unavailableNote: String? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(.modelNotReady):
            return "Tab Organizer will be available once Apple Intelligence finishes setting up."
        case .unavailable(.deviceNotEligible):
            return "Tab Organizer needs a Mac that supports Apple Intelligence."
        case .unavailable:
            return "Tab Organizer needs Apple Intelligence. Turn it on in System Settings > Apple Intelligence & Siri."
        }
    }

    private static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    /// Greedy decoding (temperature 0 alone still varied run to run), with a response cap sized to the entry count as a backstop against a runaway.
    private static func options(for entries: Int) -> GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 300 + entries * 40)
    }

    // MARK: - Grouping

    /// Groups the loose tabs on their own, then folds the result into existing folders. Existing
    /// folders stay out of the grouping turns: offered there, they used up the folder budget and
    /// pulled unrelated tabs in.
    static func groups(for inputs: [TabInput], existingFolders: [ExistingFolder]) async throws -> [TabOrganizationPlan.Group] {
        guard !inputs.isEmpty else { return [] }
        let session = LanguageModelSession(model: model, instructions: """
            You organize browser tabs into folders by the specific task or topic the person is working on, never by website. \
            Two tabs from one site often belong to different topics. Judge by the page title. \
            People keep several tabs open that relate to nothing else, such as mail, calendars, news, music and video. \
            Those tabs stay out of every folder.
            """)
        let proposed = try await proposeFolders(for: inputs, session: session)

        var folders: [(name: String, about: String)] = []
        for folder in proposed {
            let name = clean(folder.name, limit: maxFolderNameLength)
            guard !name.isEmpty, name.caseInsensitiveCompare(unrelated) != .orderedSame,
                  !folders.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            folders.append((name, clean(folder.about, limit: 120)))
        }

        var members: [String: [Int]] = [:]
        if !folders.isEmpty {
            let described = folders.map { "- \($0.name): \($0.about)" }.joined(separator: "\n")
            members = try await file(
                inputs, into: folders.map(\.name), session: session,
                prompt: """
                    Now file every tab. These are the folders:
                    \(described)
                    A tab goes in a folder only when its topic is that folder's topic. Every other tab is \(unrelated).
                    """
            )
        }
        var groups = folders.compactMap { folder -> TabOrganizationPlan.Group? in
            // A new folder for one tab is noise.
            guard let tabs = members[folder.name], tabs.count >= 2 else { return nil }
            return TabOrganizationPlan.Group(name: folder.name, existingFolderID: nil, tabs: tabs)
        }
        guard !existingFolders.isEmpty else { return groups }

        // A new group on an existing folder's topic goes into that folder.
        let abouts = Dictionary(uniqueKeysWithValues: folders.map { ($0.name, $0.about) })
        let covered = try await existingFolderNames(covering: groups.map { ($0.name, abouts[$0.name] ?? "") }, in: existingFolders)
        var merged: [TabOrganizationPlan.Group] = []
        for (group, name) in zip(groups, covered) {
            guard let existing = existingFolders.first(where: { $0.name == name }) else { merged.append(group); continue }
            if let index = merged.firstIndex(where: { $0.existingFolderID == existing.id }) {
                merged[index] = .init(name: existing.name, existingFolderID: existing.id, tabs: (merged[index].tabs + group.tabs).sorted())
            } else {
                merged.append(.init(name: existing.name, existingFolderID: existing.id, tabs: group.tabs))
            }
        }
        groups = merged

        // Tabs still loose get one chance at an existing folder; this is how a single new tab joins one.
        let grouped = Set(groups.flatMap(\.tabs))
        let leftover = inputs.filter { !grouped.contains($0.index) }
        guard !leftover.isEmpty else { return groups }
        let held = existingFolders.map { $0.sampleTitles.isEmpty ? "- \($0.name)" : "- \($0.name), holding: \($0.sampleTitles.joined(separator: "; "))" }
        let joined = try await file(
            leftover, into: existingFolders.map(\.name),
            session: LanguageModelSession(model: model, instructions: "You file browser tabs into existing folders by topic, never by website. Most tabs fit no folder."),
            prompt: """
                Folders:
                \(held.joined(separator: "\n"))
                Tabs:
                \(list(leftover))
                A tab goes in a folder only when its topic is that folder's topic. Every other tab is \(unrelated).
                """
        )
        for existing in existingFolders {
            guard let tabs = joined[existing.name], !tabs.isEmpty else { continue }
            if let index = groups.firstIndex(where: { $0.existingFolderID == existing.id }) {
                groups[index] = .init(name: existing.name, existingFolderID: existing.id, tabs: (groups[index].tabs + tabs).sorted())
            } else {
                groups.append(.init(name: existing.name, existingFolderID: existing.id, tabs: tabs))
            }
        }
        return groups
    }

    /// First turn: each tab's topic, then folder names with a sentence on what each holds. The topics
    /// come first so the model has read every tab before it names a folder. Both arrays are
    /// bounded: an unbounded one let the model run on until it overflowed the context.
    private static func proposeFolders(for inputs: [TabInput], session: LanguageModelSession) async throws -> [(name: String, about: String)] {
        let limit = max(3, inputs.count / 3)
        let folder = DynamicGenerationSchema(name: "ProposedFolder", properties: [
            .init(name: "name", description: "Title Case, 1 to 3 words, a specific task or topic, never a website name", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "about", description: "One short sentence saying what belongs in this folder", schema: DynamicGenerationSchema(type: String.self)),
        ])
        let root = DynamicGenerationSchema(name: "ProposedFolders", properties: [
            .init(
                name: "folders", description: "Folders for topics that at least 2 tabs share. Every shared topic gets a folder. No catch-all folders.",
                schema: DynamicGenerationSchema(arrayOf: folder, minimumElements: 0, maximumElements: limit)
            ),
        ])
        let content = try await session.respond(
            to: "Name the folders for these tabs. At most \(limit) folders.\nTabs:\n\(list(inputs))",
            schema: try GenerationSchema(root: root, dependencies: []), options: options(for: inputs.count)
        ).content
        return try content.value([GeneratedContent].self, forProperty: "folders").map {
            (try $0.value(String.self, forProperty: "name"), try $0.value(String.self, forProperty: "about"))
        }
    }

    /// One constrained entry per tab: its topic, then one of `names` or "Unrelated". The topic comes
    /// first so the model says what the page is before it chooses. Returns tab numbers by folder name.
    private static func file(_ inputs: [TabInput], into names: [String], session: LanguageModelSession, prompt: String) async throws -> [String: [Int]] {
        let entry = DynamicGenerationSchema(name: "Entry", properties: [
            .init(name: "tab", schema: DynamicGenerationSchema(type: Int.self)),
            .init(name: "topic", description: "What this page is about, 2 to 4 words", schema: DynamicGenerationSchema(type: String.self)),
            .init(
                name: "folder",
                description: "The folder about that same topic, or \(unrelated) when no folder is about it",
                schema: DynamicGenerationSchema(name: "Folder", anyOf: [unrelated] + names)
            ),
        ])
        let filed = try await session.respond(to: prompt, schema: try entries(of: entry, count: inputs.count), options: options(for: inputs.count)).content
        let valid = Set(inputs.map(\.index))
        var seen = Set<Int>()
        var members: [String: [Int]] = [:]
        for item in try filed.value([GeneratedContent].self, forProperty: "entries") {
            let tab = try item.value(Int.self, forProperty: "tab")
            guard valid.contains(tab), seen.insert(tab).inserted else { continue }
            members[try item.value(String.self, forProperty: "folder"), default: []].append(tab)
        }
        members[unrelated] = nil
        return members.mapValues { $0.sorted() }
    }

    /// For each new group, the existing folder that already covers its topic, or nil.
    private static func existingFolderNames(covering groups: [(name: String, about: String)], in existing: [ExistingFolder]) async throws -> [String?] {
        guard !groups.isEmpty else { return [] }
        let new = "New"
        let entry = DynamicGenerationSchema(name: "Match", properties: [
            .init(name: "folder", schema: DynamicGenerationSchema(type: Int.self)),
            .init(
                name: "sameAs",
                description: "The existing folder about the same topic, or \(new) when none is. A related topic is not the same topic.",
                schema: DynamicGenerationSchema(name: "Existing", anyOf: [new] + existing.map(\.name))
            ),
        ])
        let session = LanguageModelSession(model: model, instructions: "You compare browser tab folders by topic. Most new folders match no existing folder.")
        let lines = groups.enumerated().map { "\($0.offset + 1). \($0.element.name): \($0.element.about)" }
        let held = existing.map { $0.sampleTitles.isEmpty ? "- \($0.name)" : "- \($0.name), holding: \($0.sampleTitles.joined(separator: "; "))" }
        let matched = try await session.respond(
            to: "Existing folders:\n\(held.joined(separator: "\n"))\nNew folders:\n\(lines.joined(separator: "\n"))",
            schema: try entries(of: entry, count: groups.count), options: options(for: groups.count)
        ).content
        var result = [String?](repeating: nil, count: groups.count)
        for item in try matched.value([GeneratedContent].self, forProperty: "entries") {
            let index = try item.value(Int.self, forProperty: "folder") - 1
            let name = try item.value(String.self, forProperty: "sameAs")
            if result.indices.contains(index), name != new { result[index] = name }
        }
        return result
    }

    // MARK: - Renaming

    /// Short sidebar titles for the given tabs. Pass only tabs whose titles need it.
    static func renames(for all: [TabInput]) async throws -> [TabOrganizationPlan.Rename] {
        // A site's front page is named after the site; the model strips site names, so it never sees these.
        let sites = all.compactMap { input in siteTitle(for: input).map { TabOrganizationPlan.Rename(tab: input.index, name: $0) } }
        let inputs = all.filter { input in !sites.contains { $0.tab == input.index } }
        guard !inputs.isEmpty else { return sites }
        let session = LanguageModelSession(
            model: model,
            instructions: "You shorten browser tab titles so they fit a narrow sidebar."
        )
        let entry = DynamicGenerationSchema(name: "TitleEntry", properties: [
            .init(name: "tab", schema: DynamicGenerationSchema(type: Int.self)),
            .init(
                name: "title",
                description: "A short clean title, at most 5 words, built from words already in the title. Remove the site name, separators, counts and marketing words. Keep the words that identify the page.",
                schema: DynamicGenerationSchema(type: String.self)
            ),
        ])
        let titled = try await session.respond(
            to: "Shorten each title.\n\(list(inputs))",
            schema: try entries(of: entry, count: inputs.count), options: options(for: inputs.count)
        ).content

        let originals = Dictionary(uniqueKeysWithValues: inputs.map { ($0.index, $0.title) })
        var seen = Set<Int>()
        return try sites + titled.value([GeneratedContent].self, forProperty: "entries").compactMap { item in
            let tab = try item.value(Int.self, forProperty: "tab")
            let title = clean(try item.value(String.self, forProperty: "title"), limit: maxTitleLength)
            guard let original = originals[tab], seen.insert(tab).inserted,
                  !title.isEmpty, title.count < original.count else { return nil }
            return TabOrganizationPlan.Rename(tab: tab, name: title)
        }
    }

    /// For a front page or a top-level section ("bbc.com/news"), the part of the title that names
    /// the site: "BBC News - Breaking news, video…" gives "BBC News". Nil for deeper pages.
    /// ponytail: matches on host labels, so "bbc.co.uk" works through "bbc" but a site whose name
    /// differs from its domain gets no site title and keeps its full one.
    static func siteTitle(for input: TabInput) -> String? {
        guard input.url.pathComponents.filter({ $0 != "/" }).count <= 1, let host = input.url.host?.lowercased() else { return nil }
        let labels = host.split(separator: ".").dropLast().filter { $0.count > 2 && $0 != "www" }
        var segments = [input.title]
        for separator in [" | ", " - ", " — ", " – ", ": ", " · "] {
            segments = segments.flatMap { $0.components(separatedBy: separator) }
        }
        let match = segments.first { segment in
            let flat = segment.lowercased().filter { $0.isLetter || $0.isNumber }
            return labels.contains { flat.contains($0) }
        }?.trimmingCharacters(in: .whitespaces)
        guard let match, !match.isEmpty, match.count < input.title.count else { return nil }
        return match
    }

    // MARK: - Private

    /// `{"entries": [entry × count]}`, one per tab, so the model can neither skip nor repeat a tab.
    private static func entries(of entry: DynamicGenerationSchema, count: Int) throws -> GenerationSchema {
        let root = DynamicGenerationSchema(name: "Entries", properties: [
            .init(
                name: "entries",
                description: "One entry per tab, in list order",
                schema: DynamicGenerationSchema(arrayOf: entry, minimumElements: count, maximumElements: count)
            ),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func list(_ inputs: [TabInput]) -> String {
        inputs.map { "\($0.index). \(clean($0.title, limit: 80)) | \(shortURL($0.url))" }.joined(separator: "\n")
    }

    private static func clean(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(limit))
    }

    /// Host plus the start of the path. Queries and long paths cost tokens and say little about topic.
    private static func shortURL(_ url: URL) -> String {
        var host = url.host ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return url.path.count > 1 ? host + url.path.prefix(40) : host
    }
}
