import AppKit
import SwiftUI

public struct TooltipStyle {
    public var padding: EdgeInsets =
        .init(top: 5, leading: 10, bottom: 5, trailing: 18)
    public init() {}
}

private final class FloatingTooltipWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init<Content: View>(
        content: Content,
        style: TooltipStyle,
        at position: CGPoint
    ) {
        super.init(
            contentRect: CGRect(
                x: position.x,
                y: position.y,
                width: 1,
                height: 1
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false

        let isDark = NSAppearance.currentDrawing().name == .darkAqua

        let hostingView = NSHostingView(
            rootView:
            content
                .foregroundStyle(Color(hex: isDark ? "EFEFF0" : "212124"))
                .font(.system(size: 12, weight: .medium))
                .padding(style.padding)
                .fixedSize()
                .background(
                    ZStack {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 3,
                            bottomLeadingRadius: 14,
                            bottomTrailingRadius: 50,
                            topTrailingRadius: 50
                        )
                        .fill(isDark ? Color(hex: "191922") : .white)
                        UnevenRoundedRectangle(
                            topLeadingRadius: 3,
                            bottomLeadingRadius: 14,
                            bottomTrailingRadius: 50,
                            topTrailingRadius: 50
                        )
                        .stroke(
                            Color(isDark ? .white : .black).opacity(0.2),
                            lineWidth: 0.5
                        )
                    }
                    .compositingGroup()
                    .drawingGroup()
                )
                .animation(.easeOut(duration: 0.1), value: isDark)
        )

        contentView = hostingView

        let fittingSize = hostingView.fittingSize
        let finalFrame = CGRect(
            x: position.x,
            y: position.y - fittingSize.height,
            width: fittingSize.width,
            height: fittingSize.height
        )

        setFrame(finalFrame, display: true)
    }

    deinit {
        contentView = nil
    }
}

private final class FloatingTooltipManager: ObservableObject {
    static let shared = FloatingTooltipManager()
    private var tooltipWindow: FloatingTooltipWindow?

    private init() {}

    func show<Content: View>(
        at globalPosition: CGPoint,
        style: TooltipStyle,
        @ViewBuilder content: @escaping () -> Content
    ) {
        DispatchQueue.main.async {
            self.hide()

            // Convert SwiftUI coordinates to AppKit screen coordinates
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height
            let appKitPosition = CGPoint(
                x: globalPosition.x,
                y: screenHeight - globalPosition.y
            )

            let window = FloatingTooltipWindow(
                content: content(),
                style: style,
                at: appKitPosition
            )

            self.tooltipWindow = window
            window.alphaValue = 1.0
            window.orderFront(nil)
        }
    }

    func hide() {
        guard let window = tooltipWindow else { return }
        tooltipWindow = nil

        DispatchQueue.main.async {
            window.orderOut(nil)
            window.close()
            window.contentView = nil
        }
    }
}

private struct HelpTooltipModifier<TooltipContent: View>: ViewModifier {
    let style: TooltipStyle
    let tooltipContent: () -> TooltipContent

    @State private var isHovering = false
    @State private var anchorFrame: CGRect = .zero
    @State private var hoverTask: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: TooltipFrameKey.self,
                            value: geo.frame(in: .global)
                        )
                        .onChange(of: geo.size) { _, _ in
                            DispatchQueue.main.async {
                                anchorFrame = geo.frame(in: .global)
                            }
                        }
                }
            )
            .onPreferenceChange(TooltipFrameKey.self) { frame in
                anchorFrame = frame
            }
            .onHover { hovering in
                isHovering = hovering
                hoverTask?.cancel()

                if hovering {
                    let task = DispatchWorkItem {
                        if self.isHovering {
                            self.showTooltip()
                        }
                    }
                    hoverTask = task
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.5,
                        execute: task
                    )
                } else {
                    FloatingTooltipManager.shared.hide()
                }
            }
    }

    private func showTooltip() {
        // Get the current window frame
        guard let window = NSApp.keyWindow else { return }
        let windowFrame = window.frame

        // Calculate the position relative to the current window size
        print(anchorFrame.minY)
        print(anchorFrame.height)
        let tooltipPosition = CGPoint(
            x: windowFrame.minX + anchorFrame.minX + anchorFrame.width,
            y: windowFrame.minY + anchorFrame.minY + anchorFrame.height / 4
        )

        FloatingTooltipManager.shared.show(
            at: tooltipPosition,
            style: style
        ) {
            self.tooltipContent()
        }
    }
}

private struct TooltipFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

public extension View {
    func helpTooltip<Content: View>(
        style: TooltipStyle = TooltipStyle(),
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(HelpTooltipModifier(style: style, tooltipContent: content))
    }

    func helpTooltip(
        _ text: String,
        style: TooltipStyle = TooltipStyle()
    ) -> some View {
        helpTooltip(style: style) {
            Text(text)
        }
    }
}
