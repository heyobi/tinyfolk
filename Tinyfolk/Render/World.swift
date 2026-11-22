import SceneKit
import UIKit
import simd

/// How the scene is presented right now.
enum Presentation: Equatable {
    /// Half-open iPhone Duo standing like a small laptop: the upper half is a window onto the backdrop, the lower
    /// half onto the floor, and the character stands at the fold.
    case stage
    /// A flat screen lying down: a well beneath the glass.
    case well
    /// A flat screen held upright: a little diorama box behind the glass.
    case diorama

    var isWindow: Bool { self != .stage }
}

/// Physical layout of the display surfaces for the current presentation.
struct SurfaceLayout: Equatable {
    var presentation: Presentation
    /// Stage: upper and lower halves. Window: `lower` is the whole screen and `upper` is nil.
    var upper: Surface?
    var lower: Surface
    /// Window presentations: screen size in metres.
    var screen: SIMD2<Float>
}

enum WorldEvent {
    case knock(strength: Float)       // a lantern touched the glass from below
    case landed                       // the character landed at the bottom of the well
    case wave                         // waved at a newcomer
    case giggle
    case appear
    case fall
    case sparkle
}

/// The whole 3-D scene: room, character, light, motes, lanterns and transitions. Two cameras (one per display
/// surface) get off-axis projections from the viewer's eye every frame. All motion is computed here from one clock,
/// so both views of the shared scene always agree at the fold.
final class World {
    let scene = SCNScene()
    let camUpper = SCNNode()
    let camLower = SCNNode()

    private let room = SCNNode()
    private let floorNode = SCNNode()
    private let wallNode = SCNNode()
    private let box = SCNNode()
    private var boxFaces: [String: SCNNode] = [:]
    let ground = SCNNode()
    private let propsNode = SCNNode()
    private let effects = SCNNode()
    private let ringNode = SCNNode()
    private var ringMaterial = SCNMaterial()
    private let shaftNode = SCNNode()
    private let holeNode = SCNNode()
    private let keyLight = SCNNode()
    private let rimLight = SCNNode()
    private let ambient = SCNNode()
    private let floorMat = SCNMaterial()
    private let wallMat = SCNMaterial()

    private(set) var rig: Rig
    private(set) var character: CharacterSpec
    private(set) var stage: StageSpec
    private var brain: Brain

    var events: ((WorldEvent) -> Void)?

    /// Presentation actually shown (may lag the requested one during a transition).
    private(set) var presentation: Presentation = .diorama
    private(set) var layout: SurfaceLayout?
    private var transition: Transition?

    private struct Mote { var node: SCNNode; var pos: SIMD3<Float>; var vel: SIMD3<Float>; var phase: Float }
    private var motes: [Mote] = []
    private struct Spark { var node: SCNNode; var pos: SIMD3<Float>; var vel: SIMD3<Float>; var born: Double; var life: Double }
    private var sparks: [Spark] = []
    private struct Lantern { var node: SCNNode; var pos: SIMD3<Float>; var vel: SIMD3<Float>; var born: Double; var touched: Bool; var seed: Float }
    private var lanterns: [Lantern] = []
    private struct Ripple { var node: SCNNode; var born: Double }
    private var ripples: [Ripple] = []

    private var lookOverride: (point: SIMD3<Float>, until: Double)?
    private var nextLantern: Double = 3
    private var time: Double = 0
    private var pendingCharacter: CharacterSpec?
    /// Height of the glass above the ground in ground units (well), or a large number.
    private var ceiling: Float = 1.8

    /// Character height in metres for each presentation.
    static let stageCharacterHeight: Float = 0.064

    private enum TransitionKind { case fallIntoWell, riseToStage, swap }
    private struct Transition { var kind: TransitionKind; var started: Double; var target: Presentation }

    init(character: CharacterSpec, stage: StageSpec) {
        self.character = character
        self.stage = stage
        self.rig = character.makeRig()
        self.brain = Brain(style: character.style, seed: UInt64(abs(character.id.hashValue % 10_000) + 3))
        buildStatic()
        applyStage()
        ground.addChildNode(rig.root)
        rig.apply(Pose(), appear: 0.001)
    }

