import Foundation

/// Every joint angle and offset of a character for one frame, in character units (1 = character height) and
/// radians. The renderer applies it to the rig; the brain produces it. Plain values so the behaviour is testable.
struct Pose: Equatable {
    var bob: Float = 0            // vertical offset of the upper body
    var hop: Float = 0            // whole-body jump height
    var squash: Float = 0         // + squashes, - stretches
    var lean: Float = 0           // forward lean (x rotation of the body)
    var roll: Float = 0           // side sway (z rotation of the body)
    var twist: Float = 0          // upper-body turn (y rotation)
    var spin: Float = 0           // whole-body turn added to the facing direction
    var headYaw: Float = 0
    var headPitch: Float = 0
    var headRoll: Float = 0
    var armPlus: Float = 0.12     // raise of the arm on +x (z rotation, 0 = hanging)
    var armMinus: Float = 0.12
    var swingPlus: Float = 0      // forward swing (x rotation)
    var swingMinus: Float = 0
    var legPlus: Float = 0
    var legMinus: Float = 0
    var eyesOpen: Float = 1
    var float: Float = 0          // extra hover for floating characters
}

enum DanceStyle: String, CaseIterable {
    case bounce, sway, spin, robot, float
}

/// What the character is doing besides idling and dancing.
enum Act: Equatable {
    case wave(started: Double)
    case giggle(started: Double)
    case appear(started: Double)
    case cheer(started: Double)      // both arms up, for the fall and the lantern release
    case offer(started: Double)      // hands forward and up: releases a lantern

    var started: Double {
        switch self {
        case .wave(let s), .giggle(let s), .appear(let s), .cheer(let s), .offer(let s): return s
        }
    }

    var duration: Double {
        switch self {
        case .wave: return 2.3
        case .giggle: return 0.9
        case .appear: return 0.8
        case .cheer: return 1.4
        case .offer: return 1.3
        }
    }
}

/// Behaviour of one character: idle life (breathing, blinking, glances), looking at a target, gestures and dancing
/// on the music's beat. Deterministic for a given seed so tests can check it.
struct Brain {
    var style: DanceStyle
    /// Head limits (radians).
    var maxYaw: Float = 1.0
    var maxPitch: Float = 0.75

    private(set) var gesture: Act?
    private(set) var facing: Float = 0             // body yaw the character has turned to
    private var headYaw = Spring1(0, omega: 10)
    private var headPitch = Spring1(0, omega: 10)
    private var facingSpring = Spring1(0, omega: 4)
    private var danceAmount = Spring1(0, omega: 3)
    private var nextBlink: Double = 1.5
    private var blinkStart: Double = -1
    private var nextGlance: Double = 4
    private var glance: (yaw: Float, pitch: Float, until: Double)?
    private var rng: UInt64

    init(style: DanceStyle, seed: UInt64 = 7) {
        self.style = style
        self.rng = seed | 1
    }

    private mutating func random() -> Double {
        // xorshift64*: tiny, deterministic.
        rng ^= rng >> 12; rng ^= rng << 25; rng ^= rng >> 27
        return Double((rng &* 2685821657736338717) >> 11) / Double(1 << 53)
    }

    mutating func perform(_ g: Act) {
        // A wave or appearance is never cut short by a giggle.
        if let current = gesture, case .giggle = g {
            switch current { case .wave, .appear: return; default: break }
        }
        gesture = g
    }

    var isBusy: Bool { gesture != nil }

    var isOffering: Bool {
        if case .offer = gesture { return true }
        return false
    }

