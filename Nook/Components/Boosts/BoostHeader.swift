//
//  Untitled.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import SwiftUI

struct BoostHeader: View {
    @State private var isXHovered: Bool = false
    @State private var isGoBackHovered: Bool = false
    @State private var isMenuHovered: Bool = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        HStack {
            Button {
                NSApplication.shared.keyWindow?.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black.opacity(isXHovered ? 0.4 : 0.3))
                    .animation(.default, value: isXHovered)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
            .onHover { state in
                isXHovered = state
            }
            Menu {
                Button("Rename this Boost...") {

                }
                Button("Shuffle") {

                }
                Button("Reset all edits") {

                }
                Button("Delete this boost") {

                }
                Divider()
                Button("All Boosts...") {

                }
            } label: {
                HStack(spacing: 4) {
                    Text("My Boost")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black.opacity(0.45))

                }
            }
            .menuIndicator(.hidden)
            .background(isMenuHovered ? .black.opacity(0.07) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .onHover { state in
                isMenuHovered = state
            }
            Button {

            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        .black.opacity(isGoBackHovered ? 0.4 : 0.3)
                    )
                    .animation(.default, value: isGoBackHovered)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
            .onHover { state in
                isGoBackHovered = state
            }
        }
        .frame(width: 185, height: 40)
        .background(WindowDragView())
        .background(Color(hex: "F6F6F8"))
    }
}

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            if let window = view.window {
                window.isMovableByWindowBackground = true
            }
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.isMovableByWindowBackground = true
    }
}

struct HorizontalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    BoostHeader()
}
