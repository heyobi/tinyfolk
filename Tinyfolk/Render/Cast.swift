import SceneKit
import UIKit

/// One member of the cast. All original designs built from simple shapes.
struct CharacterSpec: Identifiable {
    let id: String
    let name: String
    let free: Bool
    let style: DanceStyle
    /// Pitch of the little voice chirps (1 = middle).
    let voice: Float
    let tint: UIColor
    /// True for characters that hover instead of standing.
    var floats = false
    let build: (Rig) -> Void

    func makeRig() -> Rig {
        let r = Rig()
        build(r)
        return r
    }
}

enum Cast {
    static let all: [CharacterSpec] = [pim, juni, mossy, odette, cosmo, tuck, kumo, lumen]
    static func spec(_ id: String) -> CharacterSpec { all.first { $0.id == id } ?? pim }

    // MARK: Shared limbs

    private static func legs(_ r: Rig, _ c: UIColor, foot: UIColor, radius: CGFloat = 0.045, length: CGFloat = 0.13) {
        for leg in [r.legPlus, r.legMinus] {
            part(capsule(radius, length + radius * 2), Mat.clay(c), leg, at: v(0, -Float(length) * 0.55, 0))
            part(sphere(0.06), Mat.clay(foot, rough: 0.5), leg, at: v(0, -0.155, 0.025), scale: v(1, 0.55, 1.4))
        }
    }

    private static func arms(_ r: Rig, _ c: UIColor, hand: UIColor? = nil, radius: CGFloat = 0.04) {
        for arm in [r.armPlus, r.armMinus] {
            part(capsule(radius, 0.22), Mat.clay(c), arm, at: v(0, -0.1, 0))
            part(sphere(radius * 1.25), Mat.clay(hand ?? c), arm, at: v(0, -0.21, 0))
        }
    }

    // MARK: Free cast

    /// Pim: a small ceramic robot with a glowing visor and an antenna light.
    static let pim = CharacterSpec(id: "pim", name: "Pim", free: true, style: .robot, voice: 1.25, tint: UIColor(hex: 0x6FD3FF)) { r in
        let shell = Mat.clay(UIColor(hex: 0xF4F1EA), rough: 0.28)
        let grey = Mat.clay(UIColor(hex: 0x8E98A6), rough: 0.45, metal: 0.3)
        part(box(0.36, 0.32, 0.28, 0.11), shell, r.body, at: v(0, 0.31, 0))
        part(box(0.16, 0.05, 0.02, 0.02), Mat.glow(UIColor(hex: 0xFF9A4D), intensity: 1.4), r.body, at: v(0, 0.33, 0.142), shadow: false)
        part(box(0.44, 0.36, 0.38, 0.13), shell, r.head, at: v(0, 0.2, 0))
        part(box(0.36, 0.2, 0.04, 0.06), Mat.clay(UIColor(hex: 0x15181F), rough: 0.12), r.head, at: v(0, 0.2, 0.18), shadow: false)
        Face.eyes(r, on: r.head, y: 0.2, z: 0.205, spread: 0.085, size: 0.04, color: UIColor(hex: 0x6FD3FF), glowing: true)
        part(cyl(0.012, 0.12), grey, r.head, at: v(0, 0.43, 0))
        part(sphere(0.035, seg: 16), Mat.glow(UIColor(hex: 0xFF9A4D), intensity: 2), r.head, at: v(0, 0.5, 0), shadow: false)
        for sx: Float in [-1, 1] { part(cyl(0.05, 0.04), grey, r.head, at: v(sx * 0.23, 0.2, 0), rot: v(0, 0, .pi / 2)) }
        arms(r, UIColor(hex: 0x8E98A6), hand: UIColor(hex: 0xF4F1EA))
        legs(r, UIColor(hex: 0x8E98A6), foot: UIColor(hex: 0x3B414C), radius: 0.04)
    }

