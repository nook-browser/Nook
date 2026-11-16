// Licensed under GPL-3.0. See LICENSE.
//
//  LookupJSON.swift
//  NookWeb
//
//  Reads the JSON object out of a connected model's reply, whatever prose or code fence it put
//  around it. Foundation only, so `Checks/LookupJSONCheck.swift` can compile it.
//

import Foundation

public enum LookupJSON {
    public enum Failure: Error { case noObject }

    /// The first complete top-level object in `reply`, decoded as `type`.
    public static func decoded<T: Decodable>(_ type: T.Type, from reply: String) throws -> T {
        guard let object = firstObject(in: reply) else { throw Failure.noObject }
        return try JSONDecoder().decode(type, from: Data(object.utf8))
    }

    /// From the first `{` to its matching `}`, skipping braces inside strings.
    static func firstObject(in text: String) -> Substring? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in text[start...].indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return text[start...index] }
            }
        }
        return nil
    }
}
