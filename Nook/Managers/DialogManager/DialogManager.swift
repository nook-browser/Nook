//
//  DialogManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI
import Observation

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
                                variant: .destructive,
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
            .padding(24)
            .frame(maxWidth: 500, alignment: .leading)
            .background(Color(.windowBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.2))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            VStack(alignment: .leading, spacing: sectionSpacingForActiveSections) {
                if let header {
                    header
                }

                content

                if let footer {
                    footer
                }
            }
        }
    }

    private var sectionSpacingForActiveSections: CGFloat {
        var count = 0
        if header != nil { count += 1 }
        count += 1 // content
        if footer != nil { count += 1 }
        return count > 1 ? sectionSpacing : 0
    }
}

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
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
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
                    action: leftButton.action,
                    keyboardShortcut: leftButton.keyboardShortcut,
                    animationType: leftButton.animationType,
                    shadowStyle: leftButton.shadowStyle,
                    customColors: leftButton.customColors
                )
                .disabled(!leftButton.isEnabled)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(rightButtons.indices, id: \.self) { index in
                    let button = rightButtons[index]
                    NookButton(
                        text: button.text,
                        iconName: button.iconName,
                        variant: button.variant,
                        action: button.action,
                        keyboardShortcut: button.keyboardShortcut,
                        animationType: button.animationType,
                        shadowStyle: button.shadowStyle,
                        customColors: button.customColors
                    )
                    .disabled(!button.isEnabled)
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
    let keyboardShortcut: KeyEquivalent?
    let animationType: NookButton.AnimationType
    let shadowStyle: NookButton.ShadowStyle
    let customColors: NookButton.CustomColors?
    let isEnabled: Bool

    init(
        text: String,
        iconName: String? = nil,
        variant: NookButton.Variant = .primary,
        keyboardShortcut: KeyEquivalent? = nil,
        animationType: NookButton.AnimationType = .none,
        shadowStyle: NookButton.ShadowStyle = .subtle,
        customColors: NookButton.CustomColors? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.iconName = iconName
        self.variant = variant
        self.action = action
        self.keyboardShortcut = keyboardShortcut
        self.animationType = animationType
        self.shadowStyle = shadowStyle
        self.customColors = customColors
        self.isEnabled = isEnabled
    }
}


#if DEBUG
private struct DialogManagerPreviewSurface: View {
    @State private var analyticsEnabled: Bool = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.blue.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

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
                        Text("Keep Nook feeling fast by sharing anonymous performance metrics.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("We never collect your browsing history or personal data. You can opt out at any time from Settings → Privacy.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle(isOn: $analyticsEnabled) {
                            Label("Share anonymous analytics", systemImage: analyticsEnabled ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(.horizontal, 4)
                },
                footer: {
                    DialogFooter(
                        leftButton: DialogButton(
                            text: "Privacy Policy",
                            iconName: "link",
                            variant: .secondary,
                            action: {}
                        ),
                        rightButtons: [
                            DialogButton(
                                text: "Not Now",
                                variant: .secondary,
                                action: {}
                            ),
                            DialogButton(
                                text: "Enable",
                                iconName: "checkmark",
                                variant: .primary,
                                action: {}
                            )
                        ]
                    )
                }
            )
            .padding(32)
            .shadow(color: Color.black.opacity(0.2), radius: 20, y: 12)
        }
    }
}

#Preview("Dialog Example") {
    DialogManagerPreviewSurface()
        .environmentObject(GradientColorManager())
}
#endif