    private var started = false

    // MARK: Building

    private func makeCamera() -> SCNCamera {
        let c = SCNCamera()
        c.automaticallyAdjustsZRange = false
        c.zNear = 0.005
        c.zFar = 4
        c.wantsHDR = true
        c.wantsExposureAdaptation = false
        c.bloomIntensity = 0.9
        c.bloomThreshold = 0.85
        c.bloomBlurRadius = 10
        c.vignettingIntensity = 0
        return c
    }

    private func buildStatic() {
        camUpper.camera = makeCamera()
        camLower.camera = makeCamera()
        scene.rootNode.addChildNode(camUpper)
        scene.rootNode.addChildNode(camLower)

        // Stage room: a floor that continues across the fold and a backdrop behind it.
        floorMat.lightingModel = .lambert
        floorMat.diffuse.wrapS = .repeat
        floorMat.diffuse.wrapT = .repeat
        floorMat.transparent.contents = Tex.edgeFade
        floorMat.transparencyMode = .aOne
        floorMat.writesToDepthBuffer = true
        wallMat.lightingModel = .lambert
        let fp = SCNPlane(width: 0.42, height: 0.42)
        fp.materials = [floorMat]
        floorNode.geometry = fp
        floorNode.eulerAngles = v(-.pi / 2, 0, 0)
        floorNode.position = v(0, 0, -0.02)
        floorNode.castsShadow = false
        room.addChildNode(floorNode)
        let wp = SCNPlane(width: 0.4, height: 0.3)
        wp.materials = [wallMat]
        wallNode.geometry = wp
        wallNode.position = v(0, 0.13, -0.058)
        wallNode.castsShadow = false
        room.addChildNode(wallNode)
        scene.rootNode.addChildNode(room)

        // Window box: five inner faces, sized when the layout is known.
        for name in ["back", "bottom", "top", "left", "right"] {
            let n = SCNNode(geometry: SCNPlane(width: 0.1, height: 0.1))
            n.castsShadow = false
            boxFaces[name] = n
            box.addChildNode(n)
        }
        scene.rootNode.addChildNode(box)

        scene.rootNode.addChildNode(ground)
        ground.addChildNode(propsNode)
        ground.addChildNode(effects)

        // Contact shadow, glowing ring and its halo under the character.
        let shadowMat = SCNMaterial()
        shadowMat.lightingModel = .constant
        shadowMat.diffuse.contents = Tex.contactShadow
        shadowMat.blendMode = .alpha
        shadowMat.writesToDepthBuffer = false
        let sp = SCNPlane(width: 0.95, height: 0.95)
        sp.materials = [shadowMat]
        let shadowNode = SCNNode(geometry: sp)
        shadowNode.eulerAngles = v(-.pi / 2, 0, 0)
        shadowNode.position = v(0, 0.012, 0)
        shadowNode.renderingOrder = 5
        shadowNode.castsShadow = false
        ground.addChildNode(shadowNode)
        ground.addChildNode(ringNode)

        // A dark hole that opens in the floor when the phone is opened flat.
        let hm = SCNMaterial()
        hm.lightingModel = .constant
        hm.diffuse.contents = UIColor.black
        let hp = SCNCylinder(radius: 0.5, height: 0.004)
        hp.materials = [hm]
        holeNode.geometry = hp
        holeNode.position = v(0, 0.016, 0)
        holeNode.scale = v(0.001, 1, 0.001)
        holeNode.isHidden = true
        holeNode.castsShadow = false
        ground.addChildNode(holeNode)

        // Lights.
        let key = SCNLight()
        key.type = .directional
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowColor = UIColor(white: 0, alpha: 0.5)
        key.shadowRadius = 4
        key.shadowSampleCount = 12
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.automaticallyAdjustsShadowProjection = false
        key.orthographicScale = 0.12
        key.zNear = 0.01
        key.zFar = 1.5
        keyLight.light = key
        scene.rootNode.addChildNode(keyLight)
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 650
        rimLight.light = rim
        scene.rootNode.addChildNode(rimLight)
        let amb = SCNLight()
        amb.type = .ambient
        ambient.light = amb
        scene.rootNode.addChildNode(ambient)

        // Motes.
        let moteGeo = sphere(0.014, seg: 6)
        for i in 0..<34 {
            let n = SCNNode(geometry: moteGeo)
            n.castsShadow = false
            effects.addChildNode(n)
            let f = Float(i)
            motes.append(Mote(node: n, pos: SIMD3(sin(f * 2.3) * 1.3, 0.2 + fmodf(f * 0.37, 1.4), cos(f * 1.7) * 0.8 - 0.2),
                              vel: .zero, phase: f * 0.77))
        }
    }

