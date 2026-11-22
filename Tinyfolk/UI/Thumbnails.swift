import SceneKit
import UIKit
import Metal

/// Portraits of the cast for the picker, rendered once with SceneKit's offscreen renderer.
@MainActor
enum Thumbnails {
    private static var cache: [String: UIImage] = [:]
    private static var stageCache: [String: UIImage] = [:]

    static func character(_ spec: CharacterSpec) -> UIImage {
        if let c = cache[spec.id] { return c }
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let rig = spec.makeRig()
        var pose = Pose()
        pose.armPlus = 0.5
        pose.headYaw = -0.25
        pose.headPitch = -0.05
        if spec.floats { pose.float = 0.05 }
        rig.apply(pose)
        rig.root.eulerAngles = SCNVector3(0, 0.35, 0)
        scene.rootNode.addChildNode(rig.root)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 26
        cam.camera?.zNear = 0.1
        cam.position = SCNVector3(0, 0.62, 3.1)
        cam.look(at: SCNVector3(0, 0.5, 0))
        scene.rootNode.addChildNode(cam)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1300
        key.position = SCNVector3(-2, 4, 4)
        key.look(at: SCNVector3(0, 0.5, 0))
        scene.rootNode.addChildNode(key)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.intensity = 500
        scene.rootNode.addChildNode(amb)
        scene.lightingEnvironment.contents = Tex.environment(top: UIColor(white: 0.95, alpha: 1), bottom: UIColor(white: 0.45, alpha: 1))
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = scene
        r.pointOfView = cam
        let img = r.snapshot(atTime: 0, with: CGSize(width: 320, height: 320), antialiasingMode: .multisampling4X)
        cache[spec.id] = img
        return img
    }

    static func stage(_ spec: StageSpec) -> UIImage {
        if let c = stageCache[spec.id] { return c }
        let wall = spec.wall()
        let floor = spec.floor()
        let size = CGSize(width: 320, height: 240)
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            wall.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.68))
            // The floor in simple perspective.
            let c = ctx.cgContext
            c.saveGState()
            c.clip(to: CGRect(x: 0, y: size.height * 0.68, width: size.width, height: size.height * 0.32))
            UIColor(patternImage: floor).setFill()
            c.fill(CGRect(x: 0, y: size.height * 0.68, width: size.width, height: size.height * 0.32))
            c.restoreGState()
            UIColor(white: 0, alpha: 0.18).setFill()
            c.fill(CGRect(x: 0, y: size.height * 0.68, width: size.width, height: 2))
            spec.ring.withAlphaComponent(0.9).setStroke()
            c.setLineWidth(3)
            c.strokeEllipse(in: CGRect(x: size.width / 2 - 46, y: size.height * 0.8, width: 92, height: 24))
        }
        stageCache[spec.id] = img
        return img
    }
}
