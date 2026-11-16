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
#if canImport(NookWeb)
import NookWeb
#endif

/// How much a model is given: characters of each page, and how many pages.
struct LookupBudget: Sendable {
    let pageCharacters: Int
    let pages: Int
}

enum LookupModelError: Error {
    case unavailable
    case badReply
}

protocol LookupModel: Sendable {
    var budget: LookupBudget { get }

    /// The searches to run and the kind of request.
    func plan(for request: String) async throws -> LookupPlan

    /// What one page states that bears on the request, as short bullet lines, or NONE.
    func notes(on text: String, title: String, request: String, search: String) async throws -> String

    /// The page's answer, written from numbered notes only. `smaller` asks for a shape that fits
    /// when the full one was cut off.
    func answer(request: String, kind: LookupKind, notes: [String], smaller: Bool) async throws -> LookupAnswer

    /// The party size, day and time a booking request names.
    func booking(in request: String, today: Date) async throws -> BookingDetails

    /// One line saying what a place is, from its own page.
    func about(_ text: String, title: String) async throws -> String
}
