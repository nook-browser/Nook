//
//  NookDesign.swift
//  Nook
//
//  Single source of truth for radii, spacing, sizes, type, motion,
//  surfaces, and elevation. No literal radius, font size, shadow, or
//  animation duration may appear in the UI layer outside this file.
//

import SwiftUI

enum NookDesign {

    // MARK: - Radius (all continuous / squircle)

    enum Radius {
        static let xs: CGFloat = 4      // favicon
        static let sm: CGFloat = 6      // icon button, menu item, small chip
        static let md: CGFloat = 8      // tab row, nav button, URL bar
        static let lg: CGFloat = 12     // essentials tile, card, settings group
        static let xl: CGFloat = 16     // dialog, toast
        static let xxl: CGFloat = 24    // command palette

        static func shape(_ radius: CGFloat) -> RoundedRectangle {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
        }
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24

        static let sidebarInset: CGFloat = 8
        static let rowGap: CGFloat = 2
        static let sectionGap: CGFloat = 10
        static let rowPadding: CGFloat = 8
        static let folderIndent: CGFloat = 20
    }

    // MARK: - Size

    enum Size {
        static let row: CGFloat = 32
        static let iconButton: CGFloat = 28
        static let favicon: CGFloat = 16
        static let essentialsTile: CGFloat = 44
        static let urlBar: CGFloat = 32
        static let navRow: CGFloat = 28
        static let bottomBar: CGFloat = 40
    }

    // MARK: - Type

    enum Font {
        static let hero = SwiftUI.Font.system(size: 48, weight: .semibold)        // empty-state glyphs only
        static let display = SwiftUI.Font.system(size: 28, weight: .semibold)     // empty-state titles
        static let titleLarge = SwiftUI.Font.system(size: 20, weight: .semibold)  // panel titles
        static let heading = SwiftUI.Font.system(size: 17, weight: .semibold)     // settings pane title, dialog title
        static let title = SwiftUI.Font.system(size: 15, weight: .semibold)       // palette input, toast title
        static let label = SwiftUI.Font.system(size: 13, weight: .semibold)       // space name, folder name
        static let body = SwiftUI.Font.system(size: 13, weight: .medium)          // tab title, menu item, settings row
        static let bodyRegular = SwiftUI.Font.system(size: 13, weight: .regular)  // paragraphs, descriptions
        static let secondary = SwiftUI.Font.system(size: 12, weight: .medium)     // URL bar, popup button
        static let caption = SwiftUI.Font.system(size: 11, weight: .medium)       // counts, shortcuts, subtitles
        static let captionStrong = SwiftUI.Font.system(size: 11, weight: .semibold) // section headers
        static let micro = SwiftUI.Font.system(size: 9, weight: .semibold)        // badges only
    }

    // MARK: - Motion

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.12)      // hover, press
        static let standard = Animation.smooth(duration: 0.22)    // selection, reveal, fold
        static let spring = Animation.bouncy(duration: 0.3)       // palette, dialog, toast
    }

    // MARK: - Surface

    enum Surface {
        static let fill = Color.primary.opacity(0.045)           // hover, URL bar, idle tile
        static let fillPressed = Color.primary.opacity(0.08)
        static let hairline = Color.primary.opacity(0.08)
        static let raised = Color(nsColor: .controlBackgroundColor) // active row, active tile
    }

    // MARK: - Elevation

    enum Elevation {
        case raised    // hairline + tight shadow: active row, tile, settings group
        case floating  // menu, palette, toast, dialog, popover
    }
}

// MARK: - View helpers

private struct NookElevationModifier: ViewModifier {
    let level: NookDesign.Elevation

    func body(content: Content) -> some View {
        switch level {
        case .raised:
            content.shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        case .floating:
            content
                .shadow(color: .black.opacity(0.16), radius: 32, y: 12)
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        }
    }
}

extension View {
    func nookElevation(_ level: NookDesign.Elevation) -> some View {
        modifier(NookElevationModifier(level: level))
    }
}
