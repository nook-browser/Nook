// Licensed under GPL-3.0. See LICENSE.
//
//  DialogManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import Observation
import SwiftUI
import Garnish
import NookDesign
import NookUI
import NookWeb

struct DialogPresentation: Identifiable {
    let id = UUID()
    let content: AnyView
    let windowID: UUID?
    let blocksTabKey: Bool
    let key: String?
    var isPresented = true
}

@MainActor
@Observable
class DialogManager {
    private(set) var presentations: [DialogPresentation] = []

    @ObservationIgnored private weak var windowRegistry: WindowRegistry?
    private var tabKeyMonitor: Any?

    init(windowRegistry: WindowRegistry) {
        self.windowRegistry = windowRegistry
    }

    // MARK: - Presentation

    func presentations(in windowID: UUID) -> [DialogPresentation] {
        presentations.filter { $0.windowID == nil || $0.windowID == windowID }
    }

    func isVisible(in windowID: UUID) -> Bool {
        presentations.contains { $0.windowID == nil || $0.windowID == windowID }
    }

    func hasPresentation(key: String, in windowID: UUID) -> Bool {
        presentations.contains { $0.key == key && $0.windowID == windowID && $0.isPresented }
    }

    func showDialog<Content: View>(
        _ dialog: Content,
        in windowID: UUID? = nil,
        blocksTabKey: Bool = true,
        key: String? = nil
    ) {
        guard let target = windowID ?? windowRegistry?.activeWindowId else { return }
        presentations.append(DialogPresentation(
            content: AnyView(dialog),
            windowID: target,
            blocksTabKey: blocksTabKey,
            key: key
        ))
        updateTabKeyMonitor()
    }

    func showDialog<Content: View>(@ViewBuilder builder: () -> Content) {
        showDialog(builder())
    }

    func closeDialog() {
        let windowID = windowRegistry?.activeWindowId
        guard let presentation = presentations.last(where: {
            windowID == nil || $0.windowID == nil || $0.windowID == windowID
        }) else { return }
        dismiss(presentation.id)
    }

