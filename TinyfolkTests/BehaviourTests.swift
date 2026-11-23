import XCTest
import simd
@testable import Tinyfolk

final class ViewerTests: XCTestCase {
    private let a = SIMD3<Float>(0, 0.2, 0.36)
    private let b = SIMD3<Float>(0.22, 0.16, 0.34)

    private func feed(_ v: inout ViewerTracker, _ dets: [Detection], from t0: Double, seconds: Double, fps: Double = 30) -> [ViewerEvent] {
        var all: [ViewerEvent] = []
        var t = t0
        while t < t0 + seconds {
            all += v.update(dets, t: t)
            t += 1 / fps
        }
        return all
    }

    func testFirstViewerArrivesAndBecomesPrimary() {
        var v = ViewerTracker()
        let ev = feed(&v, [Detection(position: a, looking: true)], from: 0, seconds: 0.5)
        XCTAssert(ev.contains(.arrived(id: 1)))
        XCTAssertEqual(v.primaryID, 1)
        XCTAssertEqual(v.attentionID, 1)
    }

    func testSecondViewerTriggersGreetingOnce() {
        var v = ViewerTracker()
        _ = feed(&v, [Detection(position: a, looking: true)], from: 0, seconds: 1)
        let ev = feed(&v, [Detection(position: a, looking: true), Detection(position: b, looking: true)], from: 1, seconds: 2)
        XCTAssertEqual(ev.filter { if case .secondArrived = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(v.confirmed.count, 2)
        // The perspective stays with the first viewer while they keep looking.
        XCTAssertEqual(v.primaryID, 1)
    }

    func testNewLookerGetsAttentionThenItAlternates() {
        var v = ViewerTracker()
        _ = feed(&v, [Detection(position: a, looking: true)], from: 0, seconds: 1)
        _ = feed(&v, [Detection(position: a, looking: true), Detection(position: b, looking: true)], from: 1, seconds: 0.5)
        XCTAssertEqual(v.attentionID, 2, "a newcomer who looks gets the character's attention")
        var seen = Set<Int>()
        var t = 1.5
        while t < 12 {
            v.update([Detection(position: a, looking: true), Detection(position: b, looking: true)], t: t)
            if let id = v.attentionID { seen.insert(id) }
            t += 1 / 30
        }
        XCTAssertEqual(seen, [1, 2], "with two lookers the character turns between them")
    }

    func testPrimaryHandsOverWhenFirstLooksAway() {
        var v = ViewerTracker()
        _ = feed(&v, [Detection(position: a, looking: true), Detection(position: b, looking: true)], from: 0, seconds: 1)
        let first = v.primaryID
        let primaryIsA = simd_distance(v.primary!.position, a) < 0.05
        let ev = feed(&v, [Detection(position: a, looking: !primaryIsA), Detection(position: b, looking: primaryIsA)],
                      from: 1, seconds: 2)
        XCTAssertNotEqual(v.primaryID, first)
        XCTAssert(ev.contains { if case .primaryChanged = $0 { return true }; return false })
    }

    func testViewerLeavesAfterTimeout() {
        var v = ViewerTracker()
        _ = feed(&v, [Detection(position: a, looking: true)], from: 0, seconds: 1)
        let ev = feed(&v, [], from: 1, seconds: 2)
        XCTAssert(ev.contains(.left(id: 1)))
        XCTAssertNil(v.primary)
    }

    /// A face that drops out for a moment (looked away, blinked into shadow) keeps its track and position.
    func testShortDropoutKeepsTheViewer() {
        var v = ViewerTracker()
        _ = feed(&v, [Detection(position: a, looking: true)], from: 0, seconds: 1)
        let ev = feed(&v, [], from: 1, seconds: 1.0)
        XCTAssertFalse(ev.contains(.left(id: 1)))
        XCTAssertEqual(v.primaryID, 1)
        XCTAssertLessThan(simd_distance(v.primary!.position, a), 0.01)
    }

    /// Noisy detections around a still head barely move the filtered eye.
    func testStillHeadIsSteady() {
        var v = ViewerTracker()
        var xs: [Float] = []
        var t = 0.0
        var seed: UInt64 = 1
        while t < 4 {
            seed = seed &* 6364136223846793005 &+ 1
            let n = Float(Int(seed >> 40) % 1000) / 1000 - 0.5
            v.update([Detection(position: a + SIMD3(n * 0.01, 0, n * 0.02), looking: true)], t: t)
            if t > 2, let p = v.primary { xs.append(p.position.x) }
            t += 1 / 30
        }
        XCTAssertLessThan(xs.max()! - xs.min()!, 0.005)
    }

    func testFlickerIsNotAViewer() {
        var v = ViewerTracker()
        let first = v.update([Detection(position: a, looking: true)], t: 0)
        let second = v.update([], t: 0.03)
        XCTAssert(first.isEmpty && second.isEmpty)
        XCTAssertNil(v.primaryID)
    }

    func testEyeBlendIsSmooth() {
        var e = EyeBlender(a)
        _ = e.update(target: a, id: 1, t: 0)
        var last = e.update(target: b, id: 2, t: 1)
        XCTAssertEqual(simd_distance(last, a), 0, accuracy: 1e-4)
        var t = 1.0
        while t < 2 {
            t += 1 / 60
            let p = e.update(target: b, id: 2, t: t)
            XCTAssertLessThan(simd_distance(p, last), 0.02, "no jumps between frames")
            last = p
        }
        XCTAssertEqual(simd_distance(last, b), 0, accuracy: 1e-4)
    }

    func testOneEuroSmoothsNoiseButFollowsMotion() {
        var f = OneEuro(minCutoff: 1, beta: 0.7)
        var still: [Double] = []
        for i in 0..<120 { still.append(f.filter(0.3 + (i % 2 == 0 ? 0.01 : -0.01), t: Double(i) / 30)) }
        let jitter = still.suffix(60).max()! - still.suffix(60).min()!
        XCTAssertLessThan(jitter, 0.01)
        var g = OneEuro(minCutoff: 1, beta: 0.7)
        var out = 0.0
        for i in 0..<60 { out = g.filter(Double(i) * 0.01, t: Double(i) / 30) }
        XCTAssertGreaterThan(out, 0.5, "follows a steady move with little lag")
    }
}

final class BrainTests: XCTestCase {
    func testLooksTowardTarget() {
        var b = Brain(style: .bounce)
        var p = Pose()
        for i in 0..<120 { p = b.update(t: Double(i) / 60, dt: 1 / 60, look: (0.5, 0.2), beat: nil) }
        XCTAssertGreaterThan(p.headYaw + p.spin, 0.4)
        XCTAssertLessThan(p.headPitch, 0, "positive pitch target looks up (negative x rotation)")
    }

    func testWaveRaisesArmThenEnds() {
        var b = Brain(style: .sway)
        b.perform(.wave(started: 0))
        var p = b.update(t: 0.8, dt: 1 / 60, look: nil, beat: nil)
        XCTAssertGreaterThan(p.armPlus, 2)
        p = b.update(t: 3, dt: 1 / 60, look: nil, beat: nil)
        XCTAssertFalse(b.isBusy)
        XCTAssertLessThan(p.armPlus, 1)
    }

    func testDancingFollowsTheBeat() {
        for style in DanceStyle.allCases {
            var b = Brain(style: style)
            var poses: [Pose] = []
            for i in 0..<600 { poses.append(b.update(t: Double(i) / 60, dt: 1 / 60, look: nil, beat: Double(i) / 60 * 2)) }
            let arms = poses.suffix(200).map(\.armPlus)
            XCTAssertGreaterThan(arms.max()! - arms.min()!, 0.2, "\(style) moves with the music")
            XCTAssertFalse(poses.contains { $0.armPlus.isNaN || $0.hop.isNaN })
        }
    }

    func testBlinks() {
        var b = Brain(style: .robot)
        var closed = false
        for i in 0..<(60 * 10) {
            let p = b.update(t: Double(i) / 60, dt: 1 / 60, look: nil, beat: nil)
            if p.eyesOpen < 0.3 { closed = true }
        }
        XCTAssert(closed)
    }
}

final class MusicTests: XCTestCase {
    func testPitchNames() {
        XCTAssertEqual(Pitch.midi("C4"), 60)
        XCTAssertEqual(Pitch.midi("F#3"), 54)
        XCTAssertEqual(Pitch.midi("Bb5"), 82)
        XCTAssertEqual(Pitch.midi("Eb5"), 75)
        XCTAssertNil(Pitch.midi("H2"))
    }

    func testChords() {
        XCTAssertEqual(Chord.parse("Gm")?.root, 7)
        XCTAssertEqual(Chord.parse("Gm")?.intervals, [0, 3, 7])
        XCTAssertEqual(Chord.parse("F#m7")?.root, 6)
        XCTAssertEqual(Chord.parse("Bb")?.root, 10)
        XCTAssertNotNil(Chord.parse("Dmaj7"))
        XCTAssertNotNil(Chord.parse("A7"))
    }

    /// Every piece parses, every bar is whole, chords exist, and the arrangement stays in a pleasant range.
    func testLibraryArranges() {
        for p in Library.all {
            let parsed = Score.parse(p.melody)
            XCTAssertFalse(parsed.notes.isEmpty, p.id)
            XCTAssertFalse(parsed.chords.isEmpty, p.id)
            XCTAssertFalse(parsed.notes.contains { $0.midi == nil && $0.dur <= 0 }, p.id)
            let a = Score.arrange(p)
            XCTAssertEqual(a.loop.truncatingRemainder(dividingBy: Double(p.meter)), 0, accuracy: 1e-6, p.id)
            XCTAssertGreaterThan(a.events.count, 40, p.id)
            XCTAssert(a.events.allSatisfy { $0.beat >= 0 && $0.beat < a.loop && $0.midi >= 28 && $0.midi <= 108 }, p.id)
            let melody = a.events.filter { $0.inst == p.lead }
            XCTAssertGreaterThanOrEqual(melody.count, parsed.notes.compactMap(\.midi).count, p.id)
        }
    }

    func testFreeAndProSplit() {
        XCTAssertEqual(Library.all.filter(\.free).count, 4)
        XCTAssertEqual(Cast.all.filter(\.free).count, 4)
        XCTAssertEqual(Stages.all.filter(\.free).count, 3)
    }

    /// The real audio graph renders sound offline (catches a silent engine before it reaches TestFlight).
    func testSynthRendersSound() throws {
        let s = Synth()
        try s.startOffline()
        s.play("lantern")
        let rms = try s.renderOfflineRMS(seconds: 3)
        XCTAssertGreaterThan(rms, 0.005)
        XCTAssertLessThan(rms, 0.7)
        s.sfx(.knock, midi: 88)
        s.sfx(.chirp, midi: 76)
        XCTAssertGreaterThan(try s.renderOfflineRMS(seconds: 0.3), 0.001)
    }

    /// Every piece sounds and the beat advances at the piece's tempo.
    func testEveryPieceSoundsAndKeepsTime() throws {
        let s = Synth()
        try s.startOffline()
        for p in Library.all {
            s.play(p.id)
            let rms = try s.renderOfflineRMS(seconds: 2)
            XCTAssertGreaterThan(rms, 0.003, p.id)
            let beat = s.beat ?? -1
            XCTAssertEqual(beat, (2 * p.tempo / 60).truncatingRemainder(dividingBy: Score.arrange(p).loop), accuracy: 0.6, p.id)
        }
    }
}
