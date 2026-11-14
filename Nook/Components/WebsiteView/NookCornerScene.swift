// Licensed under GPL-3.0. See LICENSE.
//
//  NookCornerScene.swift
//  Nook
//
//  The reading corner on the error page: armchair, books, a floor lamp, candles and a little magic.
//  Drawn in a 300 x 200 space scaled to fit.
//

import SwiftUI

struct NookCornerScene: View {
    var lampLit: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !appearsActive)) { timeline in
            Canvas { context, size in
                let scale = min(size.width / 300, size.height / 200)
                context.translateBy(x: (size.width - 300 * scale) / 2, y: (size.height - 200 * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                let t = reduceMotion ? 1.3 : timeline.date.timeIntervalSinceReferenceDate
                draw(in: &context, time: t, palette: Palette(dark: colorScheme == .dark))
            }
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, time t: Double, palette p: Palette) {
        if lampLit {
            // Fades out inside the 300 x 200 space; Canvas clips anything past it.
            glow(&context, at: CGPoint(x: 236, y: 80), radius: 62, color: p.lampGlow)
        }
        let candles: [(x: CGFloat, height: CGFloat)] = [(46, 22), (58, 14), (92, 18)]
        for (i, candle) in candles.enumerated() {
            glow(&context, at: CGPoint(x: candle.x, y: 90 - candle.height), radius: 34 * flicker(t, i), color: p.candleGlow)
        }

        // Rug and floor shadow.
        context.fill(Path(ellipseIn: CGRect(x: 40, y: 172, width: 230, height: 22)), with: .color(p.rug))
        context.fill(Path(ellipseIn: CGRect(x: 112, y: 174, width: 98, height: 10)), with: .color(p.shadow))

        drawBookcase(&context, palette: p)
        for (i, candle) in candles.enumerated() {
            drawCandle(&context, x: candle.x, height: candle.height, flicker: flicker(t, i), sway: sway(t, i), palette: p)
        }
        drawArmchair(&context, palette: p)
        drawOpenBook(&context, palette: p)
        drawLamp(&context, palette: p)
        drawSparkles(&context, time: t, palette: p)
    }

    // MARK: - Pieces

    private func drawBookcase(_ c: inout GraphicsContext, palette p: Palette) {
        let frame = CGRect(x: 26, y: 90, width: 80, height: 90)
        c.fill(Path(roundedRect: frame, cornerRadius: 3), with: .color(p.wood))
        c.fill(Path(CGRect(x: 22, y: 88, width: 88, height: 5)), with: .color(p.woodDark))
        for (row, top) in [CGFloat(96), 136].enumerated() {
            c.fill(Path(CGRect(x: 31, y: top, width: 70, height: 36)), with: .color(p.woodDark))
            var x: CGFloat = 33
            let widths: [CGFloat] = row == 0 ? [7, 9, 6, 8, 7, 10, 6] : [9, 6, 8, 7, 9, 7, 8]
            for (i, w) in widths.enumerated() {
                let h: CGFloat = [30, 34, 28, 32, 29, 33, 31][(i + row * 3) % 7]
                let book = CGRect(x: x, y: top + 36 - h, width: w, height: h)
                c.fill(Path(roundedRect: book, cornerRadius: 1), with: .color(p.books[(i + row * 2) % p.books.count]))
                c.fill(Path(CGRect(x: x + 1, y: top + 36 - h + 5, width: w - 2, height: 1.5)), with: .color(p.bookBand))
                x += w + 0.8
                if x > 96 { break }
            }
        }
    }

    private func drawCandle(_ c: inout GraphicsContext, x: CGFloat, height: CGFloat, flicker f: Double, sway s: Double, palette p: Palette) {
        let top = 88 - height
        c.fill(Path(roundedRect: CGRect(x: x - 3.5, y: top, width: 7, height: height), cornerRadius: 1.5), with: .color(p.wax))
        c.fill(Path(CGRect(x: x - 0.4, y: top - 2.5, width: 0.8, height: 2.5)), with: .color(p.wick))

        let flameHeight = 9 * f
        let base = CGPoint(x: x, y: top - 1.5)
        let tip = CGPoint(x: x + s * 1.6, y: base.y - flameHeight)
        var flame = Path()
        flame.move(to: base)
        flame.addQuadCurve(to: tip, control: CGPoint(x: x - 4.2, y: base.y - flameHeight * 0.35))
        flame.addQuadCurve(to: base, control: CGPoint(x: x + 4.2, y: base.y - flameHeight * 0.35))
        c.fill(flame, with: .color(p.flameOuter))
        c.fill(Path(ellipseIn: CGRect(x: x - 1.3, y: base.y - flameHeight * 0.42, width: 2.6, height: flameHeight * 0.4)),
               with: .color(p.flameInner))
    }

    private func drawArmchair(_ c: inout GraphicsContext, palette p: Palette) {
        for legX in [CGFloat(126), 192] {
            c.fill(Path(roundedRect: CGRect(x: legX, y: 168, width: 5, height: 9), cornerRadius: 1.5), with: .color(p.woodDark))
        }
        c.fill(Path(roundedRect: CGRect(x: 128, y: 96, width: 66, height: 62), cornerRadius: 16), with: .color(p.chairDark))
        c.fill(Path(roundedRect: CGRect(x: 124, y: 138, width: 74, height: 32), cornerRadius: 7), with: .color(p.chair))
        c.fill(Path(roundedRect: CGRect(x: 134, y: 134, width: 54, height: 14), cornerRadius: 6), with: .color(p.cushion))
        for armX in [CGFloat(116), 190] {
            c.fill(Path(roundedRect: CGRect(x: armX, y: 124, width: 16, height: 46), cornerRadius: 8), with: .color(p.chair))
        }
        // A folded throw over the left arm.
        var throwPath = Path()
        throwPath.move(to: CGPoint(x: 117, y: 128))
        throwPath.addLine(to: CGPoint(x: 131, y: 126))
        throwPath.addLine(to: CGPoint(x: 133, y: 158))
        throwPath.addLine(to: CGPoint(x: 119, y: 162))
        throwPath.closeSubpath()
        c.fill(throwPath, with: .color(p.throwBlanket))
        for y in [CGFloat(136), 146] {
            c.fill(Path(CGRect(x: 119.5, y: y, width: 12, height: 1.5)), with: .color(p.throwStripe))
        }
    }

    private func drawOpenBook(_ c: inout GraphicsContext, palette p: Palette) {
        let spine = CGPoint(x: 198, y: 124)
        for side in [CGFloat(-1), 1] {
            var cover = Path()
            cover.move(to: spine)
            cover.addLine(to: CGPoint(x: spine.x + side * 13, y: spine.y - 3))
            cover.addLine(to: CGPoint(x: spine.x + side * 13, y: spine.y + 3))
            cover.addLine(to: CGPoint(x: spine.x, y: spine.y + 5))
            cover.closeSubpath()
            c.fill(cover, with: .color(p.books[3]))
            var page = Path()
            page.move(to: CGPoint(x: spine.x, y: spine.y - 1))
            page.addQuadCurve(to: CGPoint(x: spine.x + side * 12, y: spine.y - 4), control: CGPoint(x: spine.x + side * 6, y: spine.y - 6))
            page.addLine(to: CGPoint(x: spine.x + side * 12, y: spine.y + 1))
            page.addLine(to: CGPoint(x: spine.x, y: spine.y + 3))
            page.closeSubpath()
            c.fill(page, with: .color(p.page))
        }
    }

    private func drawLamp(_ c: inout GraphicsContext, palette p: Palette) {
        c.fill(Path(ellipseIn: CGRect(x: 224, y: 174, width: 24, height: 6)), with: .color(p.metal))
        c.fill(Path(CGRect(x: 235, y: 74, width: 2, height: 102)), with: .color(p.metal))
        var shade = Path()
        shade.move(to: CGPoint(x: 225, y: 52))
        shade.addLine(to: CGPoint(x: 247, y: 52))
        shade.addLine(to: CGPoint(x: 256, y: 78))
        shade.addLine(to: CGPoint(x: 216, y: 78))
        shade.closeSubpath()
        c.fill(shade, with: .color(lampLit ? p.shadeLit : p.shadeOff))
        if lampLit {
            c.fill(Path(ellipseIn: CGRect(x: 219, y: 75, width: 34, height: 6)), with: .color(p.flameInner.opacity(0.8)))
        }
    }

    private func drawSparkles(_ c: inout GraphicsContext, time t: Double, palette p: Palette) {
        let count = 5
        for i in 0..<count {
            let progress = (t / 4.8 + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
            let x = 198 + sin(progress * .pi * 2 + Double(i) * 1.7) * 7 + Double(i - 2) * 3
            let y = 118 - progress * 62
            let size = 2.2 + Double(i % 3) * 0.8
            c.opacity = sin(progress * .pi)
            c.fill(sparkle(at: CGPoint(x: x, y: y), size: size), with: .color(p.sparkle))
            c.opacity = 1
        }
    }

    // MARK: - Helpers

    private func glow(_ c: inout GraphicsContext, at center: CGPoint, radius: CGFloat, color: Color) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        c.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color, color.opacity(0)]), center: center, startRadius: 0, endRadius: radius))
    }

    /// Summed sines at unrelated rates, so no two candles pulse in step.
    private func flicker(_ t: Double, _ i: Int) -> Double {
        let phase = Double(i) * 2.13
        return 0.88 + 0.07 * sin(t * 7.3 + phase) + 0.04 * sin(t * 13.7 + phase * 1.9) + 0.03 * sin(t * 23.1 + phase * 0.7)
    }

    private func sway(_ t: Double, _ i: Int) -> Double {
        sin(t * 3.1 + Double(i) * 1.4) * 0.6 + sin(t * 8.9 + Double(i)) * 0.4
    }

    private func sparkle(at p: CGPoint, size s: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: p.x, y: p.y - s))
        path.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: p)
        return path
    }

    /// Afternoon in light mode, evening in dark mode.
    private struct Palette {
        let wood, woodDark, chair, chairDark, cushion, throwBlanket, throwStripe, rug, shadow: Color
        let books: [Color]
        let bookBand, page, wax, wick, flameOuter, flameInner, candleGlow: Color
        let metal, shadeLit, shadeOff, lampGlow, sparkle: Color

        init(dark: Bool) {
            func c(_ r: Double, _ g: Double, _ b: Double) -> Color {
                let k = dark ? 0.62 : 1
                return Color(red: r * k, green: g * k, blue: b * k)
            }
            wood = c(0.62, 0.43, 0.29)
            woodDark = c(0.45, 0.30, 0.20)
            chair = c(0.74, 0.40, 0.32)
            chairDark = c(0.64, 0.33, 0.27)
            cushion = c(0.80, 0.48, 0.38)
            throwBlanket = c(0.86, 0.78, 0.62)
            throwStripe = c(0.66, 0.50, 0.36)
            rug = c(0.86, 0.76, 0.62).opacity(dark ? 0.7 : 0.55)
            shadow = Color.black.opacity(dark ? 0.35 : 0.12)
            books = [c(0.52, 0.62, 0.50), c(0.84, 0.66, 0.32), c(0.55, 0.38, 0.52), c(0.33, 0.53, 0.56),
                     c(0.76, 0.45, 0.33), c(0.90, 0.84, 0.70), c(0.40, 0.45, 0.62)]
            bookBand = Color(red: 0.95, green: 0.82, blue: 0.48).opacity(dark ? 0.55 : 0.7)
            page = c(0.98, 0.95, 0.88)
            wax = c(0.96, 0.92, 0.82)
            wick = Color(white: 0.2)
            flameOuter = Color(red: 1.0, green: 0.68, blue: 0.24)
            flameInner = Color(red: 1.0, green: 0.93, blue: 0.68)
            candleGlow = Color(red: 1.0, green: 0.72, blue: 0.35).opacity(dark ? 0.45 : 0.28)
            metal = c(0.32, 0.29, 0.27)
            shadeLit = Color(red: 0.98, green: 0.86, blue: 0.62)
            shadeOff = c(0.74, 0.68, 0.58)
            lampGlow = Color(red: 1.0, green: 0.80, blue: 0.48).opacity(dark ? 0.42 : 0.3)
            sparkle = Color(red: 1.0, green: 0.90, blue: 0.62)
        }
    }
}
