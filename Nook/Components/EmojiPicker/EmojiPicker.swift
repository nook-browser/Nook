//
//  EmojiPicker.swift
//  Nook
//
//  Created by Maciek Baginski on 02/10/2025.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Icon Button

class IconButton: NSButton {
    /// The value emitted on selection: emoji character or SF Symbol name.
    var iconValue: String = ""
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

// MARK: - Icon Picker View Controller

class IconPickerViewController: NSViewController {
    enum Tab: Int {
        case symbols = 0
        case emojis = 1
    }

    private let segmentedControl = NSSegmentedControl()
    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let contentView = NSView()
    var onIconSelected: ((String) -> Void)?
    var currentIcon: String = ""

    private var currentTab: Tab = .symbols
    private var buttons: [IconButton] = []

    // MARK: - SF Symbols

    private static let symbolNames: [String] = [
        // General
        "square.grid.2x2", "house", "star", "heart", "bookmark",
        "flag", "tag", "pin", "bolt", "sparkles",
        // Work & Productivity
        "briefcase", "building.2", "doc.text", "folder",
        "tray.full", "calendar", "clock",
        "paperplane", "envelope", "phone",
        // Development & Tech
        "terminal", "chevron.left.forwardslash.chevron.right",
        "hammer", "wrench.and.screwdriver",
        "server.rack", "cpu", "globe", "link", "network",
        // People & Communication
        "person", "person.2", "bubble.left", "bell",
        // Media & Entertainment
        "play.circle", "music.note", "photo", "film", "tv",
        "headphones", "mic",
        // Shopping & Finance
        "cart", "bag", "creditcard", "chart.bar",
        // Education & Science
        "book", "graduationcap", "brain", "lightbulb", "atom",
        // Travel & Nature
        "airplane", "car", "leaf",
        "sun.max", "moon", "cloud",
        // Lifestyle
        "gamecontroller", "paintbrush", "camera",
        "gift", "cup.and.saucer", "fork.knife",
        // Security
        "lock", "shield", "key", "eye",
        // Devices
        "laptopcomputer", "desktopcomputer",
        "wifi", "map", "location",
        // Tools
        "pencil", "scissors", "gearshape",
        "magnifyingglass", "wand.and.stars",
        "archivebox", "flame", "drop", "snowflake",
    ]

    // MARK: - Emojis

