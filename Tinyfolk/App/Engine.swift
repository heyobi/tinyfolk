import SwiftUI
import SceneKit
import simd

enum TrackingState: Equatable { case off, needsPermission, denied, running, unavailable }

/// How the device is held, for hints.
enum Posture: Equatable { case window, stage, book }

/// Ties everything together: device geometry and hinge → display surfaces, camera faces → viewers → the rendering
/// eye, and the world's events → sound and haptics. One instance for the app, driven by HoloView's display link.
@MainActor
final class Engine: ObservableObject {
    // Choices (persisted).
    @Published var characterID: String { didSet { save("character", characterID); world.setCharacter(Cast.spec(characterID)) } }
    @Published var stageID: String { didSet { save("stage", stageID); world.setStage(Stages.spec(stageID)) } }
    @Published var songID: String { didSet { save("song", songID); if musicOn { Synth.shared.play(songID) } } }
    @Published var musicOn: Bool { didSet { save("music", musicOn); Synth.shared.play(musicOn ? songID : nil) } }

    // State for the interface.
    @Published private(set) var tracking: TrackingState = .off
    @Published private(set) var viewerCount = 0
    @Published private(set) var posture: Posture = .window
    @Published private(set) var presentation: Presentation = .diorama
    @Published private(set) var diagnostics = ""
    @Published private(set) var hasHinge = false
    @Published var askReview = false
    /// True while iOS shows our companion on the iPhone Duo outer display.
    @Published var outerDisplay = false
    /// Sheet the screenshot tour wants open.
    @Published var shotSheet: Sheet?

    // Debug / simulator controls.
    @Published var simulate: Bool
    @Published var simA = SIMD3<Float>(0, 0.2, 0.36)
    @Published var simB = SIMD3<Float>(0.18, 0.16, 0.33)
    @Published var simBOn = false
    @Published var simALooking = true
    @Published var simBLooking = true
    @Published var demoOrbit = true
    @Published var hingeOverride: Double?
    @Published var presentationOverride: Presentation?

    let world: World
    let tracker = FaceTracker()
    let motion = Motion()

    private var viewers = ViewerTracker()
    private var blender = EyeBlender(SIMD3(0, 0.2, 0.36))
    private var fallbackEye = Spring3(SIMD3(0, 0.2, 0.36), omega: 3)
    /// Last smoothing on the rendering eye: removes the remaining frame-to-frame tremble with ~60 ms of lag.
    private var eyeSmooth = Spring3(SIMD3(0, 0.2, 0.36), omega: 16)
    private var latestFrame: FaceTracker.Frame?
    private var frameConsumed = true
    private var hingeAngle: Double?
    private var hingeClosed = false
    private var stageMode = false
    private var lastLayout: SurfaceLayout?
    private var lastPresentation: Presentation?
    private var greetedFirst = false

    // Geometry from HoloView.
    struct Geometry: Equatable {
        var size: CGSize = .zero
        var fold: CGRect?
        var insets: UIEdgeInsets = .zero
        var interface: UIInterfaceOrientation = .portrait
        var isPad = false
        var nativeScale: CGFloat = 3
    }
    var geometry = Geometry() { didSet { if geometry.interface != oldValue.interface { interfaceChanged() } } }