    /// - Parameters:
    ///   - look: desired head direction (yaw right-positive, pitch up-positive) toward the person or point of
    ///     interest, in radians relative to the body's rest facing; nil when nobody is there.
    ///   - beat: music position in beats when music plays, else nil.
    mutating func update(t: Double, dt: Float, look: (yaw: Float, pitch: Float)?, beat: Double?) -> Pose {
        var p = Pose()
        if let g = gesture, t - g.started > g.duration { gesture = nil }

        // Breathing.
        let breath = Float(sin(t * 2 * .pi / 3.6))
        p.squash = breath * 0.012
        p.bob = breath * 0.004

        // Blinking: quick close/open, sometimes double.
        if t >= nextBlink {
            blinkStart = t
            nextBlink = t + 2.2 + random() * 3.5
            if random() < 0.18 { nextBlink = t + 0.28 }
        }
        let bt = t - blinkStart
        if bt >= 0 && bt < 0.16 { p.eyesOpen = Float(abs(bt - 0.08) / 0.08) }

        // Where to look: the person, or idle glances around when nobody is there.
        var target: (yaw: Float, pitch: Float)
        if let look {
            target = look
            glance = nil
        } else {
            if t >= nextGlance {
                glance = (Float(random() * 1.4 - 0.7), Float(random() * 0.5 - 0.15), t + 1.2 + random() * 1.5)
                nextGlance = t + 3.5 + random() * 4
            }
            if let g = glance, t < g.until { target = (g.yaw, g.pitch) } else { target = (0, 0.05) }
        }
        // The body turns toward big angles; the head does the rest.
        var desiredFacing = facing
        if abs(target.yaw - facing) > 0.65 { desiredFacing = target.yaw * 0.8 }
        if look == nil && abs(facing) > 0.05 && glance == nil { desiredFacing = 0 }
        facing = facingSpring.step(to: desiredFacing, dt: dt)
        let relYaw = max(-maxYaw, min(maxYaw, target.yaw - facing))
        let relPitch = max(-maxPitch * 0.6, min(maxPitch, target.pitch))
        p.headYaw = headYaw.step(to: relYaw, dt: dt)
        p.headPitch = -headPitch.step(to: relPitch, dt: dt)    // rig: positive x rotation looks down
        p.spin = facing

        // Dancing fades in and out with the music.
        let dancing = danceAmount.step(to: beat == nil || gesture != nil ? 0 : 1, dt: dt)
        if dancing > 0.01, let b = beat ?? Optional(0) {
            dance(&p, beat: b, amount: dancing)
        }

        if let g = gesture { apply(g, t: t, to: &p) }
        return p
    }

    private func dance(_ p: inout Pose, beat: Double, amount a: Float) {
        let ph = Float(beat.truncatingRemainder(dividingBy: 1))
        let bar2 = Float((beat / 2).truncatingRemainder(dividingBy: 1))
        let pulse = sin(ph * .pi)                       // 0→1→0 each beat
        let side: Float = Int(beat) % 2 == 0 ? 1 : -1
        switch style {
        case .bounce:
            p.hop += pulse * 0.05 * a
            p.squash += (1 - pulse) * 0.05 * a - 0.02 * a
            p.armPlus += (side > 0 ? 2.2 : 0.5) * a * pulse
            p.armMinus += (side < 0 ? 2.2 : 0.5) * a * pulse
            p.headRoll += side * 0.12 * a
            p.headPitch += 0.08 * pulse * a
        case .sway:
            let s = sin(bar2 * 2 * .pi)
            p.roll += s * 0.16 * a
            p.twist += s * 0.25 * a
            p.armPlus += (1.1 + s * 0.5) * a
            p.armMinus += (1.1 - s * 0.5) * a
            p.legPlus += max(0, s) * 0.3 * a
            p.legMinus += max(0, -s) * 0.3 * a
            p.bob += pulse * 0.015 * a
            p.headRoll -= s * 0.1 * a
        case .spin:
            p.hop += pulse * 0.03 * a
            p.armPlus += 1.4 * a
            p.armMinus += 1.4 * a
            p.swingPlus -= 0.4 * a
            p.swingMinus -= 0.4 * a
            // A pirouette over the last two beats of every eight.
            let cycle = beat.truncatingRemainder(dividingBy: 8)
            if cycle >= 6 {
                let u = Float((cycle - 6) / 2)
                let e = u * u * (3 - 2 * u)
                p.spin += e * 2 * .pi * a
                p.armPlus += 1.0 * a * sin(u * .pi)
                p.armMinus += 1.0 * a * sin(u * .pi)
            } else {
                p.roll += side * 0.08 * a
            }
        case .robot:
            // Snappy poses that change on each beat.
            let snap = min(1, ph * 6)
            let k = Int(beat) % 4
            let poses: [(Float, Float, Float)] = [(1.6, 0.2, 0.3), (0.2, 1.6, -0.3), (1.6, 1.6, 0), (0.6, 0.6, 0.2)]
            let prev = poses[(k + 3) % 4], cur = poses[k]
            p.armPlus += (prev.0 + (cur.0 - prev.0) * snap) * a
            p.armMinus += (prev.1 + (cur.1 - prev.1) * snap) * a
            p.headRoll += (prev.2 + (cur.2 - prev.2) * snap) * a
            p.twist += (prev.2 + (cur.2 - prev.2) * snap) * 0.8 * a
            p.bob += pulse * 0.02 * a
        case .float:
            p.float += (sin(Float(beat) * .pi / 2) * 0.05 + 0.05) * a
            p.armPlus += (1.2 + sin(ph * 2 * .pi) * 0.6) * a
            p.armMinus += (1.2 + sin(ph * 2 * .pi) * 0.6) * a
            p.roll += sin(Float(beat) * .pi / 2) * 0.12 * a
        }
        if style == .float { p.float += 0.04 }
    }

