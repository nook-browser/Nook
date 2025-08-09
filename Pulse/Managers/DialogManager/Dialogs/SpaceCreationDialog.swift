//
//  SpaceCreationDialog.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct SpaceCreationDialog: DialogProtocol {
    @Binding var spaceName: String
    @Binding var spaceIcon: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    init(
        spaceName: Binding<String>,
        spaceIcon: Binding<String>,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._spaceName = spaceName
        self._spaceIcon = spaceIcon
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var header: AnyView {
        AnyView(
            DialogHeader(
                icon: "folder.badge.plus",
                title: "Create New Space",
                subtitle: "Organize your tabs into a new space"
            )
        )
    }
    
    var content: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Space Name")
                        .font(.system(size: 14, weight: .medium))
                    PulseTextField(text: $spaceName, placeholder: "Enter space name", variant: .default)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Space Icon")
                        .font(.system(size: 14, weight: .medium))
                    
                    Button(action: {
                        // Show a simple picker for now
                        let emojis = ["🚀", "💡", "🎯", "⚡️", "🔥", "🌟", "💼", "🏠", "🎨", "📱"]
                        spaceIcon = emojis.randomElement() ?? "✨"
                    }) {
                        HStack(spacing: 8) {
                            Text(spaceIcon.isEmpty ? "✨" : spaceIcon)
                                .font(.system(size: 16))
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.gray.opacity(0.1))
                                .stroke(.separator, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        )
    }
    
    var footer: AnyView {
        AnyView(
            DialogFooter(
                rightButtons: [
                    DialogButton(
                        text: "Cancel",
                        variant: .secondary,
                        action: onCancel
                    ),
                    DialogButton(
                        text: "Create Space",
                        iconName: "plus",
                        variant: .primary,
                        action: onSave
                    )
                ]
            )
        )
    }
} 
