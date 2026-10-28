import Foundation

@main
struct SpaceThemeArcRulesCheck {
    static func main() throws {
        precondition(SpaceTheme.hues(key: 10, count: 1, wheel: .analogous) == [10])
        precondition(SpaceTheme.hues(key: 10, count: 2, wheel: .analogous) == [10, 50])
        precondition(SpaceTheme.hues(key: 10, count: 2, wheel: .complementary) == [10, 190])
        precondition(SpaceTheme.hues(key: 10, count: 3, wheel: .analogous) == [10, 50, 330])
        precondition(SpaceTheme.hues(key: 10, count: 3, wheel: .complementary) == [10, 160, 220])
        precondition(SpaceTheme.hues(key: 0, count: 4, wheel: .analogous) == [0, 90, 180, 270])

        precondition(SpaceTheme.lightnessRange(forced: .light) == 0.575...0.97)
        precondition(SpaceTheme.lightnessRange(forced: .dark) == 0.01...0.425)
        precondition(SpaceTheme.clampLightness(0.2, forced: .light) == 0.575)
        precondition(SpaceTheme.clampLightness(0.99, forced: .light) == 0.97)
        precondition(SpaceTheme.clampLightness(0.9, forced: .dark) == 0.425)
        precondition(SpaceTheme.clampLightness(0.3, forced: .dark) == 0.3)

        // A theme saved by PR 402: no wheel, overlay or count; two free points.
        let old = #"{"points":[{"x":0.9,"y":0.5},{"x":0.5,"y":0.1}],"mode":"dark","intensity":0.4,"grain":0.3}"#
        let theme = try JSONDecoder().decode(SpaceTheme.self, from: Data(old.utf8))
        precondition(theme.wheel == .analogous && theme.overlay == .grain)
        precondition(theme.colorCount == 2 && theme.points.count == 2)
        precondition(theme.points[0] == SpaceTheme.Point(x: 0.9, y: 0.5))
        precondition(abs(theme.points[1].hue - 40) < 1e-6)
        precondition(theme.resolve(systemDark: true).stops.count == 2)

        // Companions follow the key, and the count is 1...3.
        var t = SpaceTheme(points: [.init(hue: 100, saturation: 0.8)], wheel: .complementary, colorCount: 3)
        precondition(t.points.count == 3 && abs(t.points[1].hue - 250) < 1e-6 && abs(t.points[2].hue - 310) < 1e-6)
        t.points[0] = .init(hue: 200, saturation: 0.8)
        precondition(abs(t.points[1].hue - 350) < 1e-6)
        t.colorCount = 9
        precondition(t.colorCount == 3)
        t.colorCount = 0
        precondition(t.colorCount == 1 && t.points.count == 1)

        // Presets arrive in Display P3: grays land on the neutral center, a saturated red keeps its hue.
        precondition(SpaceTheme.Point(rgb: ThemeRGB(displayP3: 0.5, 0.5, 0.5)).saturation < 0.01)
        let red = SpaceTheme.Point(rgb: ThemeRGB(displayP3: 0.9, 0.2, 0.2))
        precondition(red.saturation > 0.5 && abs(red.hue - 29) < 15)

        // Favorite tiles reproduce what was measured in Arc on a #B1DAEA sidebar.
        let tiles = SpaceTheme.tileColors(chrome: ThemeRGB(hex: "#B1DAEA")!, dark: false)
        func near(_ c: ThemeRGB, _ hex: String, _ tolerance: Double) -> Bool {
            let e = ThemeRGB(hex: hex)!
            return max(abs(c.r - e.r), abs(c.g - e.g), abs(c.b - e.b)) * 255 <= tolerance
        }
        precondition(near(tiles.fill, "#A7CEDD", 2))
        precondition(near(tiles.selectedFill, "#D0E6F1", 4))
        precondition(near(tiles.selectedBorder, "#A6BFC8", 9))
        let darkTiles = SpaceTheme.tileColors(chrome: ThemeRGB(hex: "#2A3A44")!, dark: true)
        precondition(darkTiles.selectedFill.luminance > darkTiles.fill.luminance)

        // Round trip keeps the new fields.
        t.overlay = .tweed
        let back = try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(t))
        precondition(back == t)
        // Grey presets: nine tones give nine distinct chromes, split by the mode each picks.
        let greys = [1.0, 0.9, 0.8, 0.7, 0.5, 0.4, 0.2, 0.1, 0.0].map { v -> ThemeRGB in
            let theme = SpaceTheme(points: [.center], mode: v >= 0.6 ? .light : (v <= 0.4 ? .dark : .auto), tone: v)
            return theme.resolve(systemDark: false).stops[0]
        }
        precondition(Set(greys).count == 9)
        var toned = SpaceTheme(points: [.center], tone: 0.3)
        let tonedBack = try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(toned))
        precondition(tonedBack.tone == 0.3)
        toned.tone = nil
        let untoned = try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(toned))
        precondition(untoned.tone == nil)
        print("ok")
    }
}
