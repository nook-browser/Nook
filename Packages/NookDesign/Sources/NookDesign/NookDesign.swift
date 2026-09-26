// Licensed under GPL-3.0. See LICENSE.
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
        #if os(iOS)
        // Depth 5 at 20 would eat 100 of a 390pt phone row.
        public static let folderIndent: CGFloat = 16
        #else
        public static let folderIndent: CGFloat = 20
        #endif
        public static let sidebarTop: CGFloat = 52     // the unified title band; the lights sit centred in it
        public static let trafficLights: CGFloat = 88  // leading space the traffic lights take in the title row
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
        public static let urlBar: CGFloat = 40
        public static let navRow: CGFloat = 28
        #if os(iOS)
        // The floating bar's control row. 50 clears the 44pt touch minimum with
        // room for the field's own inset.
        public static let bottomBar: CGFloat = 50
        #else
        public static let bottomBar: CGFloat = 40
        #endif
        public static let spaceIcon: CGFloat = 14      // switcher and header symbol
        public static let rowGlyph: CGFloat = 13       // inline glyphs in a row: audio, lock, chevron
        public static let rowButton: CGFloat = 20      // hover-only close/unload button in a row
        public static let cornerButton: CGFloat = 14   // button tucked into a tile corner, kept off the tile's centre
        public static let hairlineWidth: CGFloat = 1   // 1pt rule
        public static let loadBar: CGFloat = 2         // page load progress along the top of Peek and the mini window
        public static let waveAmplitude: CGFloat = 3   // peak of the separator's working wave
        public static let waveLength: CGFloat = 56     // one full cycle of that wave
        public static let dropTail: CGFloat = 100      // empty drop target height below the last row
        public static let dialogMaxWidth: CGFloat = 500
        public static let glassControl: CGFloat = 36   // sidebar glass controls, the size of a macOS 26 toolbar button
        // Narrowest sidebar: the lights (88), the history pill (110), the inset (8).
        public static let sidebarMin: CGFloat = 206

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
        public static let settle = Animation.smooth(duration: 0.6)       // the separator wave rising and flattening
        public static let wavePeriod: TimeInterval = 1.6                 // seconds for the wave to travel one cycle
        public static let flight = Animation.easeIn(duration: 0.6)       // a download flying from the page to its button
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
        /// Destructive action fill. Kept at the value the dialog buttons shipped with.
        public static let danger = Color(hex: "#F60000")
        public static let scrim = Color.black.opacity(0.4)                 // modal dimming behind a dialog
        public static let privateTint = Color(red: 0.36, green: 0.22, blue: 0.62).opacity(0.38) // private window chrome
        /// A subtle wash over the system window material when a Space tint is enabled.
        public static let windowTintOpacity = 0.12
        #if os(macOS)
        public static let windowBackground = Color(nsColor: .windowBackgroundColor)
        public static let raised = Color(nsColor: .controlBackgroundColor) // active row, active tile
        #else
        public static let windowBackground = Color(uiColor: .systemBackground)
        public static let raised = Color(uiColor: .secondarySystemBackground) // active row, active tile
        #endif

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
            // Raised only. A 2pt shadow hugs the shape and reads as a dark stroke, which a
            // floating glass layer does not want: the material defines its own edge.
            .shadow(color: .black.opacity(level == .raised ? 0.05 : 0), radius: level == .raised ? 2 : 0, y: level == .raised ? 1 : 0)
    }
}

public extension View {
    func nookElevation(_ level: NookDesign.Elevation) -> some View {
        modifier(NookElevationModifier(level: level))
    }
}
