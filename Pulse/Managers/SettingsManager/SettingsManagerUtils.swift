//
//  Utils.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import AppKit
import Foundation

public let materials: [(name: String, value: NSVisualEffectView.Material)] = [
    ("titlebar", .titlebar),
    ("selection", .selection),
    ("menu", .menu),
    ("popover", .popover),
    ("sidebar", .sidebar),
    ("headerView", .headerView),
    ("sheet", .sheet),
    ("windowBackground", .windowBackground),
    ("Arc", .hudWindow),
    ("fullScreenUI", .fullScreenUI),
    ("toolTip", .toolTip),
    ("contentBackground", .contentBackground),
    ("underWindowBackground", .underWindowBackground),
    ("underPageBackground", .underPageBackground),
]

public func nameForMaterial(_ material: NSVisualEffectView.Material) -> String {
    materials.first(where: { $0.value == material })?.name
        ?? "raw(\(material.rawValue))"
}
