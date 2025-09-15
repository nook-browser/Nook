//
//  GradientNode.swift
//  Nook
//
//  Created by Codex on 28/08/2025.
//

import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Gradient Node Model

struct GradientNode: Identifiable, Codable, Hashable {
    let id: UUID
    var colorHex: String
    var location: Double

    init(id: UUID = UUID(), colorHex: String, location: Double) {
        self.id = id
        self.colorHex = colorHex
        // Clamp location to [0, 1]
        self.location = max(0.0, min(1.0, location))
    }

    init(id: UUID = UUID(), color: Color, location: Double) {
        #if canImport(AppKit)
        let hex = NSColor(color).toHexString() ?? "#000000"
        #else
        let hex = "#000000"
        #endif
        self.init(id: id, colorHex: hex, location: location)
    }
}
