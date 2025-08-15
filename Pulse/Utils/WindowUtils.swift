//
//  WindowUtils.swift
//  Pulse
//
//  Created by Maciek Bagiński on 31/07/2025.
//
import SwiftUI
import Foundation
import AppKit

func zoomCurrentWindow() {
    if let window = NSApp.keyWindow {
        window.zoom(nil)
    }
}
