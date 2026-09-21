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

// MARK: - Generated Types

@Generable
private struct ProposedFolders {
    @Guide(description: "Folders for tabs that share one specific task or topic. Only tasks that at least 2 tabs are clearly about. No catch-all folders.")
    var folders: [ProposedFolder]
}

@Generable
private struct ProposedFolder {
    @Guide(description: "Title Case, 1 to 3 words, a specific task or topic, never a website name")
    var name: String
    @Guide(description: "One short sentence saying what belongs in this folder")
    var about: String
}

// MARK: - TabOrganizationModel

enum TabOrganizationModel {

    /// Titles at or under this length are left alone.
    static let cleanTitleLength = 30

    private static let unrelated = "Unrelated"
    private static let maxFolderNameLength = 40
    private static let maxTitleLength = 60

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
    private static let options = GenerationOptions(temperature: 0)

    // MARK: - Grouping

    /// Two turns in one session: name the folders, then file every tab under one of those names
    /// or under "Unrelated". The second schema only permits those choices, one entry per tab.
    static func groups(for inputs: [TabInput], existingFolders: [ExistingFolder]) async throws -> [TabOrganizationPlan.Group] {
        guard !inputs.isEmpty else { return [] }
        let session = LanguageModelSession(model: model, instructions: """
            You organize browser tabs into folders by the specific task or topic the person is working on, never by website. \
            Two tabs from one site often belong to different topics. Judge by the page title. \
            People keep several tabs open that relate to nothing else, such as mail, calendars, news, music and video. \
            Those tabs stay out of every folder.
            """)

        var request = "Name the folders for these tabs. At most \(max(2, inputs.count / 4)) folders."
        if !existingFolders.isEmpty {
            let lines = existingFolders.map { folder in
                folder.sampleTitles.isEmpty ? "- \(folder.name)" : "- \(folder.name), holding: \(folder.sampleTitles.joined(separator: "; "))"
            }
            request += "\nThese folders already exist. Do not name a new folder for a topic one of them covers.\n"
                + lines.joined(separator: "\n")
        }
        let proposed = try await session.respond(
            to: "\(request)\nTabs:\n\(list(inputs))", generating: ProposedFolders.self, options: options
        ).content.folders

        // First name wins, so a proposal that repeats an existing folder files into that folder.
        var choices: [String] = []
        for name in existingFolders.map(\.name) + proposed.map({ clean($0.name, limit: maxFolderNameLength) })
        where !name.isEmpty && !choices.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
            && name.caseInsensitiveCompare(unrelated) != .orderedSame {
            choices.append(name)
        }
        guard !choices.isEmpty else { return [] }

        let entry = DynamicGenerationSchema(name: "Entry", properties: [
            .init(name: "tab", schema: DynamicGenerationSchema(type: Int.self)),
            .init(
                name: "folder",
                description: "The folder whose description fits this tab, or \(unrelated) when no description fits",
                schema: DynamicGenerationSchema(name: "Folder", anyOf: [unrelated] + choices)
            ),
        ])
        let filed = try await session.respond(
            to: "Now file every tab. Use \(unrelated) for a tab that fits no folder's description.",
            schema: try entries(of: entry, count: inputs.count), options: options
        ).content

        let valid = Set(inputs.map(\.index))
        var seen = Set<Int>()
        var members: [String: [Int]] = [:]
        for item in try filed.value([GeneratedContent].self, forProperty: "entries") {
            let tab = try item.value(Int.self, forProperty: "tab")
            guard valid.contains(tab), seen.insert(tab).inserted else { continue }
            members[try item.value(String.self, forProperty: "folder"), default: []].append(tab)
        }
        return choices.compactMap { name in
            let existing = existingFolders.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            let tabs = (members[name] ?? []).sorted()
            // A new folder for one tab is noise; an existing folder takes any number.
            guard tabs.count >= (existing == nil ? 2 : 1) else { return nil }
            return TabOrganizationPlan.Group(name: name, existingFolderID: existing?.id, tabs: tabs)
        }
    }

    // MARK: - Renaming

    /// Short sidebar titles for the given tabs. Pass only tabs whose titles need it.
    static func renames(for inputs: [TabInput]) async throws -> [TabOrganizationPlan.Rename] {
        guard !inputs.isEmpty else { return [] }
        let session = LanguageModelSession(
            model: model,
            instructions: "You shorten browser tab titles so they fit a narrow sidebar."
        )
        let entry = DynamicGenerationSchema(name: "TitleEntry", properties: [
            .init(name: "tab", schema: DynamicGenerationSchema(type: Int.self)),
            .init(
                name: "title",
                description: "A short clean title, at most 5 words. Remove the site name, separators, counts and marketing words. Keep the words that identify the page.",
                schema: DynamicGenerationSchema(type: String.self)
            ),
        ])
        let titled = try await session.respond(
            to: "Shorten each title.\n\(list(inputs))",
            schema: try entries(of: entry, count: inputs.count), options: options
        ).content

        let originals = Dictionary(uniqueKeysWithValues: inputs.map { ($0.index, $0.title) })
        var seen = Set<Int>()
        return try titled.value([GeneratedContent].self, forProperty: "entries").compactMap { item in
            let tab = try item.value(Int.self, forProperty: "tab")
            let title = clean(try item.value(String.self, forProperty: "title"), limit: maxTitleLength)
            guard let original = originals[tab], seen.insert(tab).inserted,
                  !title.isEmpty, title.count < original.count else { return nil }
            return TabOrganizationPlan.Rename(tab: tab, name: title)
        }
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
