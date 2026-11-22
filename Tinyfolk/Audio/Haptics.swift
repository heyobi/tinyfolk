import CoreHaptics
import UIKit

/// Small, physical-feeling haptics: a lantern knocking on the glass, a landing, a wave hello.
final class Haptics {
    static let shared = Haptics()

    var enabled: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }

    private var engine: CHHapticEngine?
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let softGen = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    private init() {
        light.prepare(); softGen.prepare(); rigid.prepare()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
    }

    private func play(_ events: [CHHapticEvent]) -> Bool {
        guard let engine, let pattern = try? CHHapticPattern(events: events, parameters: []) else { return false }
        do {
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
            return true
        } catch { return false }
    }

    private func tick(_ i: Float, _ s: Float, at t: TimeInterval = 0) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: s)], relativeTime: t)
    }

    /// A lantern touching the glass from below: a tiny, crisp tap.
    func knock(_ strength: Float) {
        guard enabled else { return }
        if !play([tick(0.25 + 0.45 * strength, 0.85)]) { rigid.impactOccurred(intensity: CGFloat(0.3 + 0.5 * strength)) }
    }

    func land() {
        guard enabled else { return }
        let rumble = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)], relativeTime: 0.02, duration: 0.12)
        if !play([tick(0.9, 0.3), rumble]) { softGen.impactOccurred(intensity: 1) }
    }

    func wave() {
        guard enabled else { return }
        if !play([tick(0.45, 0.6), tick(0.35, 0.6, at: 0.16)]) { light.impactOccurred() }
    }

    func tap() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.7)
    }

    func fall() {
        guard enabled else { return }
        if !play([tick(0.5, 0.2), tick(0.3, 0.2, at: 0.12), tick(0.15, 0.2, at: 0.24)]) { softGen.impactOccurred() }
    }

    func soft(_ i: CGFloat = 0.6) {
        guard enabled else { return }
        softGen.impactOccurred(intensity: i)
    }
}
