//
//  TabOrganizationPlan.swift
//  Nook
//
//  Codable structs for parsed LLM output describing how to reorganize tabs.
//  Uses stored `id` properties for stable SwiftUI identity.
//  Includes a resilient parser with three fallback strategies.
//

import Foundation

// MARK: - TabOrganizationPlan

/// The decoded output of an LLM tab-organization response.
///
/// Integer values in `tabs`, `tab`, `keep`, `close`, and `sort` are 1-based indices
/// matching the prompt produced by ``TabOrganizationPrompt``.
struct TabOrganizationPlan: Codable {

    // MARK: - Group

    /// A named group of tab indices that should be filed together.
    struct Group: Codable, Identifiable {
        let id: UUID
        let name: String
        let tabs: [Int]

        private enum CodingKeys: String, CodingKey {
            case name, tabs
        }

        init(name: String, tabs: [Int]) {
            self.id = UUID()
            self.name = name
            self.tabs = tabs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = UUID()
            self.name = try container.decode(String.self, forKey: .name)
            self.tabs = try container.decode([Int].self, forKey: .tabs)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(tabs, forKey: .tabs)
        }
    }

    // MARK: - Rename

    /// A suggested rename for a single tab.
    struct Rename: Codable, Identifiable {
        let id: UUID
        let tab: Int
        let name: String

        private enum CodingKeys: String, CodingKey {
            case tab, name
        }

        init(tab: Int, name: String) {
            self.id = UUID()
            self.tab = tab
            self.name = name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = UUID()
            self.tab = try container.decode(Int.self, forKey: .tab)
            self.name = try container.decode(String.self, forKey: .name)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(tab, forKey: .tab)
            try container.encode(name, forKey: .name)
        }
    }

    // MARK: - DuplicateSet

    /// A set of duplicate tabs — one to keep, the rest to close.
    struct DuplicateSet: Codable, Identifiable {
        let id: UUID
        let keep: Int
        let close: [Int]

        private enum CodingKeys: String, CodingKey {
            case keep, close
        }

        init(keep: Int, close: [Int]) {
            self.id = UUID()
            self.keep = keep
            self.close = close
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = UUID()
            self.keep = try container.decode(Int.self, forKey: .keep)
            self.close = try container.decode([Int].self, forKey: .close)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(keep, forKey: .keep)
            try container.encode(close, forKey: .close)
        }
    }

    // MARK: - Properties

    let groups: [Group]
    let renames: [Rename]
    let sort: [Int]?
    let duplicates: [DuplicateSet]
}

// MARK: - ParseError

/// Errors produced by ``TabOrganizationPlanParser``.
enum TabOrganizationPlanParseError: LocalizedError {
    /// No JSON object could be found in the LLM output.
    case noJSON
    /// JSON was found but could not be decoded into a ``TabOrganizationPlan``.
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .noJSON:
            return "No JSON object found in model output."
        case .invalidJSON(let detail):
            return "Invalid JSON: \(detail)"
        }
    }
}

// MARK: - TabOrganizationPlanParser

/// Parses raw LLM text output into a validated ``TabOrganizationPlan``.
///
/// Attempts three strategies in order:
/// 1. Direct `JSONDecoder` decode of the entire string.
/// 2. Strip markdown code fences, then decode.
/// 3. Extract the first balanced `{...}` object, then decode.
///
/// After successful decode, indices outside `validRange` are removed
/// and empty groups are dropped.
enum TabOrganizationPlanParser {

    // MARK: - Public

    /// Parse LLM output into a validated plan.
    ///
    /// - Parameters:
    ///   - output: Raw text from the LLM.
    ///   - validRange: The closed range of valid 1-based tab indices (e.g. `1...20`).
    /// - Returns: A validated ``TabOrganizationPlan``.
    /// - Throws: ``TabOrganizationPlanParseError`` if no valid JSON can be extracted.
    static func parse(_ output: String, validRange: ClosedRange<Int>) throws -> TabOrganizationPlan {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strategy 1: direct decode
        if let plan = decode(trimmed) {
            return validate(plan, validRange: validRange)
        }

        // Strategy 2: strip markdown fences
        if let stripped = stripMarkdownFences(trimmed), let plan = decode(stripped) {
            return validate(plan, validRange: validRange)
        }

        // Strategy 3: extract first balanced JSON object
        if let extracted = extractFirstJSONObject(trimmed), let plan = decode(extracted) {
            return validate(plan, validRange: validRange)
        }

        throw TabOrganizationPlanParseError.noJSON
    }

    // MARK: - Decode

    private static func decode(_ string: String) -> TabOrganizationPlan? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TabOrganizationPlan.self, from: data)
    }

    // MARK: - Fence Stripping

    /// Strips ``` or ```json fences from around the content.
    private static func stripMarkdownFences(_ string: String) -> String? {
        // Match ```json ... ``` or ``` ... ```
        let pattern = #"```(?:json)?\s*\n?([\s\S]*?)\n?\s*```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                in: string,
                options: [],
                range: NSRange(string.startIndex..., in: string)
              ),
              let captureRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Balanced Extraction

    /// Finds the first balanced `{ ... }` substring in the input.
    private static func extractFirstJSONObject(_ string: String) -> String? {
        guard let startIndex = string.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escape = false

        for index in string[startIndex...].indices {
            let char = string[index]

            if escape {
                escape = false
                continue
            }

            if char == "\\" && inString {
                escape = true
                continue
            }

            if char == "\"" {
                inString.toggle()
                continue
            }

            guard !inString else { continue }

            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    let endIndex = string.index(after: index)
                    return String(string[startIndex..<endIndex])
                }
            }
        }

        return nil
    }

    // MARK: - Validation

    /// Remove out-of-range indices and drop empty groups.
    private static func validate(
        _ plan: TabOrganizationPlan,
        validRange: ClosedRange<Int>
    ) -> TabOrganizationPlan {
        let groups = plan.groups.compactMap { group -> TabOrganizationPlan.Group? in
            let filtered = group.tabs.filter { validRange.contains($0) }
            guard !filtered.isEmpty else { return nil }
            return TabOrganizationPlan.Group(name: group.name, tabs: filtered)
        }

        let renames = plan.renames.filter { validRange.contains($0.tab) }

        let sort = plan.sort?.filter { validRange.contains($0) }

        let duplicates = plan.duplicates.compactMap { dup -> TabOrganizationPlan.DuplicateSet? in
            guard validRange.contains(dup.keep) else { return nil }
            let filtered = dup.close.filter { validRange.contains($0) }
            guard !filtered.isEmpty else { return nil }
            return TabOrganizationPlan.DuplicateSet(keep: dup.keep, close: filtered)
        }

        return TabOrganizationPlan(
            groups: groups,
            renames: renames,
            sort: sort,
            duplicates: duplicates
        )
    }
}