    /// Juni: a little fox with a fluffy tail.
    static let juni = CharacterSpec(id: "juni", name: "Juni", free: true, style: .bounce, voice: 1.1, tint: UIColor(hex: 0xF08A3C)) { r in
        let fur = Mat.clay(UIColor(hex: 0xEE8434), rough: 0.85)
        let cream = Mat.clay(UIColor(hex: 0xFFF1DC), rough: 0.85)
        let dark = Mat.clay(UIColor(hex: 0x2B2024), rough: 0.4)
        part(sphere(0.18), fur, r.body, at: v(0, 0.3, 0), scale: v(1, 1.08, 0.92))
        part(sphere(0.12), cream, r.body, at: v(0, 0.28, 0.1), scale: v(1, 1.15, 0.6))
        part(sphere(0.25), fur, r.head, at: v(0, 0.2, 0), scale: v(1.08, 0.95, 0.95))
        part(sphere(0.12), cream, r.head, at: v(0, 0.12, 0.15), scale: v(1.25, 0.8, 0.9))
        part(sphere(0.03, seg: 16), dark, r.head, at: v(0, 0.16, 0.26))
        for sx: Float in [-1, 1] {
            let ear = SCNNode()
            ear.position = v(sx * 0.14, 0.39, -0.02)
            ear.eulerAngles = v(0, 0, -sx * 0.32)
            r.head.addChildNode(ear)
            part(cone(0, 0.08, 0.17), fur, ear, at: v(0, 0.06, 0))
            part(cone(0, 0.045, 0.1), dark, ear, at: v(0, 0.1, 0.012))
        }
        Face.eyes(r, on: r.head, y: 0.23, z: 0.215, spread: 0.1)
        // Tail: a curve of growing spheres ending in a cream tip.
        let tail = SCNNode()
        tail.position = v(0, 0.2, -0.14)
        tail.eulerAngles = v(-0.5, 0, 0)
        r.body.addChildNode(tail)
        for (i, s) in [0.06, 0.085, 0.1, 0.09].enumerated() {
            part(sphere(CGFloat(s)), i == 3 ? cream : fur, tail, at: v(0, Float(i) * 0.06, -Float(i) * 0.07))
        }
        arms(r, UIColor(hex: 0xEE8434), hand: UIColor(hex: 0x2B2024))
        legs(r, UIColor(hex: 0xEE8434), foot: UIColor(hex: 0x2B2024))
    }

    /// Mossy: a forest sprite wearing a big leaf.
    static let mossy = CharacterSpec(id: "mossy", name: "Mossy", free: true, style: .sway, voice: 0.9, tint: UIColor(hex: 0x7FB55A)) { r in
        let skin = Mat.clay(UIColor(hex: 0x9CC77A), rough: 0.8)
        let leaf = Mat.clay(UIColor(hex: 0x3F8A44), rough: 0.55)
        let bark = Mat.clay(UIColor(hex: 0x6B4B33), rough: 0.9)
        part(sphere(0.19), Mat.clay(UIColor(hex: 0x86B565), rough: 0.8), r.body, at: v(0, 0.29, 0), scale: v(1.05, 1, 0.95))
        part(sphere(0.26), skin, r.head, at: v(0, 0.19, 0))
        let hat = SCNNode()
        hat.position = v(0.02, 0.4, -0.02)
        hat.eulerAngles = v(-0.25, 0, 0.18)
        r.head.addChildNode(hat)
        part(sphere(0.2), leaf, hat, scale: v(1.5, 0.28, 1.15))
        part(cyl(0.008, 0.25), Mat.clay(UIColor(hex: 0x2F6B34)), hat, at: v(0, 0.06, 0), rot: v(.pi / 2, 0, 0))
        part(cyl(0.015, 0.1), bark, hat, at: v(0, 0.08, 0), rot: v(0, 0, 0.3))
        Face.eyes(r, on: r.head, y: 0.2, z: 0.235, spread: 0.095)
        Face.cheeks(on: r.head, y: 0.12, z: 0.215)
        arms(r, UIColor(hex: 0x86B565))
        legs(r, UIColor(hex: 0x6B4B33), foot: UIColor(hex: 0x4D3624))
    }

