import SceneKit
import UIKit

enum MoteMotion { case drift, rise, fall }

/// A set for the cast: floor, backdrop, light, the ring under the feet, floating motes and a few props.
struct StageSpec: Identifiable {
    let id: String
    let name: String
    let free: Bool
    let background: UIColor
    let floor: () -> UIImage
    /// Size of one floor texture tile in metres.
    var floorTile: Float = 0.032
    let wall: () -> UIImage
    let ring: UIColor
    let mote: UIColor
    let motes: MoteMotion
    let key: UIColor
    var keyIntensity: CGFloat = 1100
    let ambient: UIColor
    var ambientIntensity: CGFloat = 380
    /// Light shaft from above the character.
    var shaft: Bool = false
    /// Props around the character in ground space (character units, y up, the backdrop toward -z).
    let props: (SCNNode) -> Void
}

enum Stages {
    static let all: [StageSpec] = [studio, garden, rooftop, tide, winter, library]
    static func spec(_ id: String) -> StageSpec { all.first { $0.id == id } ?? studio }

    static let studio = StageSpec(
        id: "studio", name: String(localized: "Holo Studio"), free: true, background: UIColor(hex: 0x05070E),
        floor: { Tex.dots(bg: UIColor(hex: 0x0A1222), dot: UIColor(hex: 0x5FE1FF, alpha: 0.55), lines: UIColor(hex: 0x5FE1FF, alpha: 0.06)) },
        wall: { Tex.studioWall() }, ring: UIColor(hex: 0x5FE1FF), mote: UIColor(hex: 0x8FEAFF), motes: .drift,
        key: UIColor(hex: 0xE6F4FF), ambient: UIColor(hex: 0x6E86B8), shaft: true) { g in
        // Two slim holo pillars at the back corners.
        for sx: Float in [-1, 1] {
            part(box(0.04, 1.4, 0.04, 0.01), Mat.glow(UIColor(hex: 0x5FE1FF), intensity: 0.9), g, at: v(sx * 1.25, 0.7, -0.9), shadow: false)
        }
    }

    static let garden = StageSpec(
        id: "garden", name: String(localized: "Paper Garden"), free: true, background: UIColor(hex: 0xF4E3CB),
        floor: { Tex.paper(UIColor(hex: 0xE9D9C2), fibre: UIColor(hex: 0xC9AE8A)) }, wall: { Tex.gardenWall() },
        ring: UIColor(hex: 0xFFB74D), mote: UIColor(hex: 0xFF9EB5), motes: .fall,
        key: UIColor(hex: 0xFFF1DE), keyIntensity: 750, ambient: UIColor(hex: 0xFFE2C2), ambientIntensity: 260) { g in
        let petals: [UInt32] = [0xFF8FA3, 0xFFC857, 0xA0C4FF, 0xFFADAD, 0xC3A6FF]
        let spots: [(Float, Float, Float)] = [(-0.9, -0.4, 0.55), (-0.62, -0.75, 0.42), (0.8, -0.55, 0.6), (1.05, -0.2, 0.38), (0.5, -0.9, 0.48), (-1.15, 0.1, 0.35)]
        for (i, s) in spots.enumerated() {
            let f = SCNNode()
            f.position = v(s.0, 0, s.1)
            g.addChildNode(f)
            part(cyl(0.012, CGFloat(s.2)), Mat.clay(UIColor(hex: 0x4F8E52)), f, at: v(0, s.2 / 2, 0))
            let head = SCNNode()
            head.position = v(0, s.2, 0)
            head.eulerAngles = v(-0.3, Float(i), 0)
            f.addChildNode(head)
            let pm = Mat.clay(UIColor(hex: petals[i % petals.count]), rough: 0.95)
            pm.isDoubleSided = true
            for k in 0..<6 {
                let a = Float(k) / 6 * 2 * .pi
                part(sphere(0.06, seg: 12), pm, head, at: v(cos(a) * 0.07, 0, sin(a) * 0.07), scale: v(1.3, 0.18, 0.8), rot: v(0, -a, 0))
            }
            part(sphere(0.035, seg: 12), Mat.clay(UIColor(hex: 0xFFE08A)), head)
        }
        for k in 0..<9 {
            let x = Float(k % 3) * 0.7 - 0.7 + Float(k) * 0.05, z = -0.2 - Float(k / 3) * 0.3
            part(cone(0, 0.06, 0.18), Mat.clay(UIColor(hex: 0x6FA862), rough: 0.9), g, at: v(x * 1.4, 0.09, z), rot: v(0, 0, Float(k % 2) * 0.2 - 0.1))
        }
    }

