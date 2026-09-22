// Licensed under GPL-3.0. See LICENSE.
//
//  ShortcutConflictToast.swift
//  Nook
//
//  Created by AI Assistant on 2025.
//
//  Toast notification shown when a keyboard shortcut conflicts between
//  Nook and a website. Informs users they can press again for Nook action.
//

import SwiftUI
import NookDesign

// MARK: - Shortcut Conflict Toast View

public struct ShortcutConflictToast: View {
    /// The shortcut as the user typed it, e.g. "⌘K".
    let shortcut: String
    let websiteName: String
    let nookActionName: String
    
    public init(
        shortcut: String,
        websiteName: String,
        nookActionName: String
    ) {
        self.shortcut = shortcut
        self.websiteName = websiteName
        self.nookActionName = nookActionName
    }

    public var body: some View {
        ToastView {
            HStack(spacing: 10) {
                // Keyboard icon
                Image(systemName: "keyboard")
                    .font(NookDesign.Font.body)
                    .foregroundStyle(.primary)
                    .frame(width: 18, height: 18)
                    .padding(5)
                    .background(NookDesign.Surface.fill)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                    .overlay {
                        NookDesign.Radius.shape(NookDesign.Radius.md)
                            .stroke(NookDesign.Surface.hairline, lineWidth: 1)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    // Title: shortcut key used by website
                    HStack(spacing: 4) {
                        Text(shortcut)
                            .font(NookDesign.Font.secondary)
                            .foregroundStyle(.primary)
                        Text("used by")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                        Text(websiteName)
                            .font(NookDesign.Font.secondary)
                            .foregroundStyle(.primary)
                    }
                    
                    // Subtitle: press again for Nook
                    HStack(spacing: 4) {
                        Text("Press again for")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                        Text(nookActionName)
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .transition(.toast)
    }
}

// MARK: - Preview

#Preview {
    ShortcutConflictToast(
        shortcut: "⌘K",
        websiteName: "Figma",
        nookActionName: "Command Palette"
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}