    /// Odette: a tiny wooden dancer in a tutu.
    static let odette = CharacterSpec(id: "odette", name: "Odette", free: true, style: .spin, voice: 1.35, tint: UIColor(hex: 0xE59AAE)) { r in
        let wood = Mat.clay(UIColor(hex: 0xEACBA6), rough: 0.55)
        let rose = Mat.clay(UIColor(hex: 0xD9879C), rough: 0.6)
        let tulle = Mat.clay(UIColor(hex: 0xF9E3E9), rough: 0.9)
        tulle.isDoubleSided = true
        let hair = Mat.clay(UIColor(hex: 0x4A3328), rough: 0.7)
        part(sphere(0.14), rose, r.body, at: v(0, 0.33, 0), scale: v(1, 1.3, 0.85))
        part(cone(0.1, 0.32, 0.05), tulle, r.body, at: v(0, 0.22, 0))
        part(cone(0.1, 0.27, 0.04), Mat.clay(UIColor(hex: 0xF3C7D3), rough: 0.9), r.body, at: v(0, 0.25, 0))
        part(sphere(0.22), wood, r.head, at: v(0, 0.2, 0))
        part(sphere(0.225), hair, r.head, at: v(0, 0.26, -0.025), scale: v(1.02, 0.78, 1))
        part(sphere(0.09), hair, r.head, at: v(0, 0.46, -0.06))
        part(torus(0.06, 0.012), rose, r.head, at: v(0, 0.42, -0.06), rot: v(0.4, 0, 0))
        Face.eyes(r, on: r.head, y: 0.17, z: 0.2, spread: 0.08, size: 0.04)
        Face.cheeks(on: r.head, y: 0.1, z: 0.185, spread: 0.12)
        arms(r, UIColor(hex: 0xEACBA6), radius: 0.032)
        legs(r, UIColor(hex: 0xEACBA6), foot: UIColor(hex: 0xD9879C), radius: 0.034)
    }

    // MARK: Pro cast

    /// Cosmo: an astronaut in a bubble helmet, who prefers to float.
    static let cosmo = CharacterSpec(id: "cosmo", name: "Cosmo", free: false, style: .float, voice: 1.0, tint: UIColor(hex: 0xF2F2F2), floats: true) { r in
        let suit = Mat.clay(UIColor(hex: 0xF3F3F1), rough: 0.7)
        let orange = Mat.clay(UIColor(hex: 0xFF8A3D), rough: 0.5)
        part(box(0.34, 0.34, 0.3, 0.12), suit, r.body, at: v(0, 0.3, 0))
        part(box(0.26, 0.28, 0.12, 0.05), Mat.clay(UIColor(hex: 0xC9CED6), rough: 0.5), r.body, at: v(0, 0.33, -0.19))
        part(box(0.1, 0.06, 0.02, 0.01), orange, r.body, at: v(0.06, 0.37, 0.152), shadow: false)
        part(sphere(0.2), Mat.clay(UIColor(hex: 0xF0C59C), rough: 0.6), r.head, at: v(0, 0.2, 0))
        Face.eyes(r, on: r.head, y: 0.21, z: 0.18, spread: 0.075, size: 0.036)
        Face.cheeks(on: r.head, y: 0.14, z: 0.17, spread: 0.11)
        part(sphere(0.29, seg: 48), Mat.glass(UIColor(hex: 0xBFE6FF), alpha: 0.18), r.head, at: v(0, 0.2, 0), shadow: false)
        part(torus(0.2, 0.035), suit, r.head, at: v(0, -0.02, 0))
        part(cyl(0.008, 0.1), orange, r.head, at: v(0.12, 0.52, 0), rot: v(0, 0, -0.3))
        arms(r, UIColor(hex: 0xF3F3F1), hand: UIColor(hex: 0xFF8A3D), radius: 0.045)
        legs(r, UIColor(hex: 0xF3F3F1), foot: UIColor(hex: 0x9AA2AE))
    }

    /// Tuck: a seabird with a bright beak.
    static let tuck = CharacterSpec(id: "tuck", name: "Tuck", free: false, style: .bounce, voice: 1.5, tint: UIColor(hex: 0xFF6B3D)) { r in
        let black = Mat.clay(UIColor(hex: 0x24262C), rough: 0.6)
        let white = Mat.clay(UIColor(hex: 0xF6F4F0), rough: 0.7)
        let beak = Mat.clay(UIColor(hex: 0xFF6B3D), rough: 0.35)
        part(sphere(0.2), black, r.body, at: v(0, 0.3, 0), scale: v(1, 1.12, 0.95))
        part(sphere(0.15), white, r.body, at: v(0, 0.28, 0.08), scale: v(1, 1.2, 0.7))
        part(sphere(0.24), black, r.head, at: v(0, 0.19, 0))
        part(sphere(0.2), white, r.head, at: v(0, 0.17, 0.08), scale: v(1.05, 0.9, 0.8))
        let b = part(cone(0.0, 0.07, 0.18), beak, r.head, at: v(0, 0.13, 0.3), rot: v(.pi / 2, 0, 0))
        b.scale = v(1.2, 1, 0.75)
        Face.eyes(r, on: r.head, y: 0.22, z: 0.215, spread: 0.1, size: 0.04)
        for arm in [r.armPlus, r.armMinus] {
            part(capsule(0.06, 0.26), black, arm, at: v(0, -0.1, 0), scale: v(0.6, 1, 1.2))
        }
        legs(r, UIColor(hex: 0xFF6B3D), foot: UIColor(hex: 0xFF6B3D), radius: 0.03, length: 0.11)
    }

