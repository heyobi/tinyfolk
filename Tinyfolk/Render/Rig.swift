import SceneKit
import UIKit

/// A small jointed puppet. Everything is built in character units (feet at y = 0, about 1 tall, facing +z) and the
/// root is scaled to the real size. The brain's `Pose` drives the joints every frame.
final class Rig {
    let root = SCNNode()        // on the ground; facing and scale
    let mover = SCNNode()       // hop, float, spin
    let body = SCNNode()        // upper body: bob, squash, lean, roll, twist
    let head = SCNNode()        // neck pivot
    let armPlus = SCNNode()     // shoulder on +x (the character's left, the viewer's right)
    let armMinus = SCNNode()
    let legPlus = SCNNode()
    let legMinus = SCNNode()
    var eyes: [SCNNode] = []
    var headHeight: Float = 0.72   // where the eyes are, for look-at maths
    var baseScale: Float = 1

    init() {
        root.addChildNode(mover)
        mover.addChildNode(body)
        mover.addChildNode(legPlus)
        mover.addChildNode(legMinus)
        body.addChildNode(head)
        body.addChildNode(armPlus)
        body.addChildNode(armMinus)
        head.position = SCNVector3(0, 0.5, 0)
        armPlus.position = SCNVector3(0.2, 0.43, 0)
        armMinus.position = SCNVector3(-0.2, 0.43, 0)
        legPlus.position = SCNVector3(0.085, 0.17, 0)
        legMinus.position = SCNVector3(-0.085, 0.17, 0)
    }

    func apply(_ p: Pose, appear: Float = 1) {
        mover.position = SCNVector3(0, p.hop + p.float, 0)
        mover.eulerAngles = SCNVector3(0, p.spin, 0)
        body.position = SCNVector3(0, p.bob, 0)
        body.scale = SCNVector3(1 + p.squash * 0.6, 1 - p.squash, 1 + p.squash * 0.6)
        body.eulerAngles = SCNVector3(p.lean, p.twist, p.roll)
        head.eulerAngles = SCNVector3(p.headPitch, p.headYaw, p.headRoll)
        armPlus.eulerAngles = SCNVector3(p.swingPlus, 0, p.armPlus)
        armMinus.eulerAngles = SCNVector3(p.swingMinus, 0, -p.armMinus)
        legPlus.eulerAngles = SCNVector3(p.legPlus, 0, 0)
        legMinus.eulerAngles = SCNVector3(-p.legMinus, 0, 0)
        let open = max(0.08, p.eyesOpen)
        for e in eyes { e.scale = SCNVector3(1, open, 1) }
        let s = baseScale * max(0.001, appear)
        root.scale = SCNVector3(s, s, s)
    }
}

// MARK: - Geometry helpers

enum Mat {
    static func clay(_ c: UIColor, rough: CGFloat = 0.62, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    static func glow(_ c: UIColor, intensity: CGFloat = 1.6) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c
        m.emission.contents = c
        m.emission.intensity = intensity
        return m
    }

    static func glass(_ tint: UIColor, alpha: CGFloat = 0.25) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = tint.withAlphaComponent(alpha)
        m.roughness.contents = 0.05
        m.metalness.contents = 0.0
        m.transparencyMode = .dualLayer
        m.fresnelExponent = 2.2
        m.isDoubleSided = false
        m.blendMode = .alpha
        return m
    }

    static func additive(_ image: Any, intensity: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.diffuse.intensity = intensity
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }
}

@discardableResult
func part(_ g: SCNGeometry, _ m: SCNMaterial, _ parent: SCNNode, at p: SCNVector3 = SCNVector3Zero,
          scale s: SCNVector3 = SCNVector3(1, 1, 1), rot r: SCNVector3 = SCNVector3Zero, shadow: Bool = true) -> SCNNode {
    g.materials = [m]
    let n = SCNNode(geometry: g)
    n.position = p
    n.scale = s
    n.eulerAngles = r
    n.castsShadow = shadow
    parent.addChildNode(n)
    return n
}

func sphere(_ r: CGFloat, seg: Int = 32) -> SCNSphere { let s = SCNSphere(radius: r); s.segmentCount = seg; return s }
func capsule(_ r: CGFloat, _ h: CGFloat) -> SCNCapsule { SCNCapsule(capRadius: r, height: h) }
func cone(_ top: CGFloat, _ bottom: CGFloat, _ h: CGFloat) -> SCNCone { SCNCone(topRadius: top, bottomRadius: bottom, height: h) }
func cyl(_ r: CGFloat, _ h: CGFloat) -> SCNCylinder { SCNCylinder(radius: r, height: h) }
func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ c: CGFloat) -> SCNBox { SCNBox(width: w, height: h, length: l, chamferRadius: c) }
func torus(_ r: CGFloat, _ pipe: CGFloat) -> SCNTorus { SCNTorus(ringRadius: r, pipeRadius: pipe) }

func v(_ x: Float, _ y: Float, _ z: Float) -> SCNVector3 { SCNVector3(x, y, z) }

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

/// Shared face parts: glossy eyes with a catch-light (blinkable), optional cheeks.
enum Face {
    static func eyes(_ rig: Rig, on parent: SCNNode, y: Float, z: Float, spread: Float = 0.095, size: CGFloat = 0.048,
                     color: UIColor = UIColor(hex: 0x1d1a24), glowing: Bool = false) {
        for sx: Float in [-1, 1] {
            let pivot = SCNNode()
            pivot.position = v(sx * spread, y, z)
            parent.addChildNode(pivot)
            let m = glowing ? Mat.glow(color, intensity: 1.8) : Mat.clay(color, rough: 0.18)
            part(sphere(size), m, pivot, scale: v(0.9, 1.15, 0.55), shadow: false)
            if !glowing {
                part(sphere(size * 0.32, seg: 12), Mat.glow(.white, intensity: 1.2), pivot,
                     at: v(Float(size) * 0.3, Float(size) * 0.42, Float(size) * 0.42), shadow: false)
            }
            rig.eyes.append(pivot)
        }
        rig.headHeight = 0.5 + y
    }

    static func cheeks(on parent: SCNNode, y: Float, z: Float, spread: Float = 0.15, color: UIColor = UIColor(hex: 0xff8fa3)) {
        let m = Mat.clay(color.withAlphaComponent(0.55), rough: 0.9)
        m.blendMode = .alpha
        for sx: Float in [-1, 1] {
            part(sphere(0.035, seg: 16), m, parent, at: v(sx * spread, y, z), scale: v(1.2, 0.7, 0.3), shadow: false)
        }
    }

    static func smile(on parent: SCNNode, y: Float, z: Float, color: UIColor = UIColor(hex: 0x3a2730)) {
        let t = torus(0.03, 0.006)
        let n = part(t, Mat.clay(color, rough: 0.4), parent, at: v(0, y, z), rot: v(.pi / 2, 0, 0), shadow: false)
        // Keep only the lower half visible by squashing into the face.
        n.scale = v(1, 1, 0.5)
    }
}