    private func applyStage() {
        let s = stage
        scene.background.contents = s.background
        floorMat.diffuse.contents = s.floor()
        wallMat.diffuse.contents = s.wall()
        scene.lightingEnvironment.contents = Tex.environment(top: s.ambient, bottom: s.background)
        scene.lightingEnvironment.intensity = 0.9
        keyLight.light?.color = s.key
        keyLight.light?.intensity = s.keyIntensity
        rimLight.light?.color = s.ring
        ambient.light?.color = s.ambient
        ambient.light?.intensity = s.ambientIntensity

        ringNode.childNodes.forEach { $0.removeFromParentNode() }
        ringMaterial = Mat.glow(s.ring, intensity: 1.8)
        let t = torus(0.42, 0.012)
        t.ringSegmentCount = 96
        t.materials = [ringMaterial]
        let rn = SCNNode(geometry: t)
        rn.position = v(0, 0.012, 0)
        rn.castsShadow = false
        ringNode.addChildNode(rn)
        let halo = SCNPlane(width: 1.25, height: 1.25)
        halo.materials = [Mat.additive(Tex.glow(s.ring), intensity: 0.32)]
        let hn = SCNNode(geometry: halo)
        hn.eulerAngles = v(-.pi / 2, 0, 0)
        hn.position = v(0, 0.01, 0)
        hn.castsShadow = false
        hn.renderingOrder = 6
        ringNode.addChildNode(hn)

        shaftNode.removeFromParentNode()
        shaftNode.childNodes.forEach { $0.removeFromParentNode() }
        if s.shaft {
            let c = cone(0.08, 0.6, 2.2)
            c.materials = [Mat.additive(Tex.shaft(s.key), intensity: 0.35)]
            let n = SCNNode(geometry: c)
            n.position = v(0, 1.1, 0)
            n.castsShadow = false
            n.renderingOrder = 7
            shaftNode.addChildNode(n)
            ground.addChildNode(shaftNode)
        }

        propsNode.childNodes.forEach { $0.removeFromParentNode() }
        s.props(propsNode)

        let moteMat = Mat.glow(s.mote, intensity: s.motes == .fall && s.id == "winter" ? 1.0 : 1.6)
        for m in motes { m.node.geometry?.materials = [moteMat] }
        if let l = layout { configure(l, force: true) }
    }

    func setStage(_ s: StageSpec) {
        guard s.id != stage.id else { return }
        stage = s
        applyStage()
        burst(at: SIMD3(0, 0.5, 0), count: 22, color: s.ring)
        events?(.sparkle)
    }

    func setCharacter(_ c: CharacterSpec) {
        guard c.id != character.id else { return }
        burst(at: SIMD3(0, 0.5, 0), count: 26, color: stage.ring)
        rig.root.removeFromParentNode()
        character = c
        rig = c.makeRig()
        brain = Brain(style: c.style, seed: UInt64(abs(c.id.hashValue % 10_000) + 3))
        ground.addChildNode(rig.root)
        brain.perform(.appear(started: time))
        events?(.appear)
    }

    // MARK: Layout

    /// Requests a layout. Switching between stage and well runs the trapdoor transition first.
    func request(_ l: SurfaceLayout) {
        if transition == nil, let current = layout, current.presentation != l.presentation {
            if current.presentation == .stage && l.presentation == .well {
                transition = Transition(kind: .fallIntoWell, started: time, target: .well)
                events?(.fall)
                pendingLayout = l
                return
            }
            if current.presentation == .well && l.presentation == .stage {
                transition = Transition(kind: .riseToStage, started: time, target: .stage)
                pendingLayout = l
                return
            }
            transition = Transition(kind: .swap, started: time, target: l.presentation)
            pendingLayout = l
            return
        }
        if transition != nil { pendingLayout = l; return }
        configure(l)
    }

