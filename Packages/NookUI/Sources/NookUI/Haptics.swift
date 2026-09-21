// Licensed under GPL-3.0. See LICENSE.
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

public enum Haptics {
    /// The small click the sidebar plays when a selection snaps into place.
    @MainActor public static func alignment() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