    private static let allEmojis: [String] = {
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

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 316))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        currentTab = isEmoji(currentIcon) ? .emojis : .symbols
        setupUI()
        rebuildGrid()
    }

    // MARK: - UI Setup

    private func setupUI() {
        let padding: CGFloat = 12

        // Segmented control
        segmentedControl.segmentCount = 2
        segmentedControl.setLabel("Symbols", forSegment: 0)
        segmentedControl.setLabel("Emojis", forSegment: 1)
        segmentedControl.trackingMode = .selectOne
        segmentedControl.selectedSegment = currentTab.rawValue
        segmentedControl.target = self
        segmentedControl.action = #selector(tabChanged)
        segmentedControl.segmentStyle = .rounded
        segmentedControl.frame = NSRect(
            x: padding,
            y: view.bounds.height - 30,
            width: view.bounds.width - padding * 2,
            height: 22
        )
        view.addSubview(segmentedControl)

        // Search field
        searchField.frame = NSRect(
            x: padding,
            y: view.bounds.height - 62,
            width: view.bounds.width - padding * 2,
            height: 24
        )
        searchField.placeholderString = "Search..."
        searchField.target = self
        searchField.action = #selector(searchChanged)
        view.addSubview(searchField)

        // Scroll view
        scrollView.frame = NSRect(
            x: padding,
            y: padding,
            width: view.bounds.width - padding * 2,
            height: view.bounds.height - 62 - padding * 2
        )
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = contentView
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = .clear
        view.addSubview(scrollView)
    }

    // MARK: - Actions

    @objc private func tabChanged() {
        currentTab = Tab(rawValue: segmentedControl.selectedSegment) ?? .symbols
        searchField.stringValue = ""
        rebuildGrid()
    }

    @objc private func searchChanged() {
        filterButtons()
    }

    // MARK: - Grid Building

    private func rebuildGrid() {
        contentView.subviews.removeAll()
        buttons.removeAll()

        switch currentTab {
        case .symbols:
            buildSymbolGrid()
        case .emojis:
            buildEmojiGrid()
        }
    }

    private func buildSymbolGrid() {
        let columns = 8
        let buttonSize: CGFloat = 32
        let spacing: CGFloat = 4
        let items = Self.symbolNames
        let rows = (items.count + columns - 1) / columns
        let totalHeight = CGFloat(rows) * (buttonSize + spacing) + spacing

        contentView.frame = NSRect(
            x: 0, y: 0,
            width: scrollView.contentSize.width,
            height: max(totalHeight, scrollView.bounds.height)
        )

        for (index, symbolName) in items.enumerated() {
            let row = index / columns
            let col = index % columns

            let button = IconButton(
                frame: NSRect(
                    x: CGFloat(col) * (buttonSize + spacing) + spacing,
                    y: totalHeight - CGFloat(row + 1) * (buttonSize + spacing),
                    width: buttonSize,
                    height: buttonSize
                )
            )

            button.iconValue = symbolName
            button.bezelStyle = .inline
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.wantsLayer = true
            button.layer?.cornerRadius = 6

            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: symbolName)?
                .withSymbolConfiguration(config) {
                button.image = img
            }
            button.contentTintColor = .labelColor

            button.target = self
            button.action = #selector(iconTapped(_:))

            if symbolName == currentIcon {
                button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
            }

            button.onHover = { [weak button, weak self] isHovering in
                guard let button = button, let self = self else { return }
                if isHovering {
                    button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.15).cgColor
                } else if button.iconValue == self.currentIcon {
                    button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
                } else {
                    button.layer?.backgroundColor = .clear
                }
            }

            contentView.addSubview(button)
            buttons.append(button)
        }

        scrollToTop()
    }

    private func buildEmojiGrid() {
        let columns = 8
        let buttonSize: CGFloat = 32
        let spacing: CGFloat = 4
        let items = Self.allEmojis
        let rows = (items.count + columns - 1) / columns
        let totalHeight = CGFloat(rows) * (buttonSize + spacing) + spacing

        contentView.frame = NSRect(
            x: 0, y: 0,
            width: scrollView.contentSize.width,
            height: max(totalHeight, scrollView.bounds.height)
        )

        for (index, emoji) in items.enumerated() {
            let row = index / columns
            let col = index % columns

            let button = IconButton(
                frame: NSRect(
                    x: CGFloat(col) * (buttonSize + spacing) + spacing,
                    y: totalHeight - CGFloat(row + 1) * (buttonSize + spacing),
                    width: buttonSize,
                    height: buttonSize
                )
            )

            button.iconValue = emoji
            button.title = emoji
            button.bezelStyle = .inline
            button.isBordered = false
            button.font = NSFont.systemFont(ofSize: 22)
            button.wantsLayer = true
            button.layer?.cornerRadius = 6

            button.target = self
            button.action = #selector(iconTapped(_:))

            if emoji == currentIcon {
                button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
            }

            button.onHover = { [weak button, weak self] isHovering in
                guard let button = button, let self = self else { return }
                if isHovering {
                    button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.15).cgColor
                } else if button.iconValue == self.currentIcon {
                    button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
                } else {
                    button.layer?.backgroundColor = .clear
                }
            }

            contentView.addSubview(button)
            buttons.append(button)
        }

        scrollToTop()
    }

    // MARK: - Filtering

    private func filterButtons() {
        let searchText = searchField.stringValue.lowercased()

        for button in buttons {
            if searchText.isEmpty {
                button.isHidden = false
            } else {
                // For symbols, search against the symbol name; for emojis, against the character
                button.isHidden = !button.iconValue.lowercased().contains(searchText)
            }
        }
    }

    // MARK: - Selection

    @objc private func iconTapped(_ sender: IconButton) {
        for button in buttons {
            if button !== sender {
                if button.iconValue == currentIcon {
                    button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
                } else {
                    button.layer?.backgroundColor = .clear
                }
            }
        }

        sender.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        currentIcon = sender.iconValue
        onIconSelected?(sender.iconValue)
    }

    // MARK: - Helpers

    private func scrollToTop() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.scrollView.documentView?.scroll(
                NSPoint(x: 0, y: self.contentView.bounds.height)
            )
        }
    }

    private func isEmoji(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF)
                || (scalar.value >= 0x2600 && scalar.value <= 0x26FF)
                || (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }
}

// MARK: - Emoji Picker Manager

class EmojiPickerManager: ObservableObject {
    var popover: NSPopover?
    weak var anchorView: NSView?
    @Published var selectedEmoji: String = ""

    func toggle() {
        guard let anchorView = anchorView else { return }

        if popover?.isShown == true {
            popover?.close()
            return
        }

        let picker = IconPickerViewController()
        picker.currentIcon = selectedEmoji
        picker.onIconSelected = { [weak self] icon in
            self?.selectedEmoji = icon
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

// MARK: - Anchor View

struct EmojiPickerAnchor: NSViewRepresentable {
    let manager: EmojiPickerManager

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        manager.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