    static let rooftop = StageSpec(
        id: "rooftop", name: String(localized: "Night Rooftop"), free: true, background: UIColor(hex: 0x080B20),
        floor: { Tex.tiles(UIColor(hex: 0x6A3A33), UIColor(hex: 0x5B312C), grout: UIColor(hex: 0x2A1714)) }, floorTile: 0.04,
        wall: { Tex.rooftopWall() }, ring: UIColor(hex: 0xFFB45C), mote: UIColor(hex: 0xFFD27A), motes: .drift,
        key: UIColor(hex: 0xB9C6FF), keyIntensity: 700, ambient: UIColor(hex: 0x3B4680), ambientIntensity: 300) { g in
        let pole = Mat.clay(UIColor(hex: 0x2B2B33), rough: 0.5, metal: 0.5)
        let poles: [SCNVector3] = [v(-1.3, 0, -0.7), v(1.3, 0, -0.7)]
        for p in poles { part(cyl(0.02, 1.5), pole, g, at: v(p.x, 0.75, p.z)) }
        // A sagging string of warm bulbs between the poles.
        let n = 11
        for i in 0..<n {
            let u = Float(i) / Float(n - 1)
            let x = -1.3 + 2.6 * u
            let y = 1.45 - 0.35 * (1 - pow(2 * u - 1, 2))
            part(sphere(0.035, seg: 12), Mat.glow(UIColor(hex: 0xFFC56B), intensity: 2.2), g, at: v(x, y, -0.7), shadow: false)
        }
        part(box(0.32, 0.5, 0.32, 0.02), Mat.clay(UIColor(hex: 0x8A4B3C), rough: 0.9), g, at: v(-0.95, 0.25, -0.45))
        part(box(0.36, 0.05, 0.36, 0.01), Mat.clay(UIColor(hex: 0x5B312C)), g, at: v(-0.95, 0.52, -0.45))
    }

    static let tide = StageSpec(
        id: "tide", name: String(localized: "Tide Pool"), free: false, background: UIColor(hex: 0x0A3448),
        floor: { Tex.sand() }, floorTile: 0.05, wall: { Tex.tideWall() }, ring: UIColor(hex: 0x7FF5E0),
        mote: UIColor(hex: 0xDFFBFF), motes: .rise, key: UIColor(hex: 0xC9F4FF), keyIntensity: 1000,
        ambient: UIColor(hex: 0x3A8FA8), ambientIntensity: 500, shaft: true) { g in
        let star = Mat.clay(UIColor(hex: 0xFF8A5C), rough: 0.8)
        let s = SCNNode()
        s.position = v(0.85, 0.02, -0.25)
        g.addChildNode(s)
        for k in 0..<5 {
            let a = Float(k) / 5 * 2 * .pi
            part(capsule(0.035, 0.2), star, s, at: v(cos(a) * 0.08, 0, sin(a) * 0.08), rot: v(0, -a, .pi / 2))
        }
        part(cone(0, 0.09, 0.2), Mat.clay(UIColor(hex: 0xF3E1C8), rough: 0.4), g, at: v(-0.9, 0.06, -0.3), rot: v(0, 0, 1.2))
        for k in 0..<4 {
            let weed = SCNNode()
            weed.position = v(-1.2 + Float(k) * 0.18, 0, -0.75 + Float(k % 2) * 0.1)
            g.addChildNode(weed)
            for j in 0..<6 {
                part(sphere(0.045, seg: 10), Mat.clay(UIColor(hex: 0x2F8F6B), rough: 0.7), weed,
                     at: v(sin(Float(j) * 0.9 + Float(k)) * 0.04, Float(j) * 0.09 + 0.05, 0), scale: v(1, 1.6, 0.6))
            }
        }
    }

