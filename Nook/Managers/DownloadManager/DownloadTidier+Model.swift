// Licensed under GPL-3.0. See LICENSE.
//
//  DownloadTidier+Model.swift
//  Nook
//
//  Names a download on this Mac's language model from the three things Arc uses: the file's
//  own name, the title of the page it came from, and the domain.
//

import Foundation
import FoundationModels

extension DownloadTidier {
    static var isAvailable: Bool { TabOrganizationModel.isAvailable }

    private static let timeout: Duration = .milliseconds(1500)

    /// A better file name, or nil to keep `filename`: the model is off, slow (1.5 s), or gave nothing usable.
    @MainActor
    static func proposedName(for filename: String, pageTitle: String?, domain: String?) async -> String? {
        guard #available(macOS 26, *), isAvailable else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = Once()
            let model = Task { @MainActor in
                let name = await propose(filename: filename, pageTitle: pageTitle, domain: domain)
                once.finish(name.flatMap { acceptedName($0, replacing: filename) }, continuation)
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.finish(nil, continuation)
                model.cancel()
            }
        }
    }

    @MainActor
    private final class Once {
        private var done = false
        func finish(_ value: String?, _ continuation: CheckedContinuation<String?, Never>) {
            guard !done else { return }
            done = true
            continuation.resume(returning: value)
        }
    }

    @available(macOS 26, *)
    @Generable
    struct Proposal {
        @Guide(description: "A short file name of two to six plain words, without an extension. Say what the file is, such as 'Navan itinerary' or 'Acme invoice October'. Keep version numbers.")
        var name: String
    }

    @available(macOS 26, *)
    private static func propose(filename: String, pageTitle: String?, domain: String?) async -> String? {
        let session = LanguageModelSession(
            model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
            instructions: "You name downloaded files. Use only the facts given. Never invent dates, people or numbers that are not in them.")
        let prompt = """
        File name: \(filename)
        Downloaded from: \(domain ?? "unknown")
        Page title: \(pageTitle ?? "unknown")
        """
        // Any failure, including macOS 27's LanguageModelError, means keep the original name.
        let response = try? await session.respond(
            to: prompt, generating: Proposal.self,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 40))
        return response?.content.name
    }
}
