// Licensed under GPL-3.0. See LICENSE.
//
//  LookupModel.swift
//  Nook
//
//  What Look It Up asks of a language model, whichever one answers. NookWeb is imported only
//  when it exists, so `scripts/tests/LookupPipelineCheck.swift` and the scored eval compile
//  this file beside the package's sources.
//

import Foundation
import os
#if canImport(NookWeb)
import NookWeb
#endif

/// How much a model is given: characters of each page, and how many pages.
struct LookupBudget: Sendable {
    let pageCharacters: Int
    let pages: Int
    /// Characters of page text one answer call takes in all. Zero: the answer is written from notes.
    var answerCharacters = 0
}

enum LookupModelError: Error {
    case unavailable
    case badReply

    /// Matched by case name: macOS 27 throws `LanguageModelError`, macOS 26 `GenerationError`.
    static func isRefusal(_ error: Error) -> Bool {
        ["refusal", "guardrailViolation"].contains(Mirror(reflecting: error).children.first?.label ?? "")
    }
}

enum LookupStream {
    /// The last value `stream` reported before it ended, failed, or reported nothing new for
    /// `stall`. A stop and a `fatal` error are thrown; any other failure is returned beside the value.
    static func last<T: Equatable & Sendable>(
        stall: Duration, fatal: @escaping @Sendable (Error) -> Bool = { _ in false },
        _ stream: @escaping @Sendable (@escaping @Sendable (T) -> Void) async throws -> Void
    ) async throws -> (value: T?, failure: Error?, wentQuiet: Bool) {
        let state = OSAllocatedUnfairLock(initialState: (value: T?.none, at: ContinuousClock.Instant?.none, failure: (any Error)?.none))
        let wentQuiet = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await stream { value in
                        state.withLock { if $0.value != value { $0.value = value; $0.at = .now } }
                    }
                } catch where !(error is CancellationError) && !fatal(error) {
                    state.withLock { $0.failure = error }
                }
                return false
            }
            // The clock starts at the first value: until then the model is reading the prompt.
            group.addTask {
                while true {
                    try await Task.sleep(for: stall / 2)
                    if let at = state.withLock({ $0.at }), ContinuousClock.now - at > stall { return true }
                }
            }
            let quiet = try await group.next() ?? false
            group.cancelAll()
            return quiet
        }
        try Task.checkCancellation()
        return state.withLock { ($0.value, $0.failure, wentQuiet) }
    }
}

protocol LookupModel: Sendable {
    var budget: LookupBudget { get }

    /// The searches to run and the kind of request.
    func plan(for request: String) async throws -> LookupPlan

    /// What one page states that bears on the request, as short bullet lines, or NONE.
    func notes(on text: String, title: String, request: String, search: String) async throws -> String

    /// The page's answer, written from numbered notes only. With `fromPages` each note is a
    /// page's own text. `smaller` asks for a shape that fits when the full one was cut off.
    func answer(request: String, kind: LookupKind, notes: [String], fromPages: Bool, smaller: Bool) async throws -> LookupAnswer

    /// The party size, day and time a booking request names.
    func booking(in request: String, today: Date) async throws -> BookingDetails

    /// One line saying what a place is, from its own page.
    func about(_ text: String, title: String) async throws -> String
}