    static let winter = StageSpec(
        id: "winter", name: String(localized: "First Snow"), free: false, background: UIColor(hex: 0xD6E3F0),
        floor: { Tex.snow() }, floorTile: 0.04, wall: { Tex.winterWall() }, ring: UIColor(hex: 0x9FD1FF),
        mote: UIColor.white, motes: .fall, key: UIColor(hex: 0xF4F8FF), keyIntensity: 750,
        ambient: UIColor(hex: 0xBFD3EA), ambientIntensity: 280) { g in
        let pine = Mat.clay(UIColor(hex: 0x2F6B4F), rough: 0.85)
        let snowM = Mat.clay(.white, rough: 0.95)
        let trees: [(Float, Float, Float)] = [(-1.0, -0.6, 1.0), (-1.3, -0.2, 0.7), (1.1, -0.65, 1.15), (0.85, -0.95, 0.75)]
        for t in trees {
            let n = SCNNode()
            n.position = v(t.0, 0, t.1)
            n.scale = v(t.2, t.2, t.2)
            g.addChildNode(n)
            part(cyl(0.035, 0.15), Mat.clay(UIColor(hex: 0x5A3E2B)), n, at: v(0, 0.07, 0))
            for k in 0..<3 {
                let y = 0.2 + Float(k) * 0.17, r = CGFloat(0.26 - Double(k) * 0.06)
                part(cone(0, r, 0.26), pine, n, at: v(0, y, 0))
                part(cone(0, r * 0.55, 0.1), snowM, n, at: v(0, y + 0.09, 0), shadow: false)
            }
        }
    }

    static let library = StageSpec(
        id: "library", name: String(localized: "Lamp Library"), free: false, background: UIColor(hex: 0x22160F),
        floor: { Tex.planks(UIColor(hex: 0x8A5A3B), line: UIColor(hex: 0x5C3A25)) }, floorTile: 0.06,
        wall: { Tex.libraryWall() }, ring: UIColor(hex: 0xFFC56B), mote: UIColor(hex: 0xFFE2B0), motes: .drift,
        key: UIColor(hex: 0xFFE0B5), keyIntensity: 1000, ambient: UIColor(hex: 0x7A5238), ambientIntensity: 420) { g in
        let colors: [UInt32] = [0x8C2F39, 0x2E5E4E, 0x2B4C7E, 0xC9A227]
        for (i, c) in colors.enumerated() {
            part(box(0.42, 0.07, 0.3, 0.01), Mat.clay(UIColor(hex: c), rough: 0.7), g,
                 at: v(-0.95, 0.035 + Float(i) * 0.072, -0.35), rot: v(0, Float(i) * 0.15 - 0.2, 0))
        }
        let lamp = SCNNode()
        lamp.position = v(1.0, 0, -0.45)
        g.addChildNode(lamp)
        let brass = Mat.clay(UIColor(hex: 0xC9A227), rough: 0.3, metal: 0.9)
        part(cyl(0.12, 0.03), brass, lamp, at: v(0, 0.015, 0))
        part(cyl(0.015, 0.7), brass, lamp, at: v(0, 0.36, 0))
        part(cone(0.1, 0.22, 0.18), Mat.clay(UIColor(hex: 0x2E5E4E), rough: 0.5), lamp, at: v(0, 0.74, 0))
        part(sphere(0.06, seg: 12), Mat.glow(UIColor(hex: 0xFFE2A8), intensity: 2.5), lamp, at: v(0, 0.66, 0), shadow: false)
    }
}
