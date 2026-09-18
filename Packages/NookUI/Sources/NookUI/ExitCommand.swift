// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  ExitCommand.swift
//  NookUI
//
//  Escape cancels an inline rename on macOS. SwiftUI's onExitCommand does not exist on iOS,
//  where the software keyboard has no such key and losing focus commits or cancels instead.
//

import SwiftUI

extension View {
    @ViewBuilder
    func onEscapeKey(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }
}