    init() {
        let d = UserDefaults.standard
        let c = d.string(forKey: "character") ?? "pim"
        let s = d.string(forKey: "stage") ?? "studio"
        characterID = c
        stageID = s
        songID = d.string(forKey: "song") ?? "lantern"
        musicOn = d.object(forKey: "music") as? Bool ?? true
        #if targetEnvironment(simulator)
        simulate = true
        #else
        simulate = false
        #endif
        world = World(character: Cast.spec(c), stage: Stages.spec(s))
        world.events = { [weak self] e in self?.handle(e) }
        tracker.onFrame = { [weak self] f in self?.latestFrame = f; self?.frameConsumed = false; self?.diagnostics = f.diagnostics }
        tracker.onRunning = { [weak self] running in
            guard let self else { return }
            if running { self.tracking = .running } else if self.tracking == .running { self.tracking = .off }
        }
        refreshTrackingState()
    }

    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }

    // MARK: Lifecycle

    func activate() {
        Synth.shared.start()
        if musicOn { Synth.shared.play(songID) }
        motion.start()
        refreshTrackingState()
        if FaceTracker.authorized && UserDefaults.standard.object(forKey: "tracking") as? Bool ?? true { tracker.start() }
    }

    func deactivate() {
        tracker.stop()
        motion.stop()
        Synth.shared.pause()
    }

    func refreshTrackingState() {
        if !FaceTracker.available { tracking = .unavailable }
        else if FaceTracker.denied { tracking = .denied }
        else if !FaceTracker.authorized { tracking = .needsPermission }
        else if tracking != .running { tracking = .off }
    }

    func enableTracking() {
        UserDefaults.standard.set(true, forKey: "tracking")
        if FaceTracker.authorized { tracker.start(); return }
        tracker.requestAccess { [weak self] ok in
            guard let self else { return }
            self.refreshTrackingState()
            if ok { self.tracker.start() }
        }
    }

    func disableTracking() {
        UserDefaults.standard.set(false, forKey: "tracking")
        tracker.stop()
        tracking = .off
    }

    private func interfaceChanged() {
        motion.interface = geometry.interface
        tracker.setContext(interface: geometry.interface, key: contextKey)
    }

    private var contextKey: String {
        if geometry.isPad { return "pad" }
        if hasHinge { return geometry.fold != nil ? "inner" : "outer" }
        return "phone"
    }

    // MARK: Hinge

    func hingeChanged(angle: Double, closed: Bool) {
        hasHinge = true
        hingeAngle = angle
        hingeClosed = closed
        tracker.setContext(interface: geometry.interface, key: contextKey)
    }

    var effectiveHinge: Double? { hingeOverride ?? hingeAngle }

    // MARK: Layout

    private var pointsPerMetre: Float {
        PhysicalScale.pointsPerMetre(isPad: geometry.isPad, nativeScale: Float(geometry.nativeScale))
    }

    /// The layout the device's pose asks for right now.
    func desiredLayout() -> SurfaceLayout? {
        let g = geometry
        guard g.size.width > 10, g.size.height > 10 else { return nil }
        let ppm = pointsPerMetre
        let W = Float(g.size.width), H = Float(g.size.height)
        var pose: Posture = .window

        if let fold = g.fold, let angle = effectiveHinge, !(hingeClosed && hingeOverride == nil) {
            let horizontal = fold.width > fold.height
            if horizontal {
                if stageMode { if angle > 165 || angle < 12 { stageMode = false } }
                else if angle < 155 && angle > 20 { stageMode = true }
            } else {
                stageMode = false
                if angle < 160 && angle > 20 { pose = .book }
            }
        } else {
            stageMode = false
        }
        if let o = presentationOverride { stageMode = o == .stage && g.fold.map { $0.width > $0.height } == true }

        // The stage needs a fold running across the window with real screen on both sides.
        if stageMode, let fold = g.fold, fold.width > fold.height, fold.minY > 40, H - Float(fold.maxY) > 40 {
            pose = .stage
            let angle = Float(effectiveHinge ?? 110)
            let upperH = Float(fold.minY), lowerH = H - Float(fold.maxY)
            let surfaces = DisplayLayout.stage(hingeDegrees: angle, upper: SIMD2(W / ppm, upperH / ppm), lower: SIMD2(W / ppm, lowerH / ppm),
                                        gap: Float(fold.height) / 2 / ppm)
            if posture != pose { posture = pose }
            return SurfaceLayout(presentation: .stage, upper: surfaces.upper, lower: surfaces.lower, screen: SIMD2(W / ppm, H / ppm))
        }
        if posture != pose { posture = pose }
        let screen = SIMD2(W / ppm, H / ppm)
        var p: Presentation
        if let o = presentationOverride, o != .stage {
            p = o
        } else if motion.available && motion.gravity != nil {
            p = motion.isFlat ? .well : .diorama
        } else {
            // No motion sensors (simulator): an opened-flat Duo is a well, everything else a diorama.
            p = (g.fold != nil && (effectiveHinge ?? 0) >= 165) ? .well : .diorama
        }
        return SurfaceLayout(presentation: p, upper: nil, lower: DisplayLayout.window(size: screen), screen: screen)
    }

    /// Where the front camera is: the middle of the screen edge with the deepest safe-area inset (the sensor
    /// housing); top middle when there is none (under-display cameras, iPad).
    private func cameraPoint() -> CGPoint {
        let g = geometry
        let i = g.insets
        let m = max(i.top, i.bottom, i.left, i.right)
        if m < 1 || m == i.top { return CGPoint(x: g.size.width / 2, y: max(4, i.top * 0.5)) }
        if m == i.bottom { return CGPoint(x: g.size.width / 2, y: g.size.height - i.bottom * 0.5) }
        if m == i.left { return CGPoint(x: i.left * 0.5, y: g.size.height / 2) }
        return CGPoint(x: g.size.width - i.right * 0.5, y: g.size.height / 2)
    }

    /// Converts a camera-relative face position to the world of a layout.
    private func eye(fromCamera local: SIMD3<Float>, layout l: SurfaceLayout) -> SIMD3<Float> {
        let g = geometry
        let c = cameraPoint()
        let W = g.size.width, H = g.size.height
        if l.presentation == .stage, let fold = g.fold, let upper = l.upper {
            if c.y < fold.minY {
                return CameraMount.eye(local, on: upper, u: Float(c.x / W), v: Float((fold.minY - c.y) / max(fold.minY, 1)))
            }
            return CameraMount.eye(local, on: l.lower, u: Float(c.x / W), v: Float((H - c.y) / max(H - fold.maxY, 1)))
        }
        return CameraMount.eye(local, on: l.lower, u: Float(c.x / W), v: Float(1 - c.y / H))
    }

    /// A tap in HoloView coordinates on one of its scene views.
    func tap(at point: CGPoint, in view: SCNView, viewPoint: CGPoint) {
        let hits = view.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
        if let h = hits.first, world.isCharacter(h.node) {
            world.tapCharacter()
            return
        }
        guard let l = world.layout else { return }
        if l.presentation == .stage {
            if let h = hits.first { world.tapFloor(at: SIMD3(h.worldCoordinates.x, h.worldCoordinates.y, h.worldCoordinates.z)) }
        } else {
            let u = Float(viewPoint.x / max(geometry.size.width, 1)), v = Float(1 - viewPoint.y / max(geometry.size.height, 1))
            world.tapGlass(at: l.lower.point(u, v))
            Haptics.shared.tap()
        }
    }

    // MARK: Frame

    func tick(t: Double, dt: Float) {
        if let want = desiredLayout(), want != lastLayout {
            lastLayout = want
            world.request(want)
        }
        guard let l = world.layout else { return }
        if l.presentation != lastPresentation {
            lastPresentation = l.presentation
            presentation = l.presentation
            viewers.reset()
            resetSimulated(for: l.presentation)
            tracker.setContext(interface: geometry.interface, key: contextKey)
        }

        // Viewers: simulated, or from the newest camera frame.
        var events: [ViewerEvent] = []
        if simulate {
            var a = simA
            if demoOrbit { a += SIMD3(0.09 * Float(sin(t * 0.45)), 0.03 * Float(sin(t * 0.31)), 0) }
            var dets = [Detection(position: a, looking: simALooking)]
            if simBOn { dets.append(Detection(position: simB, looking: simBLooking)) }
            events = viewers.update(dets, t: t)
        } else if let f = latestFrame, !frameConsumed {
            frameConsumed = true
            let dets = f.faces.map { box -> Detection in
                let local = f.camera.position(of: box)
                return Detection(position: eye(fromCamera: local, layout: l), looking: abs(box.yaw ?? 0) < 0.42)
            }
            events = viewers.update(dets, t: f.time)
        } else if tracking != .running {
            events = viewers.update([], t: t)
        }
        let count = viewers.confirmed.count
        if count != viewerCount { viewerCount = count }
        for e in events { handle(e) }

        // The rendering eye.
        let neutral = neutralEye(l.presentation)
        var fallback = neutral
        if l.presentation.isWindow, let tilt = motion.tiltEye(neutral: neutral) { fallback = tilt }
        let fb = fallbackEye.step(to: fallback, dt: dt)
        let target: SIMD3<Float>
        if let p = viewers.primary, p.confirmed {
            target = p.position
        } else {
            target = fb
        }
        let renderEye = blender.update(target: target, id: viewers.primary?.confirmed == true ? viewers.primaryID : nil, t: t)
        let attention = viewers.attention.flatMap { $0.confirmed ? $0.position : nil }
        let smoothEye = eyeSmooth.step(to: renderEye, dt: dt)
        world.update(t: t, dt: dt, eye: smoothEye, attention: attention, beat: musicOn ? Synth.shared.beat : nil)
    }

    private func neutralEye(_ p: Presentation) -> SIMD3<Float> {
        switch p {
        case .stage: return SIMD3(0, 0.21, 0.36)
        case .well: return SIMD3(0, -0.1, 0.3)
        case .diorama: return SIMD3(0, -0.02, 0.32)
        }
    }

    private func resetSimulated(for p: Presentation) {
        switch p {
        case .stage: simA = SIMD3(0, 0.2, 0.36); simB = SIMD3(0.2, 0.15, 0.32)
        case .well: simA = SIMD3(0, -0.1, 0.3); simB = SIMD3(0.12, 0.12, 0.28)
        case .diorama: simA = SIMD3(0, -0.02, 0.32); simB = SIMD3(0.14, 0.0, 0.3)
        }
    }

    // MARK: Events

    private func handle(_ e: ViewerEvent) {
        switch e {
        case .arrived:
            if !greetedFirst {
                greetedFirst = true
                world.greetNewcomer()
            }
        case .secondArrived:
            world.greetNewcomer()
            ReviewGate.delight()
            if ReviewGate.shouldAsk() { after(3) { self.askReview = true } }
        case .left, .primaryChanged:
            break
        }
    }

    private func handle(_ e: WorldEvent) {
        let voice = Double(world.character.voice)
        let base = 72 + 12 * log2(voice)
        switch e {
        case .knock(let s):
            Haptics.shared.knock(s)
            Synth.shared.sfx(.knock, midi: 86 + Double(Int.random(in: 0...4)), vel: 0.25 + 0.4 * s, pan: Float.random(in: -0.4...0.4), dur: 0.08)
        case .landed:
            Haptics.shared.land()
            Synth.shared.sfx(.kick, midi: 38, vel: 0.6, dur: 0.3)
            ReviewGate.delight()
        case .wave:
            Haptics.shared.wave()
            Synth.shared.sfx(.chirp, midi: base, vel: 0.5, dur: 0.12)
            after(0.16) { Synth.shared.sfx(.chirp, midi: base + 4, vel: 0.5, dur: 0.14) }
        case .giggle:
            Haptics.shared.tap()
            for k in 0..<3 {
                after(0.09 * Double(k)) { Synth.shared.sfx(.chirp, midi: base + 5 + Double(k * 2), vel: 0.35, dur: 0.07) }
            }
        case .appear:
            Haptics.shared.soft()
            for (k, n) in [84.0, 88, 91, 96].enumerated() {
                after(0.06 * Double(k)) { Synth.shared.sfx(.celesta, midi: n, vel: 0.3, pan: Float(k) * 0.2 - 0.3, dur: 0.4) }
            }
        case .fall:
            Haptics.shared.fall()
            for k in 0..<4 {
                after(0.5 + 0.1 * Double(k)) { Synth.shared.sfx(.chirp, midi: base + 7 - Double(k * 3), vel: 0.35, dur: 0.1) }
            }
        case .sparkle:
            Synth.shared.sfx(.celesta, midi: 91, vel: 0.25, pan: 0.2, dur: 0.3)
        }
    }

    private func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            body()
        }
    }

    /// Plays the opening flourish once the scene first appears.
    func firstAppear() {
        handle(.appear)
    }
}
