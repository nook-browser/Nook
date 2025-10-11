//
//  EmojiPicker.swift
//  Nook
//
//  Created by Maciek Bagiński on 02/10/2025.
//

import AppKit
import SwiftUI
import Observation

class EmojiButton: NSButton {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )

        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

class EmojiPickerViewController: NSViewController {
    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let contentView = NSView()
    var onEmojiSelected: ((String) -> Void)?
    var currentEmoji: String = ""

    private let allEmojis: [String] = {
        var result: [String] = []
        let ranges: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F,
            0x1F300...0x1F5FF,
            0x1F680...0x1F6FF,
            0x1F900...0x1F9FF,
            0x2600...0x26FF,
            0x2700...0x27BF,
            0x1F1E6...0x1F1FF,
        ]

        for range in ranges {
            for scalar in range {
                if let unicodeScalar = UnicodeScalar(scalar) {
                    result.append(String(unicodeScalar))
                }
            }
        }
        return result
    }()

    private var filteredEmojis: [String] = []
    private var emojiButtons: [EmojiButton] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 280))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        filteredEmojis = allEmojis
        setupUI()
        buildEmojiGrid()
    }

    private func setupUI() {
        let padding: CGFloat = 12

        searchField.frame = NSRect(
            x: padding,
            y: view.bounds.height - 32,
            width: view.bounds.width - padding * 2,
            height: 24
        )
        searchField.placeholderString = "Search emojis..."
        searchField.target = self
        searchField.action = #selector(searchChanged)
        view.addSubview(searchField)

        scrollView.frame = NSRect(
            x: padding,
            y: padding,
            width: view.bounds.width - padding * 2,
            height: view.bounds.height - 32 - padding * 2
        )
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = contentView
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = .clear
        view.addSubview(scrollView)
    }

    @objc private func searchChanged() {
        updateVisibility()
    }

    private func updateVisibility() {
        let searchText = searchField.stringValue.lowercased()

        for button in emojiButtons {
            if searchText.isEmpty {
                button.isHidden = false
            } else {
                button.isHidden = !button.title.contains(searchText)
            }
        }
    }

    private func buildEmojiGrid() {
        let columns = 8
        let buttonSize: CGFloat = 32
        let spacing: CGFloat = 4
        let rows = (filteredEmojis.count + columns - 1) / columns

        let totalHeight = CGFloat(rows) * (buttonSize + spacing) + spacing

        contentView.frame = NSRect(
            x: 0,
            y: 0,
            width: scrollView.contentSize.width,
            height: max(totalHeight, scrollView.bounds.height)
        )

        emojiButtons.removeAll()

        for (index, emoji) in filteredEmojis.enumerated() {
            let row = index / columns
            let col = index % columns

            let button = EmojiButton(
                frame: NSRect(
                    x: CGFloat(col) * (buttonSize + spacing) + spacing,
                    y: totalHeight - CGFloat(row + 1) * (buttonSize + spacing),
                    width: buttonSize,
                    height: buttonSize
                )
            )

            button.title = emoji
            button.bezelStyle = .inline
            button.isBordered = false
            button.font = NSFont.systemFont(ofSize: 24)
            button.target = self
            button.action = #selector(emojiTapped(_:))
            button.wantsLayer = true
            button.layer?.cornerRadius = 4

            if emoji == currentEmoji {
                button.layer?.backgroundColor =
                    NSColor.black.withAlphaComponent(0.2).cgColor
            }

            button.onHover = { [weak button, weak self] isHovering in
                guard let button = button, let self = self else { return }
                if isHovering {
                    button.layer?.backgroundColor =
                        NSColor.black.withAlphaComponent(0.3).cgColor
                } else {
                    if button.title == self.currentEmoji {
                        button.layer?.backgroundColor =
                            NSColor.black.withAlphaComponent(0.2).cgColor
                    } else {
                        button.layer?.backgroundColor = .clear
                    }
                }
            }

            contentView.addSubview(button)
            emojiButtons.append(button)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.scrollView.documentView?.scroll(
                NSPoint(x: 0, y: self.contentView.bounds.height)
            )
        }
    }

    @objc private func emojiTapped(_ sender: EmojiButton) {
        for button in emojiButtons {
            if button.title != sender.title {
                button.layer?.backgroundColor = .clear
            }
        }

        sender.layer?.backgroundColor =
            NSColor.black.withAlphaComponent(0.2).cgColor

        currentEmoji = sender.title
        onEmojiSelected?(sender.title)
    }
}

@Observable
class EmojiPickerManager {
    var popover: NSPopover?
    weak var anchorView: NSView?
    var selectedEmoji: String = ""

    func toggle() {
        guard let anchorView = anchorView else { return }

        if popover?.isShown == true {
            popover?.close()
            return
        }

        let picker = EmojiPickerViewController()
        picker.currentEmoji = selectedEmoji
        picker.onEmojiSelected = { [weak self] emoji in
            self?.selectedEmoji = emoji
        }

        popover = NSPopover()
        popover?.contentViewController = picker
        popover?.behavior = .semitransient

        guard let window = anchorView.window,
            let screen = window.screen
        else {
            popover?.show(
                relativeTo: anchorView.bounds,
                of: anchorView,
                preferredEdge: .minY
            )
            return
        }

        let anchorFrameInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorFrameInScreen = window.convertToScreen(anchorFrameInWindow)

        let popoverWidth: CGFloat = 320
        let screenFrame = screen.visibleFrame

        var positioningRect = anchorView.bounds

        let rightEdge = anchorFrameInScreen.maxX
        let leftEdge = anchorFrameInScreen.minX

        if rightEdge + popoverWidth > screenFrame.maxX {
            let overflow = (rightEdge + popoverWidth) - screenFrame.maxX
            positioningRect.origin.x -= overflow
        } else if leftEdge < screenFrame.minX {
            let overflow = screenFrame.minX - leftEdge
            positioningRect.origin.x += overflow
        }

        popover?.show(
            relativeTo: positioningRect,
            of: anchorView,
            preferredEdge: .maxY
        )
    }
}

struct EmojiPickerAnchor: NSViewRepresentable {
    let manager: EmojiPickerManager

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        manager.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
