//
//  SpaceCreationDialog.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI
import AppKit

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
                    NookTextField(text: $spaceName, placeholder: "Enter space name", variant: .default)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Space Icon")
                        .font(.system(size: 14, weight: .medium))
                    EmojiTextField(text: $spaceIcon)
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

struct EmojiTextField: NSViewRepresentable {
    @Binding var text: String
    
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        
        let textField = NSTextField()
        textField.stringValue = text.isEmpty ? "✨" : text
        textField.delegate = context.coordinator
        textField.placeholderString = "✨"
        textField.font = NSFont.systemFont(ofSize: 16)
        textField.alignment = .center
        textField.maximumNumberOfLines = 1
        textField.usesSingleLineMode = true
        textField.frame = NSRect(x: 0, y: 0, width: 40, height: 24)
        
        let button = NSButton()
        button.title = "▼"
        button.bezelStyle = .roundRect
        button.target = context.coordinator
        button.action = #selector(Coordinator.showEmojiPicker)
        button.frame = NSRect(x: 45, y: 0, width: 30, height: 24)
        
        containerView.addSubview(textField)
        containerView.addSubview(button)
        
        context.coordinator.textField = textField
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let textField = context.coordinator.textField {
            if textField.stringValue != text {
                textField.stringValue = text.isEmpty ? "✨" : text
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: EmojiTextField
        var textField: NSTextField?
        
        init(_ parent: EmojiTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                let newText = textField.stringValue
                if !newText.isEmpty {
                    // Take only the last character (emoji)
                    let emoji = String(newText.last!)
                    DispatchQueue.main.async {
                        self.parent.text = emoji
                    }
                    // Clear extra text, keep only the emoji
                    textField.stringValue = emoji
                }
            }
        }
        
        @objc func showEmojiPicker() {
            if let textField = textField {
                textField.becomeFirstResponder()
                NSApp.orderFrontCharacterPalette(textField)
            }
        }
    }
}
