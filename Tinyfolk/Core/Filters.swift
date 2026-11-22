import Foundation
import simd

/// One-euro filter (Casiez, Roussel, Vogel 2012): heavy smoothing when the signal is still, little lag when it moves.
struct OneEuro {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double = 1

    private var x: Double?
    private var dx: Double = 0
    private var lastT: Double?

    init(minCutoff: Double = 1.0, beta: Double = 0.7) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    mutating func reset() { x = nil; dx = 0; lastT = nil }

    mutating func filter(_ value: Double, t: Double) -> Double {
        guard let px = x, let pt = lastT else {
            x = value; lastT = t; return value
        }
        let dt = max(t - pt, 1e-3)
        let rawDx = (value - px) / dt
        dx += Self.alpha(dCutoff, dt) * (rawDx - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let nx = px + Self.alpha(cutoff, dt) * (value - px)
        x = nx
        lastT = t
        return nx
    }
}

/// One-euro filter on a 3-D point (per axis).
struct OneEuro3 {
    private var fx: OneEuro, fy: OneEuro, fz: OneEuro

    init(minCutoff: Double = 1.0, beta: Double = 0.7) {
        fx = OneEuro(minCutoff: minCutoff, beta: beta)
        fy = OneEuro(minCutoff: minCutoff, beta: beta)
        // Depth from face size is the noisiest axis: smooth it more.
        fz = OneEuro(minCutoff: minCutoff * 0.5, beta: beta * 0.5)
    }

    mutating func reset() { fx.reset(); fy.reset(); fz.reset() }

    mutating func filter(_ p: SIMD3<Float>, t: Double) -> SIMD3<Float> {
        SIMD3(Float(fx.filter(Double(p.x), t: t)), Float(fy.filter(Double(p.y), t: t)), Float(fz.filter(Double(p.z), t: t)))
    }
}

/// Critically damped spring toward a moving target, for smooth hand-offs that never overshoot.
struct Spring3 {
    var value: SIMD3<Float>
    var velocity = SIMD3<Float>(repeating: 0)
    /// Angular frequency; higher is snappier.
    var omega: Float

    init(_ value: SIMD3<Float>, omega: Float = 9) {
        self.value = value
        self.omega = omega
    }

    mutating func step(to target: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
        let dt = min(max(dt, 0), 0.1)
        let x = value - target
        let exp = Foundation.exp(-omega * dt)
        let temp = (velocity + x * omega) * dt
        velocity = (velocity - temp * omega) * exp
        value = target + (x + temp) * exp
        return value
    }
}

/// Scalar critically damped spring.
struct Spring1 {
    var value: Float
    var velocity: Float = 0
    var omega: Float

    init(_ value: Float, omega: Float = 9) {
        self.value = value
        self.omega = omega
    }

    mutating func step(to target: Float, dt: Float) -> Float {
        let dt = min(max(dt, 0), 0.1)
        let x = value - target
        let exp = Foundation.exp(-omega * dt)
        let temp = (velocity + x * omega) * dt
        velocity = (velocity - temp * omega) * exp
        value = target + (x + temp) * exp
        return value
    }
}
