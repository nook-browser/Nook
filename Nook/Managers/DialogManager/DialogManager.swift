//
//  DialogManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI
import Observation
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

    func showQuitDialog(onAlwaysQuit: @escaping () -> Void, onQuit: @escaping () -> Void) {
        showDialog {
            StandardDialog(
                header: {
                    DialogHeader(
                        icon: "xmark.circle",
                        title: "Are you sure you want to quit Nook?",
                        subtitle: "You may lose unsaved work in your tabs."
                    )
                },
                content: {
                    EmptyView()
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
                                iconName: "arrowshape.turn.up.left.fill",
                                variant: .primary,
                                action: onQuit
                            )
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
    @ViewBuilder func dialogChrome(header: DialogHeader, content: DialogContent, footer: DialogFooter) -> AnyView
}

extension DialogPresentable {
    @ViewBuilder
    func dialogChrome(header: DialogHeader, content: DialogContent, footer: DialogFooter) -> AnyView {
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
            .universalGlassEffect(.regular.tint(Color(.windowBackgroundColor).opacity(0.7)), in: .rect(cornerRadius: 26))
            .alwaysArrowCursor()
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
                    .universalGlassEffect(.clear.tint(gradientColorManager.primaryColor.opacity(0.2)))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(gradientColorManager.primaryColor).frame(width: 48, height: 48)
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
    @Environment(GradientColorManager.self) var gradientColorManager
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
                    Button(leftButton.text, systemImage: iconName, action: leftButton.action)
                        .buttonStyle(
                            .universalGlass()
                        )
                        .conditionally(if: OSVersion.supportsGlassEffect){ View in
                            View
                                .tint(Color("plainBackgroundColor").opacity(colorScheme == .light ? 0.8 : 0.4))
                        }
                        .controlSize(.extraLarge)
                    
                        .disabled(!leftButton.isEnabled)
                        .modifier(OptionalKeyboardShortcut(shortcut: leftButton.keyboardShortcut))
                } else {
                    Button(leftButton.text, action: leftButton.action)
                        .buttonStyle(
                            .universalGlass()
                        )
                        .conditionally(if: OSVersion.supportsGlassEffect){ View in
                            View
                                .tint(Color("plainBackgroundColor").opacity(colorScheme == .light ? 0.8 : 0.4))
                        }
                        .controlSize(.extraLarge)
                        .disabled(!leftButton.isEnabled)
                        .modifier(OptionalKeyboardShortcut(shortcut: leftButton.keyboardShortcut))
                }
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(rightButtons.indices, id: \.self) { index in
                    let button = rightButtons[index]

                    if let iconName = button.iconName {
                        Button(button.text, systemImage: iconName, action: button.action)
                            .buttonStyle(
                                .universalGlassProminent()
                            )
                            .tint(gradientColorManager.primaryColor)
                            .controlSize(.extraLarge)
                            .disabled(!button.isEnabled)
                            .modifier(OptionalKeyboardShortcut(shortcut: button.keyboardShortcut))
                    } else {
                        Button(button.text, action: button.action)
                            .buttonStyle(
                                .universalGlass()
                            )
                            .conditionally(if: OSVersion.supportsGlassEffect){ View in
                                View
                                    .tint(Color("plainBackgroundColor").opacity(colorScheme == .light ? 0.8 : 0.4))
                            }
                            .controlSize(.extraLarge)
                            .disabled(!button.isEnabled)
                            .modifier(OptionalKeyboardShortcut(shortcut: button.keyboardShortcut))
                    }
                }
            }
        }
    }
}

struct DialogButton {
    let text: String
    let iconName: String?
    let variant: NookButtonStyle.Variant
    let action: () -> Void
    let keyboardShortcut: KeyEquivalent?
    let shadowStyle: NookButtonStyle.ShadowStyle
    let isEnabled: Bool

    init(
        text: String,
        iconName: String? = nil,
        variant: NookButtonStyle.Variant = .primary,
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


#if DEBUG
struct DialogManagerPreviewSurface: View {

    var body: some View {
        StandardDialog(
            header: {
                DialogHeader(
                    icon: "sparkles",
                    title: "Sample Dialog",
                    subtitle: "Use this preview to adjust spacing, typography, and surfaces"
                )
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This is placeholder body copy to demonstrate wrapping, spacing, and text styles in the dialog. Replace this with your own content.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            },
            footer: {
                DialogFooter(
                    leftButton: DialogButton(
                        text: "Learn More",
                        iconName: "book",
                        variant: .secondary,
                        action: {}
                    ),
                    rightButtons: [
                        DialogButton(
                            text: "Close",
                            variant: .secondary,
                            action: {}
                        ),
                        DialogButton(
                            text: "OK",
                            iconName: "checkmark",
                            variant: .primary,
                            action: {}
                        )
                    ]
                )
            }
        )
        .padding(32)
        .background(
            Image("tulips").resizable().scaledToFill()
            .ignoresSafeArea()
        )
    }
}

#Preview("Dialog Example") {
    DialogManagerPreviewSurface()
        .environmentObject(GradientColorManager())
}
#endif

