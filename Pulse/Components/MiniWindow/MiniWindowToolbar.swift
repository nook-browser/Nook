//
//  MiniWindowToolbar.swift
//  Pulse
//
//  Created by Codex on 26/08/2025.
//

import SwiftUI
import AppKit

struct MiniWindowToolbar: View {
    @ObservedObject var session: MiniWindowSession
    let adoptAction: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            profilePill
            Spacer(minLength: 12)
            VStack(spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(hostLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)

            MiniWindowShareButtonContainer(session: session)

            Button(action: adoptAction) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.badge.plus")
                    Text("Open in \(session.targetSpaceName)")
                }
            }
            .buttonStyle(MiniWindowPrimaryButtonStyle())
            .keyboardShortcut("o", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(toolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
                .blur(radius: 0.8)
        }
    }

    private var hostLabel: String {
        session.currentURL.host ?? session.currentURL.absoluteString
    }

    private var profilePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                )
            Text(session.originName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    private var toolbarBackground: some View {
        LinearGradient(
            colors: [Color(hex: "9EC6FF"), Color(hex: "5A8CFF")],
            startPoint: .leading,
            endPoint: .trailing
        )
        .overlay(
            LinearGradient(
                colors: [Color.white.opacity(0.2), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Share Button Container

private struct MiniWindowShareButtonContainer: View {
    @ObservedObject var session: MiniWindowSession

    var body: some View {
        MiniWindowShareButton(session: session)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
    }
}

private struct MiniWindowShareButton: NSViewRepresentable {
    var session: MiniWindowSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        button.setButtonType(.momentaryChange)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.session = session
    }

    final class Coordinator: NSObject {
        var session: MiniWindowSession

        init(session: MiniWindowSession) {
            self.session = session
        }

        @MainActor @objc func share(_ sender: NSButton) {
            let picker = NSSharingServicePicker(items: [session.currentURL])
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}

