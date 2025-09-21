//
//  GradientNode.swift
//  Nook
//
//  Created by Jonathan Caudill on 28/08/2025.
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
    // Visual positions on the canvas (0.0 to 1.0)
    var xPosition: Double?
    var yPosition: Double?

    init(id: UUID = UUID(), colorHex: String, location: Double, xPosition: Double? = nil, yPosition: Double? = nil) {
        self.id = id
        self.colorHex = colorHex
        // Clamp location to [0, 1]
        self.location = max(0.0, min(1.0, location))
        self.xPosition = xPosition
        self.yPosition = yPosition
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
