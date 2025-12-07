//
//  ControlButtons.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

// MARK: - MacButtonsViewNew

struct MacButtonsViewNew: View {
    var body: some View {
        ZStack {
            NSMacButtons()
        }
    }
}

import AppKit

// MARK: - NSMacButtons

struct NSMacButtons: NSViewRepresentable {
    var btnTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    func makeNSView(context: Context) -> NSView {
        let stack = NSStackView()
        let viewButtons: [NSButton?]
        stack.spacing = 6

        viewButtons = btnTypes.map { NSWindow.standardWindowButton($0, for: .titled) }

        for button in viewButtons {
            if let button {
                stack.addArrangedSubview(button)
            }
        }

        return stack
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - MacButtonsViewModel

@Observable
class MacButtonsViewModel {
    let windowPaddingOffset: CGFloat = 2
    let width: CGFloat = 51
    let spacing = 7.5
    var buttonColors: [Color]
    var isHovered = false
    var buttonState: ButtonState = .idle
    let showIcons = true
    
    enum ButtonType {
        case close
        case minimize
        case fullscreen
    }

    enum ButtonState {
        case idle
        case active
        case hover
    }

    func getButtonColor(buttonType: ButtonType, isDark: Bool) -> (Color, Color) {
        if buttonState != .idle {
            return (macFillColor(buttonType: buttonType), macStrokeColor(buttonType: buttonType))
        }
        return (isDark ? AppColors.pinnedTabHoverLight : AppColors.pinnedTabHoverDark, Color.clear)
    }

    func macFillColor(buttonType: ButtonType) -> Color {
        switch buttonType {
        case .close: Color(red: 236 / 255, green: 106 / 255, blue: 94 / 255)
        case .minimize: Color(red: 254 / 255, green: 188 / 255, blue: 46 / 255)
        case .fullscreen: Color(red: 40 / 255, green: 200 / 255, blue: 65 / 255)
        }
    }

    func macStrokeColor(buttonType: ButtonType) -> Color {
        switch buttonType {
        case .close: Color(red: 208 / 255, green: 78 / 255, blue: 69 / 255)
        case .minimize: Color(red: 224 / 255, green: 156 / 255, blue: 21 / 255)
        case .fullscreen: Color(red: 21 / 255, green: 169 / 255, blue: 31 / 255)
        }
    }

    func getButtonAction(buttonType: ButtonType) -> () -> () {
        switch buttonType {
        case .close: { NSApp.keyWindow?.close() }
        case .minimize: { NSApp.keyWindow?.miniaturize(nil) }
        case .fullscreen: { NSApp.keyWindow?.toggleFullScreen(nil) }
        }
    }

    func getButtonImage(buttonType: ButtonType) -> String {
        switch buttonType {
        case .close: "minus"
        case .minimize: "xmark"
        case .fullscreen: "square.split.diagonal.fill"
        }
    }

    func hoverChange(hoverState: Bool) {
        if hoverState {
            if showIcons {
                buttonState = .hover
            } else {
                buttonState = .active
            }
        } else {
            buttonState = .idle
        }
    }

    init() {
        buttonColors = []
    }
}

// MARK: - MacButtonsView

struct MacButtonsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    let viewModel = MacButtonsViewModel()

    var body: some View {
        GeometryReader { geometry in
            HStack {
                HStack(alignment: .center, spacing: viewModel.spacing) {
                    MacButtonView(
                        viewModel: viewModel,
                        buttonType: .close
                    )
                    MacButtonView(
                        viewModel: viewModel,
                        buttonType: .minimize
                    )
                    MacButtonView(
                        viewModel: viewModel,
                        buttonType: .fullscreen
                    )
                }
                .onHover { Hovered in
                    viewModel.hoverChange(hoverState: Hovered)
                }
            }
            .frame(height: geometry.size.height)
            .padding(.leading, (geometry.size.height / 3) - viewModel.windowPaddingOffset)
        }
    }
}

// MARK: - MacButtonView

struct MacButtonView: View {
    @Environment(\.colorScheme) var colorScheme
    var viewModel: MacButtonsViewModel
    var buttonType: MacButtonsViewModel.ButtonType

    var body: some View {
        let isDark = colorScheme == .dark
        Button(action: viewModel.getButtonAction(buttonType: buttonType)) {
            if viewModel.buttonState == .idle {
                Circle()
                    .fill(viewModel.getButtonColor(buttonType: buttonType, isDark: isDark).0)
                    .frame(width: 12.5, height: 12.5)
            } else {
                ZStack {
                    Circle()
                        .fill(viewModel.getButtonColor(buttonType: buttonType, isDark: isDark).1)
                        .overlay(
                            Circle()
                                .inset(by: 0.5)
                                .fill(viewModel.getButtonColor(buttonType: buttonType, isDark: isDark).0)
                        )
                    if viewModel.buttonState == .hover {}
                }.frame(width: 12.5, height: 12.5)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
