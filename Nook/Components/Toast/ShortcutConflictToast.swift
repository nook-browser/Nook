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
import UniversalGlass

// MARK: - Shortcut Conflict Toast View

struct ShortcutConflictToast: View {
    let conflictInfo: ShortcutConflictInfo
    
    var body: some View {
        ToastView {
            HStack(spacing: 10) {
                // Keyboard icon
                Image(systemName: "keyboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .padding(5)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.4), lineWidth: 1)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    // Title: shortcut key used by website
                    HStack(spacing: 4) {
                        Text(conflictInfo.keyCombination.displayString)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("used by")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(conflictInfo.websiteName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    
                    // Subtitle: press again for Nook
                    HStack(spacing: 4) {
                        Text("Press again for")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(conflictInfo.nookActionName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
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
        conflictInfo: ShortcutConflictInfo(
            keyCombination: KeyCombination(key: "k", modifiers: [.command]),
            websiteName: "Figma",
            websiteShortcutDescription: "Search / Quick Actions",
            nookActionName: "Command Palette",
            windowId: UUID()
        )
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}