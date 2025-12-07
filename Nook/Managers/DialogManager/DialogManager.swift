//
//  DialogManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import Observation
import SwiftUI
import UniversalGlass

@MainActor
@Observable
class DialogManager {
    var isVisible: Bool = false
    var activeDialog: AnyView?

    // MARK: - Presentation

    func showDialog<Content: View>(_ dialog: Content) {
        activeDialog = AnyView(dialog)
        isVisible = true
    }

    func showDialog<Content: View>(@ViewBuilder builder: () -> Content) {
        showDialog(builder())
    }

    func closeDialog() {
        guard isVisible else {
            activeDialog = nil
            return
        }

        isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.activeDialog = nil
        }
    }

    // MARK: - Convenience Dialogs

    func showQuitDialog(
        onAlwaysQuit: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        showDialog {
            StandardDialog(
                header: {
                    EmptyView()
                },
                content: {
                    VStack(alignment: .leading, spacing: 20) {
                        Image("nook-logo-1024")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .shadow(
                                color: .white.opacity(0.3),
                                radius: 0.5,
                                y: 1
                            )
                        Text("Are you sure your want to quit Nook?")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                        Text("You may lose unsaved work in your tabs.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(10)
                },
                footer: {
                    DialogFooter(
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
                                iconName: "return",
                                variant: .primary,
                                action: onQuit
                            ),
                        ]
                    )
                }
            )
        }
    }
}

protocol DialogPresentable: View {
    associatedtype DialogContent: View

    @ViewBuilder func dialogHeader() -> DialogHeader
    @ViewBuilder func dialogContent() -> DialogContent
    @ViewBuilder func dialogFooter() -> DialogFooter
    @ViewBuilder func dialogChrome(
        header: DialogHeader,
        content: DialogContent,
        footer: DialogFooter
    ) -> AnyView
}

extension DialogPresentable {
    @ViewBuilder
    func dialogChrome(
        header: DialogHeader,
        content: DialogContent,
        footer: DialogFooter
    ) -> AnyView {
        AnyView(
            StandardDialog(
                header: { header },
                content: { content },
                footer: { footer }
            )
        )
    }

    var body: some View {
        let header = dialogHeader()
        let content = dialogContent()
        let footer = dialogFooter()
        return dialogChrome(header: header, content: content, footer: footer)
    }
}

// MARK: - Dialog Surfaces

struct DialogCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: 500, alignment: .leading)
            .background(BlurEffectView(material: .headerView, state: .active))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: .black, radius: 1, y: 0)
    }
}

struct StandardDialog<Header: View, Content: View, Footer: View>: View {
    private let header: AnyView?
    private let content: Content
    private let footer: AnyView?
    private let sectionSpacing: CGFloat

    init(
        spacing: CGFloat = 32,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        let headerView = header()
        self.header = Header.self == EmptyView.self ? nil : AnyView(headerView)
        self.content = content()
        let footerView = footer()
        self.footer = Footer.self == EmptyView.self ? nil : AnyView(footerView)
        self.sectionSpacing = spacing
    }

    var body: some View {
        DialogCard {
            VStack(alignment: .leading, spacing: 25) {
                if let header {

                    header
                }

                content

                if let footer {
                    VStack(alignment: .leading, spacing: 15) {
                        //                        Divider()
                        footer
                    }
                }

            }
        }
    }

}

struct DialogHeader: View {
    @EnvironmentObject var gradientColorManager: GradientColorManager
    let icon: String
    let title: String
    let subtitle: String?

    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(gradientColorManager.primaryColor.opacity(0.1))
                    .universalGlassEffect(
                        .clear.tint(
                            gradientColorManager.primaryColor.opacity(0.2)
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(gradientColorManager.primaryColor).frame(
                        width: 48,
                        height: 48
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
        }
        .padding(.top, 8)
    }
}

struct DialogFooter: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var gradientColorManager: GradientColorManager
    let leftButton: DialogButton?
    let rightButtons: [DialogButton]

    init(leftButton: DialogButton? = nil, rightButtons: [DialogButton]) {
        self.leftButton = leftButton
        self.rightButtons = rightButtons
    }

