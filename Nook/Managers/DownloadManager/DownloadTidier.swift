// Licensed under GPL-3.0. See LICENSE.
//
//  DownloadTidier.swift
//  Nook
//
//  Tidy Downloads: a finished download with a name like 387494876.pdf or kovalam-bed.webp.jpeg
//  is renamed on this Mac's language model from the page it came from, or by rule without it.
//  The rules are in `DownloadTidyName`.
//

import Foundation
import FoundationModels

enum DownloadTidier {
    static var isAvailable: Bool { TabOrganizationModel.isAvailable }

    /// A tidier file name for `filename`, or nil to keep it. The model names it when Apple
    /// Intelligence is on; otherwise, or when the model gives nothing usable, the rules do.
    static func proposedName(for filename: String, pageTitle: String?, sourceURL: URL) async -> String? {
        guard DownloadTidyName.needsTidying(filename) else { return nil }
        if #available(macOS 26, *), isAvailable,
           let name = await propose(filename: filename, pageTitle: pageTitle, sourceURL: sourceURL) {
            return name
        }
        return DownloadTidyName.ruleBased(filename)
    }

    @available(macOS 26, *)
    @Generable
    struct Proposal {
        @Guide(description: "A short file name of two to six plain lowercase words, without an extension. Say what the file is, such as 'navan itinerary' or 'acme invoice october'. Keep version numbers.")
        var name: String
    }

    @available(macOS 26, *)
    private static func propose(filename: String, pageTitle: String?, sourceURL: URL) async -> String? {
        let session = LanguageModelSession(
            model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
            instructions: "You name downloaded files. Use only the facts given. Never invent dates, people or numbers that are not in them.")
        let prompt = """
        File name: \(filename)
        Downloaded from: \(sourceURL.host ?? sourceURL.absoluteString)
        Page title: \(pageTitle ?? "unknown")
        """
        do {
            let response = try await session.respond(
                to: prompt, generating: Proposal.self,
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 40))
            return DownloadTidyName.cleaned(response.content.name.lowercased(), replacing: filename)
        } catch {
            return nil
        }
    }
}
