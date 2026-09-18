//
//  NookDesign.swift
//  Nook
//
//  Single source of truth for radii, spacing, sizes, type, motion,
//  surfaces, and elevation. No literal radius, font size, shadow, or
//  animation duration may appear in the UI layer outside this file.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum NookDesign {

    // MARK: - Radius (all continuous / squircle)

    public enum Radius {
        public static let xs: CGFloat = 4      // favicon
        public static let sm: CGFloat = 6      // icon button, menu item, small chip
        public static let md: CGFloat = 8      // tab row, nav button, URL bar
        public static let lg: CGFloat = 12     // essentials tile, card, settings group
        public static let xl: CGFloat = 16     // dialog, toast
        public static let xxl: CGFloat = 24    // command palette

        public static func shape(_ radius: CGFloat) -> RoundedRectangle {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
        }
    }

    // MARK: - Spacing

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let xl: CGFloat = 16
        public static let xxl: CGFloat = 20
        public static let xxxl: CGFloat = 24

        public static let sidebarInset: CGFloat = 8
        public static let rowGap: CGFloat = 2
        public static let sectionGap: CGFloat = 10
        public static let rowPadding: CGFloat = 8
        public static let folderIndent: CGFloat = 20
        public static let sidebarTop: CGFloat = 34     // clears the traffic lights when the sidebar is on the left
        public static let trafficLights: CGFloat = 78  // leading space the traffic lights take in the title row
        public static let titleFade: CGFloat = 20      // trailing fade on long row titles
    }

    // MARK: - Size

    public enum Size {
        #if os(iOS)
        public static let row: CGFloat = 44
        #else
        public static let row: CGFloat = 32
        #endif
        public static let iconButton: CGFloat = 28
        public static let favicon: CGFloat = 16
        public static let essentialsTile: CGFloat = 44
        public static let essentialsFavicon: CGFloat = 20
        public static let urlBar: CGFloat = 32
        public static let navRow: CGFloat = 28
        public static let bottomBar: CGFloat = 40
        public static let spaceIcon: CGFloat = 14      // switcher and header symbol
        public static let rowGlyph: CGFloat = 13       // inline glyphs in a row: audio, lock, chevron
        public static let rowButton: CGFloat = 20      // hover-only close/unload button in a row
        public static let hairlineWidth: CGFloat = 1   // 1pt rule
        public static let dropTail: CGFloat = 100      // empty drop target height below the last row
        public static let dialogMaxWidth: CGFloat = 500

        // Settings
        public static let settingsChip: CGFloat = 22           // tinted icon chip in the settings sidebar
        public static let settingsIcon: CGFloat = 32           // icon tile in a settings list row
        public static let statusDot: CGFloat = 8               // inline state dot in a settings row
        public static let fieldNarrow: CGFloat = 100           // numeric field, inline progress bar
        public static let textEditorHeight: CGFloat = 200      // multi-line editor, scrolling value box

        // Sheet scale, smallest to largest
        public static let sheetSmallWidth: CGFloat = 450       // single-record editor
        public static let sheetSmallHeight: CGFloat = 360
        public static let sheetMediumWidth: CGFloat = 600      // record detail
        public static let sheetMediumHeight: CGFloat = 500
        public static let sheetLargeWidth: CGFloat = 800       // data management browser
        public static let sheetLargeHeight: CGFloat = 600
    }

    // MARK: - Type

    public enum Font {
        public static let hero = SwiftUI.Font.system(size: 48, weight: .semibold)        // empty-state glyphs only
        public static let display = SwiftUI.Font.system(size: 28, weight: .semibold)     // empty-state titles
        public static let titleLarge = SwiftUI.Font.system(size: 20, weight: .semibold)  // panel titles
        public static let heading = SwiftUI.Font.system(size: 17, weight: .semibold)     // settings pane title, dialog title
        public static let title = SwiftUI.Font.system(size: 15, weight: .semibold)       // palette input, toast title
        public static let label = SwiftUI.Font.system(size: 13, weight: .semibold)       // space name, folder name
        public static let body = SwiftUI.Font.system(size: 13, weight: .medium)          // tab title, menu item, settings row
        public static let bodyRegular = SwiftUI.Font.system(size: 13, weight: .regular)  // paragraphs, descriptions
        public static let secondary = SwiftUI.Font.system(size: 12, weight: .medium)     // URL bar, popup button
        public static let caption = SwiftUI.Font.system(size: 11, weight: .medium)       // counts, shortcuts, subtitles
        public static let captionStrong = SwiftUI.Font.system(size: 11, weight: .semibold) // section headers
        public static let micro = SwiftUI.Font.system(size: 9, weight: .semibold)        // badges only
    }

    // MARK: - Motion

    public enum Motion {
        public static let quick = Animation.easeOut(duration: 0.12)      // hover, press
        public static let standard = Animation.smooth(duration: 0.22)    // selection, reveal, fold
        public static let spring = Animation.snappy(duration: 0.3)      // palette, dialog, toast, drag reorder, gesture-tracked motion
    }

    // MARK: - Surface

    public enum Surface {
        public static let fill = Color.primary.opacity(0.045)           // hover, URL bar, idle tile
        public static let fillPressed = Color.primary.opacity(0.08)
        public static let hairline = Color.primary.opacity(0.08)
        public static let unloadedOpacity: Double = 0.55
        public static let dropBorderIdle = Color.secondary.opacity(0.3)    // dashed empty-state drop target
        public static let dropBorderActive = Color.primary.opacity(0.4)    // dashed drop target while dragging
        public static let scrim = Color.black.opacity(0.4)                 // modal dimming behind a dialog
        public static let privateTint = Color(red: 0.36, green: 0.22, blue: 0.62).opacity(0.38) // private window chrome
        /// The neutral accent a private window's chrome uses in place of a space's. Keep in step
        /// with `SpaceGradient.incognito`, which is the persisted form of the same color.
        public static let incognitoAccent = Color(hex: "#8E8E93")

        #if os(macOS)
        public static let windowBackground = Color(nsColor: .windowBackgroundColor)
        public static let raised = Color(nsColor: .controlBackgroundColor) // active row, active tile
        #else
        public static let windowBackground = Color(uiColor: .systemBackground)
        public static let raised = Color(uiColor: .secondarySystemBackground) // active row, active tile
        #endif

        /// Sidebar/window chrome fill: the space accent fading to the system window background.
        /// The top stop is a tint, not the raw accent, so it reads as light/washed out for every
        /// color. Inactive windows blend further toward that background, approximating the dimming
        /// NSVisualEffectView.followsWindowActiveState used to give the old blur for free.
        public static func containerGradient(accent: Color, isActive: Bool) -> LinearGradient {
            let end = windowBackground
            let topBlend = isActive ? 0.55 : 0.8
            #if os(macOS)
            let top = Color(nsColor: NSColor(accent).blended(withFraction: topBlend, of: .windowBackgroundColor) ?? NSColor(accent))
            #else
            // ponytail: iOS not built yet; NSColor.blended(withFraction:of:) has no UIKit
            // equivalent. Flat opacity tint stands in until an iOS window chrome exists.
            let top = accent.opacity(1 - topBlend)
            #endif
            return LinearGradient(colors: [top, end], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Elevation

    public enum Elevation {
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

public extension View {
    func nookElevation(_ level: NookDesign.Elevation) -> some View {
        modifier(NookElevationModifier(level: level))
    }
}