    func dismiss(_ presentationID: UUID) {
        guard let index = presentations.firstIndex(where: { $0.id == presentationID }),
              presentations[index].isPresented else { return }
        withAnimation(NookDesign.Motion.spring) {
            presentations[index].isPresented = false
        }
        updateTabKeyMonitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self,
                  let index = self.presentations.firstIndex(where: { $0.id == presentationID }),
                  !self.presentations[index].isPresented else { return }
            self.presentations.remove(at: index)
        }
    }

    func dismissDialogs(in windowID: UUID) {
        presentations.removeAll { $0.windowID == windowID }
        updateTabKeyMonitor()
    }

    // MARK: - Tab Key Blocking

    private func updateTabKeyMonitor() {
        guard presentations.contains(where: { $0.blocksTabKey && $0.isPresented }) else {
            removeTabKeyMonitor()
            return
        }
        guard tabKeyMonitor == nil else { return }
        tabKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let shouldBlock = MainActor.assumeIsolated {
                guard let self, event.keyCode == 48 else { return false }
                let windowID = self.windowRegistry?.activeWindowId
                return self.presentations.last(where: {
                    windowID == nil || $0.windowID == nil || $0.windowID == windowID
                }).map({ $0.blocksTabKey && $0.isPresented }) == true
            }
            if shouldBlock {
                NSSound.beep()
                return nil
            }
            return event
        }
    }

    private func removeTabKeyMonitor() {
        if let monitor = tabKeyMonitor {
            NSEvent.removeMonitor(monitor)
            tabKeyMonitor = nil
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
                        Text("Quit Nook?")
                            .font(NookDesign.Font.heading)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("You may lose unsaved work in your tabs.")
                            .font(NookDesign.Font.label)
                            .foregroundStyle(AppColors.textSecondary)
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
                                customIcon: AnyView(KeycapLabel("esc")),
                                variant: .secondary,
                                keyboardShortcut: .escape,
                                action: closeDialog
                            ),
                            DialogButton(
                                text: "Quit",
                                iconName: "return",
                                variant: .primary,
                                keyboardShortcut: .return,
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
        NookPanel(maxWidth: NookDesign.Size.dialogMaxWidth) {
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
                    .fill(gradientColorManager.accentColor.opacity(0.1))
                    .nookClearGlassEffect(tint: gradientColorManager.accentColor.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(NookDesign.Font.titleLarge)
                    .foregroundStyle(gradientColorManager.accentColor).frame(
                        width: 48,
                        height: 48
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(NookDesign.Font.heading)
                    .foregroundStyle(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(NookDesign.Font.body)
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
                Button(leftButton.text, action: leftButton.action)
                    .buttonStyle(
                        DialogButtonStyle(
                            variant: leftButton.variant,
                            icon: leftButton.resolvedIcon,
                            iconPosition: .trailing
                        )
                    )
                    .tint(
                        Color("plainBackgroundColor").opacity(
                            colorScheme == .light ? 0.8 : 0.4
                        )
                    )
                    .controlSize(.extraLarge)
                    .disabled(!leftButton.isEnabled)
                    .modifier(
                        OptionalKeyboardShortcut(
                            shortcut: leftButton.keyboardShortcut
                        )
                    )
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(Array(rightButtons.indices), id: \.self) { index in
                    let button = rightButtons[index]

                    Button(button.text, action: button.action)
                        .buttonStyle(
                            DialogButtonStyle(
                                variant: button.variant,
                                icon: button.resolvedIcon,
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
    let customIcon: AnyView?
    let variant: DialogButtonStyleVariant
    let action: () -> Void
    let keyboardShortcut: KeyEquivalent?
    let shadowStyle: NookButtonStyle.ShadowStyle
    let isEnabled: Bool

    /// The resolved icon view: customIcon takes priority, then iconName as SF Symbol
    var resolvedIcon: AnyView? {
        if let customIcon { return customIcon }
        return iconName.map { AnyView(Image(systemName: $0)) }
    }

    init(
        text: String,
        iconName: String? = nil,
        customIcon: AnyView? = nil,
        variant: DialogButtonStyleVariant = .secondary,
        keyboardShortcut: KeyEquivalent? = nil,
        shadowStyle: NookButtonStyle.ShadowStyle = .subtle,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.iconName = iconName
        self.customIcon = customIcon
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
    @EnvironmentObject var gradientColorManager: GradientColorManager
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
    private let cornerRadius: CGFloat = NookDesign.Radius.md

    private var backgroundColor: Color {
        switch variant {
        // A fixed light fill with black text read as white on white in dark mode. The accent
        // carries the primary action, and the secondary sits on the same fill rows use.
        case .primary: return gradientColorManager.accentColor
        case .secondary: return NookDesign.Surface.fill
        case .danger: return NookDesign.Surface.danger
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return Garnish.contrastingShade(of: gradientColorManager.accentColor, targetRatio: 4.5, blendStyle: .strong) ?? .white
        case .secondary: return .primary
        case .danger: return .white
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            if iconPosition == .leading, let icon = icon {
                icon
            }

            configuration.label
                .font(NookDesign.Font.body)

            if iconPosition == .trailing, let icon = icon {
                icon
            }
        }
        .padding(padding)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .clipShape(NookDesign.Radius.shape(cornerRadius))
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .opacity(configuration.isPressed ? 0.8 : 1.0)
        .animation(NookDesign.Motion.quick, value: configuration.isPressed)
    }
}

/// A small rounded badge for displaying keyboard shortcut hints (e.g. "esc", "tab")
struct KeycapLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(NookDesign.Font.caption)
            .fontDesign(.rounded)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(NookDesign.Surface.fill)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
    }
}
