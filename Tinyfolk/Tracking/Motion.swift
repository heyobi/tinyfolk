import CoreMotion
import UIKit
import simd

/// Gravity from the motion sensors: tells a flat phone from an upright one and, before the camera is allowed,
/// gives a tilt-driven parallax so the scene feels deep from the very first second.
final class Motion {
    private let manager = CMMotionManager()
    private(set) var gravity: SIMD3<Float>?          // in screen axes (x right, y up, z out of the glass)
    private var baseline: SIMD3<Float>?
    private(set) var isFlat = false
    var interface: UIInterfaceOrientation = .portrait

    var available: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            self.update(device: SIMD3(Float(g.x), Float(g.y), Float(g.z)))
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    /// Device axes to screen axes for the current interface orientation.
    static func toScreen(_ d: SIMD3<Float>, _ io: UIInterfaceOrientation) -> SIMD3<Float> {
        switch io {
        case .portraitUpsideDown: return SIMD3(-d.x, -d.y, d.z)
        case .landscapeLeft: return SIMD3(d.y, -d.x, d.z)
        case .landscapeRight: return SIMD3(-d.y, d.x, d.z)
        default: return d
        }
    }

    private func update(device: SIMD3<Float>) {
        let g = Self.toScreen(device, interface)
        gravity = g
        // Flat when gravity points mostly through the glass (hysteresis).
        if isFlat { if abs(g.z) < 0.7 { isFlat = false } } else if abs(g.z) > 0.82 { isFlat = true }
        if let b = baseline {
            // The neutral pose slowly follows how the phone is held.
            baseline = simd_normalize(b + (g - b) * 0.004)
        } else {
            baseline = g
        }
    }

    /// Eye position implied by tilting the phone away from its neutral pose (window frame).
    func tiltEye(neutral: SIMD3<Float>) -> SIMD3<Float>? {
        guard let g = gravity, let b = baseline, simd_length(g) > 0.1, simd_length(b) > 0.1 else { return nil }
        let q = simd_quatf(from: simd_normalize(b), to: simd_normalize(g))
        return q.act(neutral)
    }
}
