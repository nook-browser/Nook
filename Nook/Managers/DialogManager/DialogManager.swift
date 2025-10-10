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
                )
            ]
        )
        
        showDialog(header: header, body: EmptyView(), footer: footer)
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
        HStack(spacing: 16) {
            // Icon with modern styling
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

            VStack(spacing: 24) {
                DialogHeader(
                    icon: "sparkles",
                    title: "Sample Dialog",
                    subtitle: "Use this preview to adjust spacing, typography, and surfaces"
                )

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
            .padding(24)
            .frame(maxWidth: 420, alignment: .leading)
            .background(Color(.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.2))
            )
            .shadow(color: Color.black.opacity(0.2), radius: 20, y: 12)
            .padding(32)
        }
    }
}

#Preview("Dialog Example") {
    DialogManagerPreviewSurface()
        .environmentObject(GradientColorManager())
}
#endif

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
