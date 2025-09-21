//
//  SpaceCreationDialog.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import AppKit
import SwiftUI

struct SpaceCreationDialog: DialogProtocol {
    @Binding var spaceName: String
    @Binding var spaceIcon: String
    let onSave: () -> Void
    let onCancel: () -> Void
    let onClose: () -> Void

    @State private var isCreating: Bool = false {
        didSet {
            print("📊 SpaceCreationDialog isCreating changed to: \(isCreating)")
        }
    }

    init(
        spaceName: Binding<String>,
        spaceIcon: Binding<String>,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        _spaceName = spaceName
        _spaceIcon = spaceIcon
        self.onSave = onSave
        self.onCancel = onCancel
        self.onClose = onClose
    }

    var header: AnyView {
        AnyView(
            VStack(spacing: 16) {
                // Icon with modern styling
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 4) {
                    Text("Create New Space")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Organize your tabs into a new space")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 8)
        )
    }

    var content: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 20) {
                // Space Name Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Space Name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    NookTextField(
                        text: $spaceName,
                        placeholder: "Enter space name",
                        variant: .default,
                        iconName: "textformat"
                    )
                }

                // Space Icon Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Space Icon")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        // Simple emoji picker
                        SimpleEmojiPicker(text: $spaceIcon)

                        Text("Choose an emoji to represent this space")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 4)
        )
    }

    var footer: AnyView {
        AnyView(
            HStack(spacing: 12) {
                Spacer()

                HStack(spacing: 8) {
                    NookButton.createButton(
                        text: "Cancel",
                        variant: .secondary,
                        action: onCancel,
                        keyboardShortcut: .escape
                    )

                    NookButton.animatedCreateButton(
                        text: "Create Space",
                        iconName: "plus",
                        variant: .primary,
                        action: {
                            print("🔘 Dialog Create button onSave called")
                            handleSave()
                        },
                        keyboardShortcut: .return
                    )
                }
            }
            .padding(.top, 8)
        )
    }

    private func handleSave() {
        print("🚀 SpaceCreationDialog handleSave called")

        // Call the original onSave immediately
        print("📞 Calling onSave")
        onSave()

        // Wait for 1 second then close the dialog
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🚪 Closing dialog")
            onClose()
        }
    }
}

// MARK: - Simple Emoji Picker

struct SimpleEmojiPicker: View {
    @Binding var text: String
    @State private var isHovered = false

    private let defaultEmoji = "✨"

    var body: some View {
        Button(action: showEmojiPicker) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
                    .frame(width: 44, height: 44)

                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isHovered ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.1),
                        lineWidth: 1
                    )
                    .frame(width: 44, height: 44)

                Text(text.isEmpty ? defaultEmoji : text)
                    .font(.system(size: 18))
            }
        }
        .buttonStyle(.plain)
        .alwaysArrowCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func showEmojiPicker() {
        // This would ideally show a native emoji picker
        // For now, we'll use the character palette
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(nil)
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}

// MARK: - Legacy EmojiTextField (kept for compatibility)

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

    func updateNSView(_: NSView, context: Context) {
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
