// Licensed under GPL-3.0. See LICENSE.
//
//  ShortcutRecorderView.swift
//  Nook
//
//  Created by Jonathan Caudill on 09/30/2025.
//

import SwiftUI
import NookDesign
import AppKit
import NookUI

/// The shortcut's keys as a button: click to record, Esc cancels, Delete clears.
struct ShortcutRecorderView: View {
    let keyCombination: KeyCombination?
    let action: ShortcutAction
    let shortcutManager: KeyboardShortcutManager
    let onRecord: (KeyCombination?) -> Void

    @State private var isRecording = false
    @State private var conflictAction: ShortcutAction?
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            if let conflictAction {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help("Conflicts with \(conflictAction.displayName)")
            }

            Button(action: toggleRecording) {
                Text(label)
                    .font(NookDesign.Font.body)
                    .foregroundStyle(isRecording || keyCombination == nil ? .secondary : .primary)
            }
            .buttonStyle(RectNavButtonStyle())
            .controlSize(.small)
            .nookControlSurface(isRecording, in: NookDesign.Radius.shape(NookDesign.Radius.md))
        }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if isRecording { return "Type Shortcut" }
        return keyCombination?.displayString ?? "(none)"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        conflictAction = nil
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyDown(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        conflictAction = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.isEmpty {
            switch event.keyCode {
            case 53: // Escape
                stopRecording()
                return
            case 51, 117: // Delete, Forward Delete
                stopRecording()
                onRecord(nil)
                return
            default:
                break
            }
        }

        guard let combination = KeyCombination(from: event),
              shortcutManager.isValidKeyCombination(combination) else { return }
        // A key another action holds is refused; recording continues so another can be tried.
        if let holder = shortcutManager.hasConflict(keyCombination: combination, excludingAction: action) {
            conflictAction = holder
            return
        }
        stopRecording()
        onRecord(combination)
    }
}
