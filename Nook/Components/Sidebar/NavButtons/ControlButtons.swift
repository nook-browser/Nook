import AppKit
import Observation
import SwiftUI

// MARK: - MacButtonsViewNew

struct MacButtonsViewNew: View {
    var body: some View {
        ZStack {
            NSMacButtons()
        }
    }
}

// MARK: - NSMacButtons

struct NSMacButtons: NSViewRepresentable {
    var btnTypes: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton,
    ]

    func makeNSView(context _: Context) -> NSView {
        let stack = NSStackView()
        stack.spacing = 6

        let viewButtons = btnTypes.map {
            NSWindow.standardWindowButton($0, for: .titled)
        }

        for button in viewButtons {
            if let button {
                stack.addArrangedSubview(button)
            }
        }

        return stack
    }

    func updateNSView(_: NSView, context _: Context) {}
}

// MARK: - MacButtonsViewModel

@Observable
final class MacButtonsViewModel {
    private weak var browserManager: BrowserManager?

    let windowPaddingOffset: CGFloat = 2
    let width: CGFloat = 51
    let spacing: CGFloat = 7.5
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

    init(browserManager: BrowserManager?) {
        self.browserManager = browserManager
        buttonColors = []
    }

    func getButtonColor(buttonType: ButtonType) -> (Color, Color) {
        if buttonState != .idle {
            return (
                macFillColor(buttonType: buttonType),
                macStrokeColor(buttonType: buttonType)
            )
        }
        return (Color.primary.opacity(0.2), Color.clear)
    }

    func macFillColor(buttonType: ButtonType) -> Color {
        switch buttonType {
        case .close:
            Color(red: 236 / 255, green: 106 / 255, blue: 94 / 255)
        case .minimize:
            Color(red: 254 / 255, green: 188 / 255, blue: 46 / 255)
        case .fullscreen:
            Color(red: 40 / 255, green: 200 / 255, blue: 65 / 255)
        }
    }

    func macStrokeColor(buttonType: ButtonType) -> Color {
        switch buttonType {
        case .close:
            Color(red: 208 / 255, green: 78 / 255, blue: 69 / 255)
        case .minimize:
            Color(red: 224 / 255, green: 156 / 255, blue: 21 / 255)
        case .fullscreen:
            Color(red: 21 / 255, green: 169 / 255, blue: 31 / 255)
        }
    }

    func getButtonAction(buttonType: ButtonType) -> () -> Void {
        switch buttonType {
        case .close:
            return { [weak self] in
                Task { @MainActor in
                    print("Closed and unloaded all tabs")
                    self?.browserManager?.tabManager.unloadAllInactiveTabs()
                    NSApp.keyWindow?.close()
                }
            }
        case .minimize:
            return {
                NSApp.keyWindow?.miniaturize(nil)
            }
        case .fullscreen:
            return {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
    }

    func getButtonImage(buttonType: ButtonType) -> String {
        switch buttonType {
        case .close:
            "minus"
        case .minimize:
            "xmark"
        case .fullscreen:
            "square.split.diagonal.fill"
        }
    }

    func hoverChange(hoverState: Bool) {
        if hoverState {
            buttonState = showIcons ? .hover : .active
        } else {
            buttonState = .idle
        }
    }
}

// MARK: - MacButtonsView

struct MacButtonsView: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @State private var viewModel: MacButtonsViewModel?

    var body: some View {
        GeometryReader { geometry in
            HStack {
                if let vm = viewModel {
                    HStack(alignment: .center, spacing: vm.spacing) {
                        MacButtonView(viewModel: vm, buttonType: .close)
                        MacButtonView(viewModel: vm, buttonType: .minimize)
                        MacButtonView(viewModel: vm, buttonType: .fullscreen)
                    }
                    .onHover { hovered in
                        vm.hoverChange(hoverState: hovered)
                    }
                }
            }
            .frame(height: geometry.size.height)
            .padding(
                .leading,
                (geometry.size.height / 3) - (viewModel?.windowPaddingOffset ?? 2)
            )
        }
        .onAppear {
            if viewModel == nil {
                viewModel = MacButtonsViewModel(browserManager: browserManager)
            }
        }
    }
}

// MARK: - MacButtonView

struct MacButtonView: View {
    var viewModel: MacButtonsViewModel
    var buttonType: MacButtonsViewModel.ButtonType

    var body: some View {
        Button(action: viewModel.getButtonAction(buttonType: buttonType)) {
            if viewModel.buttonState == .idle {
                Circle()
                    .fill(viewModel.getButtonColor(buttonType: buttonType).0)
                    .frame(width: 12.5, height: 12.5)
            } else {
                ZStack {
                    Circle()
                        .fill(viewModel.getButtonColor(buttonType: buttonType).1)
                        .overlay(
                            Circle()
                                .inset(by: 0.5)
                                .fill(viewModel.getButtonColor(buttonType: buttonType).0)
                        )
                    if viewModel.buttonState == .hover {}
                }
                .frame(width: 12.5, height: 12.5)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
