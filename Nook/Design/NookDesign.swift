//
//  NookDesign.swift
//  Nook
//
//  Single source of truth for radii, spacing, sizes, type, motion,
//  surfaces, and elevation. No literal radius, font size, shadow, or
//  animation duration may appear in the UI layer outside this file.
//

import SwiftUI
import AppKit

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
        static let sidebarTop: CGFloat = 34     // clears the traffic lights when the sidebar is on the left
        static let trafficLights: CGFloat = 78  // leading space the traffic lights take in the title row
        static let titleFade: CGFloat = 20      // trailing fade on long row titles
    }

    // MARK: - Size

    enum Size {
        static let row: CGFloat = 32
        static let iconButton: CGFloat = 28
        static let favicon: CGFloat = 16
        static let essentialsTile: CGFloat = 44
        static let essentialsFavicon: CGFloat = 20
        static let urlBar: CGFloat = 32
        static let navRow: CGFloat = 28
        static let bottomBar: CGFloat = 40
        static let spaceIcon: CGFloat = 14      // switcher and header symbol
        static let rowGlyph: CGFloat = 13       // inline glyphs in a row: audio, lock, chevron
        static let rowButton: CGFloat = 20      // hover-only close/unload button in a row
        static let hairlineWidth: CGFloat = 1   // 1pt rule
        static let dropTail: CGFloat = 100      // empty drop target height below the last row
        static let dialogMaxWidth: CGFloat = 500

        // Settings
        static let settingsChip: CGFloat = 22           // tinted icon chip in the settings sidebar
        static let settingsIcon: CGFloat = 32           // icon tile in a settings list row
        static let statusDot: CGFloat = 8               // inline state dot in a settings row
        static let fieldNarrow: CGFloat = 100           // numeric field, inline progress bar
        static let textEditorHeight: CGFloat = 200      // multi-line editor, scrolling value box

        // Sheet scale, smallest to largest
        static let sheetSmallWidth: CGFloat = 450       // single-record editor
        static let sheetSmallHeight: CGFloat = 360
        static let sheetMediumWidth: CGFloat = 600      // record detail
        static let sheetMediumHeight: CGFloat = 500
        static let sheetLargeWidth: CGFloat = 800       // data management browser
        static let sheetLargeHeight: CGFloat = 600
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
        static let spring = Animation.snappy(duration: 0.3)      // palette, dialog, toast, drag reorder, gesture-tracked motion
    }

    // MARK: - Surface

    enum Surface {
        static let fill = Color.primary.opacity(0.045)           // hover, URL bar, idle tile
        static let fillPressed = Color.primary.opacity(0.08)
        static let hairline = Color.primary.opacity(0.08)
        static let raised = Color(nsColor: .controlBackgroundColor) // active row, active tile
        static let unloadedOpacity: Double = 0.55
        static let dropBorderIdle = Color.secondary.opacity(0.3)    // dashed empty-state drop target
        static let dropBorderActive = Color.primary.opacity(0.4)    // dashed drop target while dragging
        static let scrim = Color.black.opacity(0.4)                 // modal dimming behind a dialog
        static let privateTint = Color(red: 0.36, green: 0.22, blue: 0.62).opacity(0.38) // private window chrome

        /// Sidebar/window chrome fill: the space accent fading to the system window background.
        /// The top stop is a tint, not the raw accent, so it reads as light/washed out for every
        /// color. Inactive windows blend further toward that background, approximating the dimming
        /// NSVisualEffectView.followsWindowActiveState used to give the old blur for free.
        static func containerGradient(accent: Color, isActive: Bool) -> LinearGradient {
            let end = Color(nsColor: .windowBackgroundColor)
            let topBlend = isActive ? 0.55 : 0.8
            let top = Color(nsColor: NSColor(accent).blended(withFraction: topBlend, of: .windowBackgroundColor) ?? NSColor(accent))
            return LinearGradient(colors: [top, end], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Elevation

    enum Elevation {
        case raised    // hairline + tight shadow: active row, tile, settings group
        case floating  // menu, palette, toast, dialog, popover
        case flat      // no shadow; for conditional elevation
    }
}

// MARK: - View helpers

private struct NookElevationModifier: ViewModifier {
    let level: NookDesign.Elevation

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(level == .floating ? 0.16 : 0), radius: level == .floating ? 32 : 0, y: level == .floating ? 12 : 0)
            .shadow(color: .black.opacity(level == .flat ? 0 : level == .floating ? 0.06 : 0.05), radius: level == .flat ? 0 : 2, y: level == .flat ? 0 : 1)
    }
}

extension View {
    func nookElevation(_ level: NookDesign.Elevation) -> some View {
        modifier(NookElevationModifier(level: level))
    }
}