    var body: some View {
        HStack {
            if let leftButton = leftButton {
                if let iconName = leftButton.iconName {
                    Button(leftButton.text, action: leftButton.action)
                        .buttonStyle(
                            DialogButtonStyle(
                                variant: leftButton.variant,
                                icon: leftButton.iconName.map {
                                    AnyView(Image(systemName: $0))
                                },
                                iconPosition: .trailing
                            )
                        )
                        .conditionally(if: OSVersion.supportsGlassEffect) {
                            View in
                            View
                                .tint(
                                    Color("plainBackgroundColor").opacity(
                                        colorScheme == .light ? 0.8 : 0.4
                                    )
                                )
                        }
                        .controlSize(.extraLarge)

                        .disabled(!leftButton.isEnabled)
                        .modifier(
                            OptionalKeyboardShortcut(
                                shortcut: leftButton.keyboardShortcut
                            )
                        )
                } else {
                    Button(leftButton.text, action: leftButton.action)
                        .buttonStyle(
                            DialogButtonStyle(
                                variant: leftButton.variant,
                                icon: leftButton.iconName.map {
                                    AnyView(Image(systemName: $0))
                                },
                                iconPosition: .trailing
                            )
                        )
                        .conditionally(if: OSVersion.supportsGlassEffect) {
                            View in
                            View
                                .tint(
                                    Color("plainBackgroundColor").opacity(
                                        colorScheme == .light ? 0.8 : 0.4
                                    )
                                )
                        }
                        .controlSize(.extraLarge)
                        .disabled(!leftButton.isEnabled)
                        .modifier(
                            OptionalKeyboardShortcut(
                                shortcut: leftButton.keyboardShortcut
                            )
                        )
                }
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(Array(rightButtons.indices), id: \.self) { index in
                    let button = rightButtons[index]

                    Button(button.text, action: button.action)
                        .buttonStyle(
                            DialogButtonStyle(
                                variant: button.variant,
                                icon: button.iconName.map {
                                    AnyView(Image(systemName: $0))
                                },
                                iconPosition: .trailing
                            )
                        )
                        .controlSize(.extraLarge)
                        .disabled(!button.isEnabled)
                        .modifier(
                            OptionalKeyboardShortcut(
                                shortcut: button.keyboardShortcut
                            )
                        )
                }
            }
        }
    }
}

struct DialogButton {
    let text: String
    let iconName: String?
    let variant: DialogButtonStyleVariant
    let action: () -> Void
    let keyboardShortcut: KeyEquivalent?
    let shadowStyle: NookButtonStyle.ShadowStyle
    let isEnabled: Bool

    init(
        text: String,
        iconName: String? = nil,
        variant: DialogButtonStyleVariant = .secondary,
        keyboardShortcut: KeyEquivalent? = nil,
        shadowStyle: NookButtonStyle.ShadowStyle = .subtle,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.iconName = iconName
        self.variant = variant
        self.action = action
        self.keyboardShortcut = keyboardShortcut
        self.shadowStyle = shadowStyle
        self.isEnabled = isEnabled
    }
}

struct OptionalKeyboardShortcut: ViewModifier {
    let shortcut: KeyEquivalent?

    func body(content: Content) -> some View {
        if let shortcut = shortcut {
            content.keyboardShortcut(shortcut, modifiers: [])
        } else {
            content
        }
    }
}

enum DialogButtonStyleVariant {
    case primary
    case secondary
    case danger
}

struct DialogButtonStyle: ButtonStyle {
    var variant: DialogButtonStyleVariant = .primary
    var icon: AnyView?
    var iconPosition: IconPosition = .trailing

    enum IconPosition {
        case leading, trailing
    }

    private let padding = EdgeInsets(
        top: 10,
        leading: 16,
        bottom: 10,
        trailing: 16
    )
    private let cornerRadius: CGFloat = 10

    private var backgroundColor: Color {
        switch variant {
        case .primary: return Color(hex: "DDDDDD")
        case .secondary: return .white.opacity(0.07)
        case .danger: return Color(hex: "F60000")
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return .black
        case .secondary: return .white
        case .danger: return .white
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            if iconPosition == .leading, let icon = icon {
                icon
            }

            configuration.label
                .font(.system(size: 13, weight: .medium))

            if iconPosition == .trailing, let icon = icon {
                icon
            }
        }
        .padding(padding)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .opacity(configuration.isPressed ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
