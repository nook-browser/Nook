// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  Haptics.swift
//  NookUI
//
//  The one platform split in NookUI's own code: AppKit's alignment feedback has no
//  cross-platform spelling.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Haptics {
    /// The small click the sidebar plays when a selection snaps into place.
    @MainActor static func alignment() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
