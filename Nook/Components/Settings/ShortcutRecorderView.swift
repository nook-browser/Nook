//
//  ShortcutRecorderView.swift
//  Nook
//
//  Created by Jonathan Caudill on 09/30/2025.
//

import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    @Binding var keyCombination: KeyCombination
    @State private var isRecording = false
    @State private var recordingKey: String = ""
    @State private var recordingModifiers: Modifiers = []
    @State private var hasConflict = false
    @State private var conflictAction: ShortcutAction? = nil

    let action: ShortcutAction
    let shortcutManager: KeyboardShortcutManager
    let onRecordingComplete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                HStack(spacing: 4) {
                    Image(systemName: isRecording ? "stop.fill" : "pencil")
                    Text(isRecording ? "Recording..." : keyCombination.displayString)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.red.opacity(0.2) : Color(.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(hasConflict ? Color.red : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            if hasConflict, let conflictAction = conflictAction {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .help("Conflicts with \(conflictAction.displayName)")
            }

            Button("Clear") {
                clearShortcut()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .disabled(keyCombination.key.isEmpty && keyCombination.modifiers.isEmpty)
        }
        .onAppear {
            setupKeyMonitor()
        }
        .onChange(of: recordingKey) {
            checkForConflicts()
        }
        .onChange(of: recordingModifiers) {
            checkForConflicts()
        }
    }

    private func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        recordingKey = ""
        recordingModifiers = []
    }

    private func finishRecording() {
        isRecording = false
        if !recordingKey.isEmpty || !recordingModifiers.isEmpty {
            let newCombination = KeyCombination(key: recordingKey, modifiers: recordingModifiers)
            if shortcutManager.isValidKeyCombination(newCombination) {
                keyCombination = newCombination
                onRecordingComplete()
            }
        }
    }

    private func clearShortcut() {
        keyCombination = KeyCombination(key: "", modifiers: [])
        onRecordingComplete()
    }

    private func checkForConflicts() {
        guard !recordingKey.isEmpty || !recordingModifiers.isEmpty else {
            hasConflict = false
            conflictAction = nil
            return
        }

        let testCombination = KeyCombination(key: recordingKey, modifiers: recordingModifiers)
        if let conflictingAction = shortcutManager.hasConflict(keyCombination: testCombination, excludingAction: action) {
            hasConflict = true
            conflictAction = conflictingAction
        } else {
            hasConflict = false
            conflictAction = nil
        }
    }

    private func setupKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            guard isRecording else { return event }

            switch event.type {
            case .keyDown:
                handleKeyDown(event)
                return nil // Consume the event
            case .flagsChanged:
                handleFlagsChanged(event)
                return nil // Consume the event
            default:
                return event
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Don't record modifier keys alone
        guard !event.modifierFlags.contains(.command) ||
              !event.modifierFlags.contains(.option) ||
              !event.modifierFlags.contains(.control) ||
              !event.modifierFlags.contains(.shift) else {
            return
        }

        if let key = event.charactersIgnoringModifiers?.lowercased() {
            recordingKey = key
            finishRecording()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        var newModifiers: Modifiers = []

        if event.modifierFlags.contains(.command) {
            newModifiers.insert(.command)
        }
        if event.modifierFlags.contains(.option) {
            newModifiers.insert(.option)
        }
        if event.modifierFlags.contains(.control) {
            newModifiers.insert(.control)
        }
        if event.modifierFlags.contains(.shift) {
            newModifiers.insert(.shift)
        }

        recordingModifiers = newModifiers
    }
}
