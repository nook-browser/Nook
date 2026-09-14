//
//  SpaceAccent.swift
//  Nook
//
//  Preset accent colors for spaces. A space's accent is its gradient's
//  primary color; new spaces are written as a single-node gradient.
//

import Foundation

enum SpaceAccent {
    static let presets: [(name: String, hex: String)] = [
        ("Teal", "#3A8FA3"),
        ("Orange", "#D6603A"),
        ("Violet", "#6B5BD6"),
        ("Green", "#2F9E6A"),
        ("Red", "#D64545"),
        ("Blue", "#2F6FDB"),
        ("Pink", "#C94F8E"),
        ("Graphite", "#6E6E73"),
    ]

    static let defaultHex = presets[0].hex
}
