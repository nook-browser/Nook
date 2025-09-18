//
//  MiniWindowToolbar.swift
//  Nook
//
//  Created by Codex on 26/08/2025.
//

import SwiftUI
import AppKit

struct MiniWindowToolbar: View {
    @Environment(\.colorScheme) private var colorScheme
    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    @ObservedObject var session: MiniWindowSession
    let adoptAction: () -> Void
    var window: NSWindow?
    
    private var cleanedTargetSpaceName: String {
        session.targetSpaceName.replacingOccurrences(of: "space", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 12) {
            trafficLights
            profilePill
            Spacer(minLength: 12)
            VStack(spacing: 2) {
                Text(hostLabel)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)

            MiniWindowShareButtonContainer(session: session, colorScheme: colorScheme)
            
            Button(action: adoptAction) {
                    HStack(spacing: 5) {
                        Text("\u{2318} O") // ⌘O as symbols
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(textColor.opacity(0.53))
                        HStack(spacing: 0) {
                            Text("move into ")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(textColor.opacity(0.9))
                            Text("\(cleanedTargetSpaceName)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.accentColor.opacity(0.8))
                        }
                        .padding(.vertical, 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(backgroundColor.opacity(1))
                            .shadow(radius: 1, x: 1, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(textColor.opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut("o", modifiers: .command)
            }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(toolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
                .blur(radius: 0.8)
        }
        .contentShape(Rectangle())
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
                        .foregroundStyle(textColor)
                )
            Text(session.originName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor.opacity(0.9))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(backgroundColor.opacity(1))
                .shadow(radius: 1, x: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(textColor.opacity(0.22), lineWidth: 1)
        )
    }

    private var toolbarBackground: some View {
        if colorScheme == .dark {
            return AnyView(Color(hex: "#242424"))
        } else {
            return AnyView(Color(hex: "#EDEDED"))
        }
    }
}

// MARK: - Traffic Lights

private extension MiniWindowToolbar {
    var trafficLights: some View {
        Group {
            if let window {
                MiniWindowTrafficLights(window: window)
            } else {
                Color.clear
            }
        }
        .frame(width: 60, height: 20, alignment: .leading)
    }
}

private struct MiniWindowTrafficLights: NSViewRepresentable {
    var window: NSWindow?

    func makeNSView(context: Context) -> TrafficLightsContainerView {
        let view = TrafficLightsContainerView()
        view.windowReference = window
        return view
    }

    func updateNSView(_ nsView: TrafficLightsContainerView, context: Context) {
        nsView.windowReference = window
    }

    final class TrafficLightsContainerView: NSView {
        weak var windowReference: NSWindow? {
            didSet {
                guard windowReference !== oldValue else { return }
                needsLayout = true
                layoutSubtreeIfNeeded()
                invalidateIntrinsicContentSize()
            }
        }

        private let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        private let buttonSpacing: CGFloat = 8

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            translatesAutoresizingMaskIntoConstraints = false
        }

        required init?(coder: NSCoder) {
            nil
        }

        override var intrinsicContentSize: NSSize {
            guard let windowReference else {
                return NSSize(width: 60, height: 18)
            }

            var width: CGFloat = 0
            var maxHeight: CGFloat = 0
            for type in buttonTypes {
                guard let button = windowReference.standardWindowButton(type) else { continue }
                width += button.frame.width
                maxHeight = max(maxHeight, button.frame.height)
            }
            if width > 0 {
                width += buttonSpacing * CGFloat(buttonTypes.count - 1)
            }
            return NSSize(width: max(width, 60), height: max(maxHeight, 18))
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if windowReference == nil {
                windowReference = window
            }
        }

        override func layout() {
            super.layout()
            guard let windowReference else { return }
            layoutButtons(for: windowReference)
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            needsLayout = true
        }

        private func layoutButtons(for window: NSWindow) {
            var xOffset: CGFloat = 0
            let containerHeight = bounds.height > 0 ? bounds.height : intrinsicContentSize.height

            for type in buttonTypes {
                guard let button = window.standardWindowButton(type) else { continue }

                if button.superview !== self {
                    button.removeFromSuperview()
                    addSubview(button)
                }

                let size = button.bounds.size == .zero ? NSSize(width: 14, height: 14) : button.bounds.size
                let yOffset = (containerHeight - size.height) / 2
                button.isBordered = false
                button.translatesAutoresizingMaskIntoConstraints = true
                button.frame = NSRect(origin: NSPoint(x: xOffset, y: yOffset), size: size)
                xOffset += size.width + buttonSpacing
            }
        }
    }
}

// MARK: - Share Button Container

private struct MiniWindowShareButtonContainer: View {
    @ObservedObject var session: MiniWindowSession
    let colorScheme: ColorScheme
    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        MiniWindowShareButton(session: session, colorScheme: colorScheme)
            .frame(width: 26, height: 29)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundColor.opacity(1))
                    .shadow(radius: 1, x: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(textColor.opacity(0.25), lineWidth: 1)
            )
    }
}

private struct MiniWindowShareButton: NSViewRepresentable {
    var session: MiniWindowSession
    let colorScheme: ColorScheme

    private var tintColor: NSColor {
        colorScheme == .dark ? .white : .black
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        button.imagePosition = .imageOnly
        button.contentTintColor = tintColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        button.setButtonType(.momentaryChange)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.session = session
        nsView.contentTintColor = tintColor
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