    private func apply(_ g: Act, t: Double, to p: inout Pose) {
        let u = Float((t - g.started) / g.duration)
        let inOut = min(1, min(u * 6, (1 - u) * 6))      // quick ease in and out
        switch g {
        case .wave:
            p.armPlus = p.armPlus * (1 - inOut) + 2.65 * inOut
            p.swingPlus = sin(Float(t - g.started) * 2 * .pi * 2.6) * 0.38 * inOut
            p.headRoll += 0.2 * inOut
            if u < 0.18 { p.hop += sin(u / 0.18 * .pi) * 0.06 }
            p.eyesOpen = max(p.eyesOpen, 0.9 - 0.5 * inOut)   // happy squint
        case .giggle:
            let w = sin(u * .pi * 5) * (1 - u)
            p.squash += w * 0.12
            p.hop += sin(u * .pi) * 0.09
            p.headRoll += sin(u * .pi * 4) * 0.18 * (1 - u)
            p.eyesOpen = 0.35
            p.armPlus += 0.6 * inOut
            p.armMinus += 0.6 * inOut
        case .appear:
            // Pops up from small with an overshoot (applied as squash/stretch; scale is the renderer's job).
            p.squash -= sin(u * .pi) * 0.15
            p.armPlus += 1.8 * sin(u * .pi)
            p.armMinus += 1.8 * sin(u * .pi)
        case .cheer:
            p.armPlus = 2.7 * inOut + p.armPlus * (1 - inOut)
            p.armMinus = 2.7 * inOut + p.armMinus * (1 - inOut)
            p.hop += abs(sin(u * .pi * 3)) * 0.05
            p.headPitch -= 0.25 * inOut
        case .offer:
            p.swingPlus = -1.5 * inOut
            p.swingMinus = -1.5 * inOut
            p.armPlus = 0.25 * inOut + p.armPlus * (1 - inOut)
            p.armMinus = 0.25 * inOut + p.armMinus * (1 - inOut)
            p.headPitch -= 0.4 * inOut
            p.lean -= 0.1 * inOut
        }
    }

    /// Appear scale (0…1 with a little overshoot) for the renderer.
    func appearScale(t: Double) -> Float {
        guard case .appear(let s)? = gesture else { return 1 }
        let u = Float(min(max((t - s) / 0.55, 0), 1))
        // Elastic ease-out.
        return 1 - pow(2, -9 * u) * cos(u * .pi * 2.6)
    }
}
