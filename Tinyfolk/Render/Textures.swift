import UIKit

/// Procedural textures drawn with Core Graphics at launch: no image assets to license or ship.
enum Tex {
    private static func draw(_ size: CGSize, opaque: Bool = true, _ body: (CGContext, CGSize) -> Void) -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: f).image { body($0.cgContext, size) }
    }

    /// Tileable dot grid.
    static func dots(bg: UIColor, dot: UIColor, cell: CGFloat = 64, radius: CGFloat = 3.2, lines: UIColor? = nil) -> UIImage {
        draw(CGSize(width: cell * 4, height: cell * 4)) { c, s in
            bg.setFill(); c.fill(CGRect(origin: .zero, size: s))
            if let lines {
                lines.setStroke()
                c.setLineWidth(1)
                for i in 0...4 {
                    let p = CGFloat(i) * cell
                    c.move(to: CGPoint(x: p, y: 0)); c.addLine(to: CGPoint(x: p, y: s.height))
                    c.move(to: CGPoint(x: 0, y: p)); c.addLine(to: CGPoint(x: s.width, y: p))
                }
                c.strokePath()
            }
            dot.setFill()
            for i in 0..<4 { for j in 0..<4 {
                let x = CGFloat(i) * cell + cell / 2, y = CGFloat(j) * cell + cell / 2
                c.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            } }
        }
    }

    /// Radial glow, transparent outside (for additive discs and the ring's halo).
    static func glow(_ color: UIColor, inner: CGFloat = 0.0, size: CGFloat = 256) -> UIImage {
        draw(CGSize(width: size, height: size), opaque: false) { c, s in
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [color.cgColor, color.withAlphaComponent(0.35).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: cs, colors: colors, locations: [inner, 0.45, 1])!
            let ctr = CGPoint(x: s.width / 2, y: s.height / 2)
            c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: s.width / 2, options: [])
        }
    }

    /// Soft dark blob for contact shadows (multiplied onto the floor).
    static let contactShadow: UIImage = draw(CGSize(width: 256, height: 256), opaque: false) { c, s in
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [UIColor(white: 0, alpha: 0.55).cgColor, UIColor(white: 0, alpha: 0.18).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.5, 1])!
        let ctr = CGPoint(x: s.width / 2, y: s.height / 2)
        c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: s.width / 2, options: [])
    }

    /// Opacity mask (alpha) that fades a floor or wall out toward its edges.
    static let edgeFade: UIImage = draw(CGSize(width: 256, height: 256), opaque: false) { c, s in
        let cs = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: cs, colors: [UIColor.white.cgColor, UIColor.white.cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 0.55, 1])!
        let ctr = CGPoint(x: s.width / 2, y: s.height / 2)
        c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: s.width / 2, options: [])
    }

    /// Simple sky-to-floor gradient used as the lighting environment (soft reflections on glossy parts).
    static func environment(top: UIColor, bottom: UIColor) -> UIImage {
        draw(CGSize(width: 256, height: 128)) { c, s in vertical(c, s, top, bottom) }
    }

    /// Vertical gradient for light shafts (bright at the top, gone at the bottom).
    static func shaft(_ color: UIColor) -> UIImage {
        draw(CGSize(width: 8, height: 256), opaque: false) { c, s in
            let cs = CGColorSpaceCreateDeviceRGB()
            let g = CGGradient(colorsSpace: cs, colors: [color.withAlphaComponent(0.0).cgColor, color.withAlphaComponent(0.5).cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.15, 1])!
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: s.height), options: [])
        }
    }

    private static func vertical(_ c: CGContext, _ s: CGSize, _ top: UIColor, _ bottom: UIColor) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: cs, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: s.height), options: [])
    }

    private static func hills(_ c: CGContext, _ s: CGSize, base: CGFloat, amp: CGFloat, freq: CGFloat, phase: CGFloat, color: UIColor) {
        color.setFill()
        c.move(to: CGPoint(x: 0, y: s.height))
        var x: CGFloat = 0
        while x <= s.width {
            let y = base + sin(x / s.width * .pi * 2 * freq + phase) * amp + sin(x / s.width * .pi * 5.3 * freq + phase * 2) * amp * 0.3
            c.addLine(to: CGPoint(x: x, y: y))
            x += 4
        }
        c.addLine(to: CGPoint(x: s.width, y: s.height))
        c.closePath()
        c.fillPath()
    }

    /// Seeded random so walls look the same on every launch.
    private struct Seeded {
        var s: UInt64
        mutating func next() -> CGFloat {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((s >> 33) % 10_000) / 10_000
        }
    }

    // MARK: Walls (non-tiling, drawn once for the whole backdrop)

    static func studioWall() -> UIImage {
        draw(CGSize(width: 1024, height: 1024)) { c, s in
            vertical(c, s, UIColor(hex: 0x050811), UIColor(hex: 0x0C1630))
            UIColor(hex: 0x5FE1FF, alpha: 0.22).setFill()
            for i in 0..<16 { for j in 0..<16 {
                let x = CGFloat(i) * 64 + 32, y = CGFloat(j) * 64 + 32
                c.fillEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
            } }
            let cs = CGColorSpaceCreateDeviceRGB()
            let g = CGGradient(colorsSpace: cs, colors: [UIColor(hex: 0x5FE1FF, alpha: 0.28).cgColor, UIColor(hex: 0x5FE1FF, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 512, y: 980), startRadius: 0, endCenter: CGPoint(x: 512, y: 980), endRadius: 600, options: [])
        }
    }

    static func gardenWall() -> UIImage {
        draw(CGSize(width: 1024, height: 1024)) { c, s in
            vertical(c, s, UIColor(hex: 0xFCE9CF), UIColor(hex: 0xF6D7B0))
            UIColor(hex: 0xFFB36B, alpha: 0.9).setFill()
            c.fillEllipse(in: CGRect(x: 640, y: 210, width: 170, height: 170))
            // Paper layers, each with a soft shadow line for the cut-paper look.
            let layers: [(CGFloat, CGFloat, CGFloat, CGFloat, UInt32)] = [
                (560, 60, 1.3, 0.4, 0xB9D59B), (650, 55, 1.7, 2.1, 0x8FBF78), (760, 45, 1.1, 4.0, 0x6FA862), (880, 35, 2.3, 1.0, 0x4F8E52)]
            for l in layers {
                c.saveGState()
                c.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: UIColor(white: 0, alpha: 0.18).cgColor)
                hills(c, s, base: l.0, amp: l.1, freq: l.2, phase: l.3, color: UIColor(hex: l.4))
                c.restoreGState()
            }
        }
    }

    static func rooftopWall() -> UIImage {
        draw(CGSize(width: 1024, height: 1024)) { c, s in
            vertical(c, s, UIColor(hex: 0x070A22), UIColor(hex: 0x27305E))
            var r = Seeded(s: 42)
            for _ in 0..<220 {
                let x = r.next() * s.width, y = r.next() * s.height * 0.75, rad = 0.8 + r.next() * 2.2
                UIColor(white: 1, alpha: 0.35 + r.next() * 0.6).setFill()
                c.fillEllipse(in: CGRect(x: x, y: y, width: rad, height: rad))
            }
            UIColor(hex: 0xFFF3D6).setFill()
            c.fillEllipse(in: CGRect(x: 180, y: 150, width: 120, height: 120))
            UIColor(hex: 0x070A22, alpha: 0.9).setFill()
            c.fillEllipse(in: CGRect(x: 214, y: 132, width: 120, height: 120))
            // Distant rooftops with a few lit windows.
            var x: CGFloat = 0
            while x < s.width {
                let w = 50 + r.next() * 90, h = 120 + r.next() * 220
                UIColor(hex: 0x141936).setFill()
                c.fill(CGRect(x: x, y: s.height - h, width: w, height: h))
                for _ in 0..<Int(r.next() * 6) {
                    UIColor(hex: 0xFFC56B, alpha: 0.75).setFill()
                    c.fill(CGRect(x: x + 8 + r.next() * (w - 20), y: s.height - h + 16 + r.next() * (h - 40), width: 8, height: 10))
                }
                x += w + 6
            }
        }
    }

    static func tideWall() -> UIImage {
        draw(CGSize(width: 1024, height: 1024)) { c, s in
            vertical(c, s, UIColor(hex: 0x3FB4C9), UIColor(hex: 0x0A3A52))
            c.saveGState()
            c.setBlendMode(.screen)
            for i in 0..<7 {
                let x = CGFloat(i) * 160 + 40
                UIColor(white: 1, alpha: 0.08).setFill()
                c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x + 70, y: 0))
                c.addLine(to: CGPoint(x: x + 240, y: s.height)); c.addLine(to: CGPoint(x: x + 120, y: s.height))
                c.closePath(); c.fillPath()
            }
            c.restoreGState()
            hills(c, s, base: 900, amp: 30, freq: 1.4, phase: 0.6, color: UIColor(hex: 0x0E4C5E))
        }
    }

    static func winterWall() -> UIImage {
        draw(CGSize(width: 1024, height: 1024)) { c, s in
            vertical(c, s, UIColor(hex: 0xBFD6EE), UIColor(hex: 0xEEF4FA))
            hills(c, s, base: 690, amp: 50, freq: 1.2, phase: 1.2, color: UIColor(hex: 0xDCE7F2))
            var r = Seeded(s: 7)
            for _ in 0..<26 {
                let x = r.next() * s.width, base = 700 + r.next() * 120, h = 70 + r.next() * 110
                UIColor(hex: 0x8FA9C2, alpha: 0.7).setFill()
                c.move(to: CGPoint(x: x, y: base - h)); c.addLine(to: CGPoint(x: x + h * 0.32, y: base)); c.addLine(to: CGPoint(x: x - h * 0.32, y: base))
                c.closePath(); c.fillPath()
            }
            hills(c, s, base: 860, amp: 30, freq: 0.8, phase: 3.0, color: UIColor(hex: 0xF7FAFD))
        }
    }

    static func libraryWall() -> UIImage {
        draw(CGSize(width: 1024, height: 1024)) { c, s in
            UIColor(hex: 0x3A271C).setFill(); c.fill(CGRect(origin: .zero, size: s))
            var r = Seeded(s: 11)
            let palette: [UInt32] = [0x8C2F39, 0x2E5E4E, 0x2B4C7E, 0xC9A227, 0x6D4C7D, 0xB5651D, 0x405D3A, 0x7A1F2B]
            var y: CGFloat = 60
            while y < s.height - 40 {
                var x: CGFloat = 40
                while x < s.width - 40 {
                    let w = 16 + r.next() * 22, h = 120 + r.next() * 50
                    UIColor(hex: palette[Int(r.next() * CGFloat(palette.count)) % palette.count]).setFill()
                    c.fill(CGRect(x: x, y: y + 170 - h, width: w, height: h))
                    UIColor(white: 1, alpha: 0.18).setFill()
                    c.fill(CGRect(x: x + 3, y: y + 170 - h + 14, width: w - 6, height: 3))
                    x += w + 2
                }
                UIColor(hex: 0x24170F).setFill()
                c.fill(CGRect(x: 0, y: y + 170, width: s.width, height: 22))
                y += 200
            }
            let cs = CGColorSpaceCreateDeviceRGB()
            let g = CGGradient(colorsSpace: cs, colors: [UIColor(hex: 0xFFC56B, alpha: 0.25).cgColor, UIColor(hex: 0xFFC56B, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 512, y: 900), startRadius: 0, endCenter: CGPoint(x: 512, y: 900), endRadius: 700, options: [])
        }
    }

    // MARK: Floors (tileable)

    static func paper(_ base: UIColor, fibre: UIColor) -> UIImage {
        draw(CGSize(width: 256, height: 256)) { c, s in
            base.setFill(); c.fill(CGRect(origin: .zero, size: s))
            var r = Seeded(s: 3)
            fibre.setStroke()
            c.setLineWidth(0.7)
            for _ in 0..<160 {
                let x = r.next() * s.width, y = r.next() * s.height, a = r.next() * .pi, l = 4 + r.next() * 10
                c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l))
            }
            c.strokePath()
            fibre.withAlphaComponent(0.5).setFill()
            for i in 0..<4 { for j in 0..<4 {
                c.fillEllipse(in: CGRect(x: CGFloat(i) * 64 + 30, y: CGFloat(j) * 64 + 30, width: 4, height: 4))
            } }
        }
    }

    static func tiles(_ a: UIColor, _ b: UIColor, grout: UIColor) -> UIImage {
        draw(CGSize(width: 256, height: 256)) { c, s in
            grout.setFill(); c.fill(CGRect(origin: .zero, size: s))
            for i in 0..<4 { for j in 0..<4 {
                ((i + j) % 2 == 0 ? a : b).setFill()
                c.fill(CGRect(x: CGFloat(i) * 64 + 2, y: CGFloat(j) * 64 + 2, width: 60, height: 60))
            } }
        }
    }

    static func planks(_ base: UIColor, line: UIColor) -> UIImage {
        draw(CGSize(width: 256, height: 256)) { c, s in
            base.setFill(); c.fill(CGRect(origin: .zero, size: s))
            var r = Seeded(s: 5)
            for j in 0..<4 {
                let y = CGFloat(j) * 64
                UIColor(white: r.next() > 0.5 ? 1 : 0, alpha: 0.05).setFill()
                c.fill(CGRect(x: 0, y: y, width: s.width, height: 64))
                line.setFill()
                c.fill(CGRect(x: 0, y: y, width: s.width, height: 2))
                c.fill(CGRect(x: (CGFloat(j) * 97).truncatingRemainder(dividingBy: 256), y: y, width: 2, height: 64))
            }
        }
    }

    static func sand() -> UIImage {
        draw(CGSize(width: 256, height: 256)) { c, s in
            UIColor(hex: 0xE3CFA4).setFill(); c.fill(CGRect(origin: .zero, size: s))
            var r = Seeded(s: 9)
            for _ in 0..<900 {
                UIColor(white: r.next() > 0.5 ? 1 : 0.2, alpha: 0.12).setFill()
                c.fill(CGRect(x: r.next() * s.width, y: r.next() * s.height, width: 1.5, height: 1.5))
            }
            // Caustic web.
            UIColor(white: 1, alpha: 0.28).setStroke()
            c.setLineWidth(2.2)
            for i in 0..<6 {
                let y0 = CGFloat(i) * 44
                c.move(to: CGPoint(x: 0, y: y0))
                var x: CGFloat = 0
                while x <= s.width {
                    c.addLine(to: CGPoint(x: x, y: y0 + sin(x / 256 * .pi * 4 + CGFloat(i)) * 12))
                    x += 8
                }
            }
            c.strokePath()
        }
    }

    static func snow() -> UIImage {
        draw(CGSize(width: 256, height: 256)) { c, s in
            UIColor(hex: 0xF4F8FC).setFill(); c.fill(CGRect(origin: .zero, size: s))
            var r = Seeded(s: 13)
            for _ in 0..<240 {
                UIColor(hex: 0xBFD2E6, alpha: 0.35 + r.next() * 0.3).setFill()
                let rad = 1 + r.next() * 2.5
                c.fillEllipse(in: CGRect(x: r.next() * s.width, y: r.next() * s.height, width: rad, height: rad))
            }
        }
    }
}
