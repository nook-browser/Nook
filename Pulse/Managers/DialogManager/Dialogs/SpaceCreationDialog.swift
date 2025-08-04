//
//  SpaceCreationDialog.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct SpaceCreationDialog: DialogProtocol {
    @Binding var spaceName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    init(
        spaceName: Binding<String>,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._spaceName = spaceName
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
