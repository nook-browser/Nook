// Licensed under GPL-3.0. See LICENSE.
//
//  DownloadTidier.swift
//  Nook
//
//  Tidy Downloads' gate and name guard, Foundation only so
//  `scripts/tests/DownloadTidyGateCheck.swift` can compile them. The model call is in
//  `DownloadTidier+Model.swift`.
//

import Foundation

enum DownloadTidier {
    static let maxLength = 60

    /// Where the bytes came from: a network download, or a file Nook wrote itself (capture, Save PDF).
    enum Origin { case network, capture }

    /// Only a network download going to the Downloads folder on its own, outside private
    /// windows and the Agent space. A name typed in the save panel is never touched.
    static func shouldTidy(isAutomaticFolder: Bool, isPrivate: Bool, origin: Origin) -> Bool {
        isAutomaticFolder && !isPrivate && origin == .network
    }

    /// Whether a name looks machine-made enough to ask the model: a hash or ID, a long run of
    /// digits, a generic word, or a copy counter. A readable name never waits on the model.
    static func isMessy(_ filename: String) -> Bool {
        let ext = fileExtension(of: filename)
        let stem = ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1))
        let lower = stem.lowercased().trimmingCharacters(in: .whitespaces)
        let generic: Set<String> = ["download", "file", "image", "img", "document", "doc", "untitled", "unnamed", "export", "attachment", "media", "video", "photo", "scan", "output"]
        let patterns = [
            #"[0-9a-f]{8,}"#,                                   // hash or hex ID
            #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}"#,            // UUID
            #"\d{6,}"#,                                         // timestamp or long number
            #"\s?\(\d+\)$"#,                                    // "name (1)"
            #"^(img|dsc|pxl|screenshot|image|file|download)[_\-\s]?\d+"#,
        ]
        if generic.contains(lower) { return true }
        return patterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    /// The model's proposal as a file name keeping `original`'s extension, or nil to keep the
    /// original. Arc's guard: an empty or dot-prefixed name is refused outright.
    static func acceptedName(_ proposal: String, replacing original: String) -> String? {
        var stem = (proposal.components(separatedBy: .newlines).first ?? "")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'`")))
        stem = stem.replacingOccurrences(of: #"[/:\\\x00]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !stem.isEmpty, !stem.hasPrefix(".") else { return nil }

        let ext = fileExtension(of: original)
        if !ext.isEmpty, stem.lowercased().hasSuffix("." + ext.lowercased()) {
            stem = String(stem.dropLast(ext.count + 1))
        }
        // Never give a file an extension it did not have.
        if ext.isEmpty { stem = stem.replacingOccurrences(of: #"\.\w{1,5}$"#, with: "", options: .regularExpression) }
        stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if stem.count > maxLength { stem = String(stem.prefix(maxLength)).trimmingCharacters(in: .whitespaces) }
        guard stem.rangeOfCharacter(from: .letters) != nil, !stem.hasPrefix(".") else { return nil }

        let name = ext.isEmpty ? stem : stem + "." + ext
        return name.caseInsensitiveCompare(original) == .orderedSame ? nil : name
    }

    /// `gz` for `a.gz`, `tar.gz` for `backup.tar.gz`.
    private static func fileExtension(of filename: String) -> String {
        let ns = filename as NSString
        let last = ns.pathExtension
        let inner = (ns.deletingPathExtension as NSString).pathExtension
        return inner.lowercased() == "tar" ? inner + "." + last : last
    }
}