    /// Kumo: a small cloud that floats and drizzles a little joy.
    static let kumo = CharacterSpec(id: "kumo", name: "Kumo", free: false, style: .float, voice: 0.8, tint: UIColor(hex: 0xDDE8FF), floats: true) { r in
        let cloud = Mat.clay(UIColor(hex: 0xF7F9FF), rough: 0.95)
        let puffs: [(Float, Float, Float, CGFloat)] = [(0, 0.34, 0, 0.21), (-0.17, 0.3, 0, 0.14), (0.17, 0.3, 0, 0.14), (0, 0.27, 0.1, 0.15), (0, 0.3, -0.1, 0.15)]
        for p in puffs { part(sphere(p.3), cloud, r.body, at: v(p.0, p.1, p.2)) }
        let headPuffs: [(Float, Float, Float, CGFloat)] = [(0, 0.17, 0, 0.24), (-0.18, 0.12, 0, 0.15), (0.18, 0.12, 0, 0.15), (-0.08, 0.34, -0.02, 0.14), (0.1, 0.33, -0.02, 0.13)]
        for p in headPuffs { part(sphere(p.3), cloud, r.head, at: v(p.0, p.1, p.2)) }
        Face.eyes(r, on: r.head, y: 0.18, z: 0.225, spread: 0.09)
        Face.cheeks(on: r.head, y: 0.1, z: 0.21, spread: 0.14, color: UIColor(hex: 0x9EC5FF))
        for arm in [r.armPlus, r.armMinus] { part(sphere(0.06), cloud, arm, at: v(0, -0.06, 0)) }
    }

    /// Lumen: a paper lantern spirit that glows from inside.
    static let lumen = CharacterSpec(id: "lumen", name: "Lumen", free: false, style: .sway, voice: 1.15, tint: UIColor(hex: 0xFFC46B)) { r in
        let paper = SCNMaterial()
        paper.lightingModel = .physicallyBased
        paper.diffuse.contents = UIColor(hex: 0xFFD08A)
        paper.emission.contents = UIColor(hex: 0xFFAE4A)
        paper.emission.intensity = 0.9
        paper.roughness.contents = 0.9
        let rib = Mat.clay(UIColor(hex: 0x9C3B2A), rough: 0.6)
        let wood = Mat.clay(UIColor(hex: 0x3C2A22), rough: 0.7)
        part(sphere(0.12), Mat.clay(UIColor(hex: 0x9C3B2A), rough: 0.7), r.body, at: v(0, 0.3, 0), scale: v(1, 1.2, 0.9))
        part(sphere(0.27), paper, r.head, at: v(0, 0.17, 0), scale: v(1, 1.12, 1))
        for y: Float in [-0.06, 0.06, 0.17, 0.28, 0.4] {
            let rr = sqrt(max(0, 0.27 * 0.27 - pow((y - 0.17) / 1.12, 2))) + 0.004
            part(torus(CGFloat(rr), 0.006), rib, r.head, at: v(0, y, 0), shadow: false)
        }
        part(cyl(0.11, 0.04), wood, r.head, at: v(0, 0.48, 0))
        part(cyl(0.1, 0.035), wood, r.head, at: v(0, -0.12, 0))
        part(cyl(0.006, 0.12), wood, r.head, at: v(0, 0.56, 0))
        Face.eyes(r, on: r.head, y: 0.2, z: 0.262, spread: 0.095, size: 0.042)
        Face.cheeks(on: r.head, y: 0.12, z: 0.25, spread: 0.15, color: UIColor(hex: 0xFF7A59))
        arms(r, UIColor(hex: 0x9C3B2A), radius: 0.032)
        legs(r, UIColor(hex: 0x3C2A22), foot: UIColor(hex: 0x3C2A22), radius: 0.032)
    }
}
