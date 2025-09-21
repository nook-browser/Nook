//
//  DialogManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import Observation
import SwiftUI

@MainActor
@Observable
class DialogManager {
    var isVisible: Bool = false
    var headerContent: AnyView?
    var bodyContent: AnyView?
    var footerContent: AnyView?
    var customContent: AnyView?

    // MARK: - Public Methods

    func showDialog<Header: View, Body: View, Footer: View>(
        header: Header,
        body: Body,
        footer: Footer
    ) {
        headerContent = AnyView(header)
        bodyContent = AnyView(body)
        footerContent = AnyView(footer)
        isVisible = true
    }

    func showDialog<Body: View, Footer: View>(
        body: Body,
        footer: Footer
    ) {
        headerContent = nil
        bodyContent = AnyView(body)
        footerContent = AnyView(footer)
        isVisible = true
    }

    func showDialog<Body: View>(
        body: Body
    ) {
        headerContent = nil
        bodyContent = AnyView(body)
        footerContent = nil
        customContent = nil
        isVisible = true
    }

    func showCustomDialog<Content: View>(
        header: AnyView?,
        content: Content,
        footer: AnyView?
    ) {
        headerContent = header
        customContent = AnyView(content)
        footerContent = footer
        bodyContent = nil
        isVisible = true
    }

    func closeDialog() {
        isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.clearContent()
        }
    }

    // MARK: - Private Methods

    private func clearContent() {
        headerContent = nil
        bodyContent = nil
        footerContent = nil
        customContent = nil
    }

    // MARK: - Convenience Methods

    func showQuitDialog(onAlwaysQuit: @escaping () -> Void, onQuit: @escaping () -> Void) {
        let header = DialogHeader(
            icon: "sparkles",
            title: "Are you sure you want to quit Nook?",
            subtitle: "You may lose unsaved work in your tabs."
        )

        let footer = DialogFooter(
            leftButton: DialogButton(
                text: "Always Quit",
                variant: .secondary,
                action: onAlwaysQuit
            ),
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    action: closeDialog
                ),
                DialogButton(
                    text: "Quit",
                    iconName: "arrowshape.turn.up.left.fill",
                    variant: .destructive,
                    action: onQuit
                ),
            ]
        )

        showDialog(header: header, body: Text("Body text"), footer: footer)
    }

    func showCustomContentDialog<Content: View>(
        header: AnyView?,
        content: Content,
        footer: AnyView?
    ) {
        showCustomDialog(header: header, content: content, footer: footer)
    }

    // MARK: - Predefined Dialogs

    func showDialog<T: DialogProtocol>(_ dialog: T) {
        showCustomDialog(
            header: dialog.header,
            content: dialog.content,
            footer: dialog.footer
        )
    }
}

// MARK: - Dialog Protocol

protocol DialogProtocol {
    var header: AnyView { get }
    var content: AnyView { get }
    var footer: AnyView { get }
}

// MARK: - Dialog Components

struct DialogHeader: View {
    let icon: String
    let title: String
    let subtitle: String?

    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 16) {
            // Icon with modern styling
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.top, 8)
    }
}

struct DialogFooter: View {
    let leftButton: DialogButton?
    let rightButtons: [DialogButton]

    init(leftButton: DialogButton? = nil, rightButtons: [DialogButton]) {
        self.leftButton = leftButton
        self.rightButtons = rightButtons
    }

    var body: some View {
        HStack {
            if let leftButton = leftButton {
                NookButton(
                    text: leftButton.text,
                    iconName: leftButton.iconName,
                    variant: leftButton.variant,
                    action: leftButton.action
                )
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(rightButtons.indices, id: \.self) { index in
                    let button = rightButtons[index]
                    NookButton(
                        text: button.text,
                        iconName: button.iconName,
                        variant: button.variant,
                        action: button.action
                    )
                }
            }
        }
    }
}

struct DialogButton {
    let text: String
    let iconName: String?
    let variant: NookButton.Variant
    let action: () -> Void

    init(
        text: String,
        iconName: String? = nil,
        variant: NookButton.Variant = .primary,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.iconName = iconName
        self.variant = variant
        self.action = action
    }
}
