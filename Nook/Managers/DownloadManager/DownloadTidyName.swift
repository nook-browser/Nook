// Licensed under GPL-3.0. See LICENSE.
//
//  DownloadTidyName.swift
//  Nook
//
//  Tidy Downloads' rules, Foundation only so `scripts/tests/DownloadTidyNameCheck.swift` can
//  compile them: which names are worth renaming, and what a proposed name may look like.
//

import Foundation

enum DownloadTidyName {
    static let maxLength = 60

    /// Words that name nothing: a file called one of these says nothing about its contents.
    private static let genericStems: Set<String> = [
        "download", "file", "document", "untitled", "image", "img", "photo", "export", "attachment", "report",
    ]

    /// Image and document extensions a site leaves inside a name, as in `photo.webp.jpeg`.
    private static let innerExtensions: Set<String> = ["webp", "jpg", "jpeg", "png", "gif", "avif", "heic", "pdf", "html", "htm"]

    /// Whether `filename` reads as something a person would have typed. Anything else gets
    /// tidied: ids, hashes, timestamps, generic words, slugs (`kovalam-tropical-bed`), names
    /// with no spaces at all, and doubled extensions.
    static func needsTidying(_ filename: String) -> Bool {
        let stem = (filename as NSString).deletingPathExtension
        if innerExtensions.contains((stem as NSString).pathExtension.lowercased()) { return true }
        if looksMessy(filename) { return true }
        // A slug: words joined by dashes, underscores or dots, never a space.
        return !stem.contains(" ") && stem.range(of: #"[-_.]"#, options: .regularExpression) != nil
    }

    /// Whether `filename` is an id, a hash, a timestamp, digits or a generic word.
    static func looksMessy(_ filename: String) -> Bool {
        let stem = (filename as NSString).deletingPathExtension
        let lowered = stem.lowercased()
        guard !lowered.isEmpty else { return true }
        if genericStems.contains(lowered.trimmingCharacters(in: .decimalDigits.union(.punctuationCharacters).union(.whitespaces))) {
            return true
        }
        // A run of six digits or eight hex characters: an id, a hash or a timestamp.
        if lowered.range(of: #"[0-9]{6,}|[0-9a-f]{8,}"#, options: .regularExpression) != nil { return true }
        let letters = lowered.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letters < 3 || Double(letters) / Double(lowered.unicodeScalars.count) < 0.3
    }

    /// The name without the model: separators to spaces, ids and doubled extensions out, all
    /// lowercase as Arc writes them. Nil when no words are left, so `387494876.pdf` keeps its name.
    static func ruleBased(_ filename: String) -> String? {
        var stem = (filename as NSString).deletingPathExtension
        if innerExtensions.contains((stem as NSString).pathExtension.lowercased()) {
            stem = (stem as NSString).deletingPathExtension
        }
        stem = stem.replacingOccurrences(of: #"[-_.+]+"#, with: " ", options: .regularExpression)
        // Ids, hashes and timestamps say nothing a person reads.
        stem = stem.replacingOccurrences(of: #"\b(?:[0-9]{6,}|[0-9a-fA-F]{8,})\b"#, with: " ", options: .regularExpression)
        // Arc's style: plain lowercase words.
        let proposal = stem.split(separator: " ").joined(separator: " ").lowercased()
        guard proposal.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 3,
              !genericStems.contains(proposal.lowercased()) else { return nil }
        return cleaned(proposal, replacing: filename)
    }

    /// The model's proposal made safe: one line, no path separators or extension, at most
    /// `maxLength` characters. Nil when nothing usable is left or it only repeats the old name.
    static func cleaned(_ proposal: String, replacing original: String) -> String? {
        var stem = proposal
            .components(separatedBy: .newlines).first ?? ""
        stem = stem.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'`.")))
        // The model sometimes adds an extension; the original's is what the file really is.
        let ext = (stem as NSString).pathExtension
        if !ext.isEmpty, ext.count <= 5, !ext.contains(" ") { stem = (stem as NSString).deletingPathExtension }
        stem = stem.replacingOccurrences(of: #"[/:\\*?"<>|\x00]"#, with: " ", options: .regularExpression)
        // Leading dots would hide the file, and `..` is no name at all.
        stem = stem.replacingOccurrences(of: #"\.{2,}"#, with: " ", options: .regularExpression)
        stem = stem.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        if stem.count > maxLength {
            stem = String(stem.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        }
        guard stem.rangeOfCharacter(from: .letters) != nil else { return nil }
        let originalStem = (original as NSString).deletingPathExtension
        guard stem.caseInsensitiveCompare(originalStem) != .orderedSame else { return nil }
        let originalExt = (original as NSString).pathExtension
        return originalExt.isEmpty ? stem : stem + "." + originalExt
    }
}
