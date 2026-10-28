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
        /// The website frame. Concentric with the macOS window corner (about 22) across the 8pt inset.
        public static let page: CGFloat = 14

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
        public static let favoriteGap: CGFloat = 8     // between favorite tiles
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

    // MARK: - Browser Frame

    public enum Chrome {
        /// Window inset around web content (20px on Retina).
        public static let pageInset: CGFloat = 10
        public static let splitGap: CGFloat = pageInset
    }

    // MARK: - Size

    public enum Size {
        #if os(iOS)
        public static let row: CGFloat = 44
        #else
        public static let row: CGFloat = 32
        #endif
        public static let iconButton: CGFloat = 28
        public static let favoriteTile: CGFloat = 53   // a favorite tile's height; four are square at the default sidebar width
        public static let favoriteBorder: CGFloat = 2  // the selected favorite's edge
        public static let favoriteGlowScale: CGFloat = 2   // pixels per point of the blurred favicon behind a tile
        public static let favoriteGlowBlur: CGFloat = 0.25 // its blur radius as a fraction of the tile
        public static let themeKnob: CGFloat = 56      // the theme editor's noise knob
        public static let favicon: CGFloat = 16
        public static let essentialsTile: CGFloat = 44
        public static let essentialsFavicon: CGFloat = 20
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
        public static let chromeControl: CGFloat = 36  // title row, URL bar and search field height
        public static let pipSkip: CGFloat = 48        // PiP skip buttons, as in the system PiP window
        public static let pipPlay: CGFloat = 64        // PiP play/pause, as in the system PiP window
        public static let pipScrub: CGFloat = 4        // PiP scrubber track
        public static let spaceTarget: CGFloat = 32    // space switcher button
        public static let libraryList: CGFloat = 420   // preferred width of the library's History and Downloads
        public static let librarySpaces: CGFloat = 840 // ...and of its Spaces page
        public static let libraryMin: CGFloat = 417    // narrowest the library gets, whatever the window
        public static let libraryEdgeGap: CGFloat = 56 // window width the library leaves uncovered

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

    /// Sidebar navigation/footer controls, sized independently of inline row actions.
    public enum SidebarChrome {
        /// Resize indicator colors for a space with no custom palette.
        public static let defaultResizeLight = Color(.sRGB, red: 130 / 255, green: 149 / 255, blue: 247 / 255)
        public static let defaultResizeDark = Color(.sRGB, red: 145 / 255, green: 153 / 255, blue: 172 / 255)
        public static let icon: CGFloat = 15
        public static let button: CGFloat = 30
        public static let gap: CGFloat = 2
        public static let trafficLightsInset: CGFloat = 76
        public static let footerSideReserve: CGFloat = 66
    }

    /// Sidebar tab cards. Keep these separate from general chrome/control sizing.
    public enum Tab {
        public static let height: CGFloat = 36
        public static let verticalInset: CGFloat = 2
        public static let stride: CGFloat = height + verticalInset * 2
        public static let radius: CGFloat = 12
        public static let font = SwiftUI.Font.system(size: 14, weight: .regular)
        public static let pressScale: CGFloat = 0.985
        public static let dragScale: CGFloat = 1.025
        public static let dragOpacity: Double = 0.96
        public static let previewPadding: CGFloat = 12
        public static let liftShadowRadius: CGFloat = 8
        public static let liftShadowY: CGFloat = 3
        public static let liftShadowOpacity: Double = 0.20
        public static let dropIndicatorHeight: CGFloat = 2
        public static let dropIndicatorDot: CGFloat = 6
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
        public static let mono = SwiftUI.Font.system(size: 12, weight: .regular, design: .monospaced) // developer bar address
    }

    // MARK: - Motion

    public enum Motion {
        public static let tabReorder = Animation.easeOut(duration: 0.10)
        public static let tabClose = Animation.easeOut(duration: 0.20)
        public static let tabLandingDuration: TimeInterval = 0.10
        public static let quick = Animation.easeOut(duration: 0.12)      // hover, press
        public static let standardDuration: TimeInterval = 0.22          // `standard`, for AppKit animations
        public static let standard = Animation.smooth(duration: standardDuration)    // selection, reveal, fold
        public static let settle = Animation.smooth(duration: 0.6)       // the separator wave rising and flattening
        public static let wavePeriod: TimeInterval = 1.6                 // seconds for the wave to travel one cycle
        public static let flight = Animation.easeIn(duration: 0.6)       // a download flying from the page to its button
        public static let spring = Animation.snappy(duration: 0.3)      // palette, dialog, toast, drag reorder, gesture-tracked motion
        public static let pageSettle = Animation.spring(response: 0.25, dampingFraction: 1)  // the space pager's settle, so the dots land with the pages
        public static let librarySpring = Spring(response: 0.25, dampingRatio: 1)   // library open, close and release, the pager's spring
        public static let libraryRubberBand: CGFloat = 0.55              // resistance past fully open
        public static let libraryVelocityWindow: TimeInterval = 0.1      // swipe samples older than this are dropped from the velocity
        public static let swipeAxisLock: CGFloat = 10                    // points of travel before a swipe commits to an axis
        public static let swipeIdleTimeout: TimeInterval = 1             // a tracked swipe with no event this long is over
    }

    // MARK: - Surface

    public enum Surface {
        public static let fill = Color.primary.opacity(0.045)           // hover, idle tile
        public static let fillPressed = Color.primary.opacity(0.08)
        public static let tintOpacity: Double = 0.18                       // accent-tinted control: chosen chip, own chat message
        public static let mediaScrim = Color.black.opacity(0.35)           // controls over video
        public static let hairline = Color.primary.opacity(0.08)
        public static let unloadedOpacity: Double = 0.55
        /// A selected favorite tile's fill, as Arc draws it: white, halved in an inactive window.
        public static func favoriteSelectedFill(dark: Bool, dimmed: Bool) -> Color {
            Color.white.opacity((dark ? 0.45 : 0.8) * (dimmed ? 0.5 : 1))
        }
        /// Opacity of the blurred favicon behind a favorite tile.
        public static func favoriteGlowOpacity(dark: Bool, hovered: Bool, dimmed: Bool) -> Double {
            if dimmed { return 0 }
            return dark ? (hovered ? 0.3 : 0.2) : (hovered ? 0.1 : 0)
        }
        public static let favoriteDimmedBorderOpacity: Double = 0.2
        public static let dropBorderIdle = Color.secondary.opacity(0.3)    // dashed empty-state drop target
        public static let dropBorderActive = Color.primary.opacity(0.4)    // dashed drop target while dragging
        /// Destructive action fill. Kept at the value the dialog buttons shipped with.
        public static let danger = Color(hex: "#F60000")
        public static let scrim = Color.black.opacity(0.4)                 // modal dimming behind a dialog
        public static let privateTint = Color(red: 0.36, green: 0.22, blue: 0.62).opacity(0.38) // private window chrome
        /// The neutral accent a private window's chrome uses in place of a space's. Keep in step
        /// with `SpaceGradient.incognito`, which is the persisted form of the same color.
        public static let incognitoAccent = Color(hex: "#8E8E93")
        /// The Agent space's fixed identity, amber to magenta: its chrome, switcher icon, and the
        /// frame around its pages. No space accent comes close, so it never reads as a user space.
        public static let agentGradient = LinearGradient(
            colors: [Color(hex: "#FFB000"), Color(hex: "#FF5A1F"), Color(hex: "#E5177E")],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        public static let agentChromeOpacity: Double = 0.45   // over the sidebar's own background
        public static let agentIconInactiveOpacity: Double = 0.4  // switcher icon while another space is open
        /// Onboarding's fixed backdrop: the app icon's forest green as a soft mesh, lightest at the
        /// top left. The stages draw white text on it, so it stays dark in either appearance.
        public static let onboardingBackdrop = MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.6, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
            colors: [
                Color(hex: "#6B8F72"), Color(hex: "#2C5242"), Color(hex: "#1D3A2F"),
                Color(hex: "#2F5A47"), Color(hex: "#23463A"), Color(hex: "#16302A"),
                Color(hex: "#13261E"), Color(hex: "#0F1F19"), Color(hex: "#0A1612"),
            ])
        public static let grainOpacity: Double = 0.08         // film grain over a fixed backdrop
        public static let themeGrainOpacity: Double = 0.4     // a space theme's noise at the knob's maximum
        /// A space theme's color over the blurred desktop: mostly see-through at the slider's
        /// left end, nearly solid at its right.
        public static func themeTintOpacity(intensity: Double) -> Double { 0.3 + 0.62 * intensity }
        public static let agentFrameWidth: CGFloat = 3        // frame around the Agent space's page

        #if os(macOS)
        public static let windowBackground = Color(nsColor: .windowBackgroundColor)
        public static let raised = Color(nsColor: .controlBackgroundColor) // floating cards, active tile
        /// Link preview cards: near black in dark appearance and white in light, as Arc's are, so
        /// the photo and text pop instead of sitting on a gray card.
        public static let previewCard = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.06, alpha: 1) : .white
        })
        /// The chosen row, as Arc draws it: white laid over the space's color, soft in dark
        /// appearance and near solid in light, so the tint still shows through.
        public static let selection = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.14)
                : NSColor.white.withAlphaComponent(0.72)
        })
        #else
        public static let windowBackground = Color(uiColor: .systemBackground)
        public static let raised = Color(uiColor: .secondarySystemBackground) // floating cards, active tile
        public static let selection = Color.primary.opacity(0.1)
        public static let previewCard = Color(uiColor: .systemBackground)
        #endif

        /// Sidebar/window chrome fill: the space accent fading to the system window background.
        /// The top stop is a tint, not the raw accent, so it reads as light/washed out for every
        /// color. Inactive windows blend further toward that background, approximating the dimming
        /// NSVisualEffectView.followsWindowActiveState used to give the old blur for free.
        public static func containerGradient(accent: Color, isActive: Bool) -> LinearGradient {
            let end = windowBackground
            let topBlend = isActive ? 0.55 : 0.8
            #if os(macOS)
            // Blend per appearance: `blended` freezes `.windowBackgroundColor` to whatever
            // appearance is current when the body runs, which flips the top light/dark.
            let base = NSColor(accent)
            let top = Color(nsColor: NSColor(name: nil) { appearance in
                var color = base
                appearance.performAsCurrentDrawingAppearance {
                    color = base.blended(withFraction: topBlend, of: .windowBackgroundColor) ?? base
                }
                return color
            })
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
            // Raised only. A 2pt shadow hugs the shape and reads as a dark stroke, which a
            // floating card does not want: `nookFloatingSurface` draws its own hairline.
            .shadow(color: .black.opacity(level == .raised ? 0.05 : 0), radius: level == .raised ? 2 : 0, y: level == .raised ? 1 : 0)
    }
}

public extension View {
    func nookElevation(_ level: NookDesign.Elevation) -> some View {
        modifier(NookElevationModifier(level: level))
    }
}