    private var pendingLayout: SurfaceLayout?

    private func configure(_ l: SurfaceLayout, force: Bool = false) {
        let changed = layout?.presentation != l.presentation || layout?.screen != l.screen || force
        layout = l
        presentation = l.presentation
        guard changed else { return }
        switch l.presentation {
        case .stage:
            room.isHidden = false
            box.isHidden = true
            let s = Self.stageCharacterHeight
            ground.simdTransform = matrix_identity_float4x4
            ground.simdPosition = SIMD3(0, 0, 0.013)
            ground.simdScale = SIMD3(repeating: s)
            ceiling = 3
            floorMat.diffuse.contentsTransform = SCNMatrix4MakeScale(0.42 / stage.floorTile, 0.42 / stage.floorTile, 1)
            scene.fogStartDistance = 0.5
            scene.fogEndDistance = 1.3
            scene.fogColor = stage.background
            keyLight.light?.orthographicScale = 0.13
        case .well, .diorama:
            room.isHidden = true
            box.isHidden = false
            scene.fogStartDistance = 0
            scene.fogEndDistance = 0
            let w = l.screen.x, h = l.screen.y
            let m = min(w, h)
            let depth = min(max(m * 0.75, 0.05), 0.15)
            let ch = min(max(m * 0.5, 0.032), 0.1)
            buildBox(w: w, h: h, d: depth, well: l.presentation == .well)
            if l.presentation == .well {
                // Ground at the bottom of the well; up points out of the glass, the backdrop toward the top edge.
                ground.simdTransform = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)))
                ground.simdPosition = SIMD3(0, 0, -depth)
                ceiling = depth / ch - 0.08
            } else {
                ground.simdTransform = matrix_identity_float4x4
                ground.simdPosition = SIMD3(0, -h / 2, -depth * 0.5)
                ceiling = 3
            }
            ground.simdScale = SIMD3(repeating: ch)
            keyLight.light?.orthographicScale = CGFloat(max(w, h) * 0.7)
        }
        placeLights()
    }

    private func buildBox(w: Float, h: Float, d: Float, well: Bool) {
        func face(_ name: String, _ width: Float, _ height: Float, _ pos: SIMD3<Float>, _ euler: SIMD3<Float>, floor: Bool) {
            guard let n = boxFaces[name], let p = n.geometry as? SCNPlane else { return }
            p.width = CGFloat(width)
            p.height = CGFloat(height)
            let m = SCNMaterial()
            m.lightingModel = .lambert
            if floor {
                m.diffuse.contents = floorMat.diffuse.contents
                m.diffuse.wrapS = .repeat
                m.diffuse.wrapT = .repeat
                m.diffuse.contentsTransform = SCNMatrix4MakeScale(width / stage.floorTile, height / stage.floorTile, 1)
            } else {
                m.diffuse.contents = wallMat.diffuse.contents
                // Side walls get a darker, softer copy of the backdrop so the depth reads.
                m.multiply.contents = UIColor(white: name == "back" ? 1 : 0.62, alpha: 1)
            }
            p.materials = [m]
            n.simdPosition = pos
            n.simdEulerAngles = euler
        }
        // Planes face +z by default; each face is turned to look into the box.
        face("back", w, h, SIMD3(0, 0, -d), SIMD3(0, 0, 0), floor: well)
        face("bottom", w, d, SIMD3(0, -h / 2, -d / 2), SIMD3(-.pi / 2, 0, 0), floor: !well)
        face("top", w, d, SIMD3(0, h / 2, -d / 2), SIMD3(.pi / 2, 0, 0), floor: false)
        face("left", d, h, SIMD3(-w / 2, 0, -d / 2), SIMD3(0, .pi / 2, 0), floor: false)
        face("right", d, h, SIMD3(w / 2, 0, -d / 2), SIMD3(0, -.pi / 2, 0), floor: false)
    }

    private func placeLights() {
        // Key light from above, slightly in front and to the left of the character, in ground space.
        let gw = ground.simdWorldTransform
        func world(_ p: SIMD3<Float>) -> SIMD3<Float> { let q = gw * SIMD4(p, 1); return SIMD3(q.x, q.y, q.z) }
        let target = world(SIMD3(0, 0.45, 0))
        keyLight.simdPosition = world(SIMD3(-1.6, 6, 3.2))
        keyLight.simdLook(at: target)
        rimLight.simdPosition = world(SIMD3(1.5, 2.5, -4))
        rimLight.simdLook(at: target)
    }

    // MARK: Interaction

    /// The character looks at a point (world coordinates) for a moment.
    func look(at p: SIMD3<Float>, for seconds: Double = 1.6) { lookOverride = (p, time + seconds) }

    func greetNewcomer() {
        brain.perform(.wave(started: time))
        burst(at: SIMD3(0.35, 1.05, 0.1), count: 12, color: stage.ring)
        events?(.wave)
    }

    func tapCharacter() {
        brain.perform(.giggle(started: time))
        events?(.giggle)
    }

    func isCharacter(_ node: SCNNode) -> Bool {
        var n: SCNNode? = node
        while let c = n { if c === rig.root { return true }; n = c.parent }
        return false
    }

    /// A tap on the floor (stage) at a world point.
    func tapFloor(at p: SIMD3<Float>) {
        let local = ground.simdConvertPosition(p, from: nil)
        burst(at: SIMD3(local.x, 0.05, local.z), count: 10, color: stage.ring)
        look(at: p)
        events?(.sparkle)
    }

    /// A tap on the glass (window presentations) at a world point on the screen plane.
    func tapGlass(at p: SIMD3<Float>) {
        let r = SCNNode(geometry: {
            let t = torus(0.004, 0.0006)
            t.ringSegmentCount = 64
            t.pipeSegmentCount = 8
            t.materials = [Mat.glow(stage.ring, intensity: 1.4)]
            return t
        }())
        r.simdPosition = SIMD3(p.x, p.y, -0.001)
        r.eulerAngles = v(.pi / 2, 0, 0)
        r.castsShadow = false
        scene.rootNode.addChildNode(r)
        ripples.append(Ripple(node: r, born: time))
        look(at: p, for: 2)
        // Lanterns near the tap bob away from the glass.
        let local = ground.simdConvertPosition(p, from: nil)
        for i in lanterns.indices {
            let d = simd_distance(SIMD2(lanterns[i].pos.x, lanterns[i].pos.z), SIMD2(local.x, local.z))
            if d < 0.8 { lanterns[i].vel.y -= 0.9 * (1 - d / 0.8); lanterns[i].touched = false }
        }
        if presentation == .well && lanterns.count < 7 && !brain.isBusy {
            brain.perform(.offer(started: time))
            nextLantern = time + 0.7
        }
    }

    // MARK: Frame update

    /// - Parameters:
    ///   - eye: the rendering eye (world coordinates of the current presentation).
    ///   - attention: where the character should look (a viewer's eye), or nil.
    ///   - beat: music position in beats, nil when silent.
    func update(t: Double, dt: Float, eye: SIMD3<Float>, attention: SIMD3<Float>?, beat: Double?) {
        time = t
        if !started {
            started = true
            brain.perform(.appear(started: t + 0.35))
            nextLantern = t + 3
            after(0.35) { [weak self] in
                guard let self else { return }
                self.burst(at: SIMD3(0, 0.45, 0), count: 24, color: self.stage.ring)
                self.events?(.appear)
            }
        }
        runTransition(t)
        runScheduled(t)
        guard let l = layout else { return }

        // Cameras.
        if let up = l.upper {
            let o = OffAxis(eye: eye, surface: up)
            camUpper.simdTransform = o.cameraTransform
            camUpper.camera?.projectionTransform = SCNMatrix4(o.projection)
        }
        let o = OffAxis(eye: eye, surface: l.lower)
        camLower.simdTransform = o.cameraTransform
        camLower.camera?.projectionTransform = SCNMatrix4(o.projection)

        // Where to look.
        var lookPoint = attention
        if let lo = lookOverride { if t < lo.until { lookPoint = lo.point } else { lookOverride = nil } }
        var look: (yaw: Float, pitch: Float)?
        if let p = lookPoint {
            let local = ground.simdConvertPosition(p, from: nil)
            let dx = local.x, dz = local.z, dy = local.y - rig.headHeight
            look = (atan2(dx, max(dz, 0.05)), atan2(dy, sqrt(dx * dx + dz * dz)))
            if dz < 0.05 { look!.yaw = dx > 0 ? 1.2 : -1.2 }
        }

        var pose = brain.update(t: t, dt: dt, look: look, beat: beat)
        let appear = brain.appearScale(t: t)
        applyTransitionPose(&pose, t: t)
        if character.floats { pose.float += 0.08 + sin(Float(t) * 1.7) * 0.025 }
        rig.apply(pose, appear: appear)
        if let tr = transition { rig.mover.position.y += transitionOffset(tr, t: t) }

        // Ring breathing.
        var ringGlow = 1.5 + 0.5 * sin(t * 2.2)
        if let b = beat { ringGlow += 0.6 * pow(1 - b.truncatingRemainder(dividingBy: 1), 3) }
        ringMaterial.emission.intensity = CGFloat(ringGlow)

        updateMotes(t: t, dt: dt)
        updateSparks(t: t, dt: dt)
        updateLanterns(t: t, dt: dt)
        updateRipples(t: t)
    }

    private func updateMotes(t: Double, dt: Float) {
        let top = min(1.7, ceiling - 0.05)
        for i in motes.indices {
            var m = motes[i]
            let ph = Float(t) * 0.6 + m.phase
            switch stage.motes {
            case .drift:
                m.vel = SIMD3(sin(ph * 0.7) * 0.05, sin(ph * 1.1) * 0.04, cos(ph * 0.6) * 0.04)
            case .rise:
                m.vel = SIMD3(sin(ph * 2) * 0.03, 0.12 + 0.05 * sin(m.phase), 0)
            case .fall:
                m.vel = SIMD3(sin(ph * 1.3) * 0.08, -0.1 - 0.04 * sin(m.phase), cos(ph) * 0.03)
            }
            m.pos += m.vel * dt
            if m.pos.y > top { m.pos.y = 0.05 }
            if m.pos.y < 0.03 { m.pos.y = top }
            if abs(m.pos.x) > 1.5 { m.pos.x = -m.pos.x * 0.95 }
            if m.pos.z > 0.7 || m.pos.z < -1.0 { m.pos.z = max(-0.95, min(0.65, -m.pos.z * 0.5)) }
            m.node.simdPosition = m.pos
            let tw = 0.55 + 0.45 * sin(Float(t) * 2.3 + m.phase * 3)
            m.node.opacity = CGFloat(tw)
            motes[i] = m
        }
    }

    func burst(at p: SIMD3<Float>, count: Int, color: UIColor) {
        let mat = Mat.glow(color, intensity: 2)
        let geo = sphere(0.022, seg: 6)
        geo.materials = [mat]
        for i in 0..<count {
            let n = SCNNode(geometry: geo)
            n.castsShadow = false
            effects.addChildNode(n)
            let a = Float(i) / Float(count) * 2 * .pi + Float(time)
            let up = 0.6 + Float((i * 37) % 10) / 10
            sparks.append(Spark(node: n, pos: p, vel: SIMD3(cos(a) * 0.9, up, sin(a) * 0.9), born: time, life: 0.9))
        }
    }

    private func updateSparks(t: Double, dt: Float) {
        sparks.removeAll { s in
            let dead = t - s.born > s.life
            if dead { s.node.removeFromParentNode() }
            return dead
        }
        for i in sparks.indices {
            sparks[i].vel.y -= 1.6 * dt
            sparks[i].vel *= (1 - 1.5 * dt)
            sparks[i].pos += sparks[i].vel * dt
            let u = Float((t - sparks[i].born) / sparks[i].life)
            sparks[i].node.simdPosition = sparks[i].pos
            sparks[i].node.opacity = CGFloat(1 - u * u)
            let s = 1 - u * 0.6
            sparks[i].node.simdScale = SIMD3(repeating: s)
        }
    }

    // MARK: Lanterns (well only)

    private func makeLantern() -> SCNNode {
        let n = SCNNode()
        let paper = SCNMaterial()
        paper.lightingModel = .constant
        paper.diffuse.contents = UIColor(hex: 0xFFC56B)
        paper.emission.contents = UIColor(hex: 0xFFB04A)
        paper.emission.intensity = 1.8
        let body = SCNNode(geometry: { let c = cyl(0.075, 0.12); c.materials = [paper]; return c }())
        body.castsShadow = false
        n.addChildNode(body)
        let cap = Mat.clay(UIColor(hex: 0x7A2E22), rough: 0.6)
        for y: Float in [-0.065, 0.065] {
            let c = SCNNode(geometry: { let g = cyl(0.06, 0.012); g.materials = [cap]; return g }())
            c.position = v(0, y, 0)
            n.addChildNode(c)
        }
        let halo = SCNNode(geometry: { let p = SCNPlane(width: 0.5, height: 0.5); p.materials = [Mat.additive(Tex.glow(UIColor(hex: 0xFFB04A)), intensity: 0.5)]; return p }())
        halo.constraints = [SCNBillboardConstraint()]
        halo.castsShadow = false
        halo.renderingOrder = 8
        n.addChildNode(halo)
        return n
    }

    private func updateLanterns(t: Double, dt: Float) {
        guard presentation == .well, transition == nil else {
            if presentation != .well { for l in lanterns { l.node.removeFromParentNode() }; lanterns = [] }
            return
        }
        if t >= nextLantern && lanterns.count < 7 {
            if !brain.isOffering && !brain.isBusy { brain.perform(.offer(started: t)) }
            if case .offer(let s)? = brain.gesture, t - s > 0.55 {
                let n = makeLantern()
                effects.addChildNode(n)
                let seed = Float(lanterns.count) * 1.7 + Float(t.truncatingRemainder(dividingBy: 10))
                lanterns.append(Lantern(node: n, pos: SIMD3(0, 0.72, 0.28), vel: SIMD3(0, 0.25, 0), born: t, touched: false, seed: seed))
                nextLantern = t + 7 + Double(lanterns.count) * 1.5
            }
        }
        let top = ceiling - 0.07
        var remove: [Int] = []
        for i in lanterns.indices {
            var l = lanterns[i]
            let age = Float(t - l.born)
            // Rise with a gentle wobble; drift apart a little.
            l.vel.y += (0.32 - l.vel.y) * min(1, dt * 1.2)
            l.vel.x = sin(age * 0.9 + l.seed) * 0.08
            l.vel.z = cos(age * 0.7 + l.seed * 1.3) * 0.06
            l.pos += l.vel * dt
            l.pos.x = max(-1.2, min(1.2, l.pos.x))
            l.pos.z = max(-1.2, min(1.2, l.pos.z))
            if l.pos.y >= top {
                l.pos.y = top
                if !l.touched {
                    l.touched = true
                    events?(.knock(strength: min(1, max(0.25, l.vel.y * 2.5))))
                }
                l.vel.y = -0.04
            }
            l.node.simdPosition = l.pos
            l.node.eulerAngles = v(sin(age * 1.3 + l.seed) * 0.12, age * 0.2, cos(age * 1.1 + l.seed) * 0.12)
            let fade: Float = age > 22 ? max(0, 1 - (age - 22) / 3) : min(1, age * 3)
            l.node.opacity = CGFloat(fade)
            if age > 25 { remove.append(i) }
            lanterns[i] = l
        }
        for i in remove.reversed() { lanterns[i].node.removeFromParentNode(); lanterns.remove(at: i) }
    }

    private func updateRipples(t: Double) {
        ripples.removeAll { r in
            let u = Float(t - r.born) / 0.9
            if u >= 1 { r.node.removeFromParentNode(); return true }
            let s = 1 + u * 5
            r.node.simdScale = SIMD3(s, s, s)
            r.node.opacity = CGFloat(1 - u)
            return false
        }
    }

    private var scheduled: [(at: Double, body: () -> Void)] = []

    private func after(_ seconds: Double, _ body: @escaping () -> Void) { scheduled.append((time + seconds, body)) }

    private func runScheduled(_ t: Double) {
        guard !scheduled.isEmpty else { return }
        let due = scheduled.filter { $0.at <= t }
        scheduled.removeAll { $0.at <= t }
        for d in due { d.body() }
    }

    // MARK: Transitions

    private func runTransition(_ t: Double) {
        guard let tr = transition else { return }
        let e = t - tr.started
        switch tr.kind {
        case .fallIntoWell:
            if e < 0.5 {
                holeNode.isHidden = false
                let s = Float(e / 0.5) * 0.9 + 0.001
                holeNode.scale = v(s, 1, s)
            } else if e >= 1.15, presentation == .stage, let l = pendingLayout {
                holeNode.isHidden = true
                holeNode.scale = v(0.001, 1, 0.001)
                configure(l)
                pendingLayout = nil
            }
            if e >= 2.6 {
                transition = nil
                events?(.landed)
                burst(at: SIMD3(0, 0.05, 0), count: 18, color: stage.ring)
                brain.perform(.wave(started: t))
                nextLantern = t + 2.2
                if let l = pendingLayout { pendingLayout = nil; request(l) }
            }
        case .riseToStage:
            if e >= 0.45, presentation == .well, let l = pendingLayout {
                configure(l)
                pendingLayout = nil
                burst(at: SIMD3(0, 0.1, 0), count: 22, color: stage.ring)
                events?(.appear)
            }
            if e >= 1.2 {
                transition = nil
                brain.perform(.cheer(started: t))
                if let l = pendingLayout { pendingLayout = nil; request(l) }
            }
        case .swap:
            if e >= 0.2, let l = pendingLayout {
                configure(l)
                pendingLayout = nil
                brain.perform(.appear(started: t))
            }
            if e >= 0.25 {
                transition = nil
                if let l = pendingLayout { pendingLayout = nil; request(l) }
            }
        }
    }

    /// Vertical offset (ground units) of the character during a transition.
    private func transitionOffset(_ tr: Transition, t: Double) -> Float {
        let e = Float(t - tr.started)
        switch tr.kind {
        case .fallIntoWell:
            if presentation == .stage {
                // Wait on the opening hole, then drop.
                let f = max(0, e - 0.55)
                return -4.5 * f * f
            }
            // In the well: drift down from the glass like a feather, landing at 2.6 s.
            let u = min(1, max(0, (e - 1.15) / 1.45))
            let start = ceiling - 0.4
            let ease = 1 - pow(1 - u, 2.2)
            return start * (1 - ease) + sin(u * .pi * 3) * 0.05 * (1 - u)
        case .riseToStage:
            if presentation == .well {
                let u = min(1, e / 0.45)
                return u * u * (ceiling + 0.5)
            }
            let u = min(1, max(0, (e - 0.45) / 0.75))
            // Pops up through the floor with a little overshoot.
            return -1.2 * (1 - u) + sin(u * .pi) * 0.25
        case .swap:
            return 0
        }
    }

    private func applyTransitionPose(_ p: inout Pose, t: Double) {
        guard let tr = transition else { return }
        let e = t - tr.started
        switch tr.kind {
        case .fallIntoWell:
            if e > 0.45 {
                p.armPlus = 2.6 + sin(Float(e) * 18) * 0.25
                p.armMinus = 2.6 + cos(Float(e) * 17) * 0.25
                p.headPitch = -0.5
                p.legPlus = sin(Float(e) * 14) * 0.4
                p.legMinus = cos(Float(e) * 14) * 0.4
                p.eyesOpen = 1.1
            }
            if presentation == .stage && e > 0.55 { p.spin += Float(e - 0.55) * 4 }
        case .riseToStage:
            p.armPlus = 2.5
            p.armMinus = 2.5
            p.headPitch = -0.3
        case .swap:
            break
        }
    }
}
