import XCTest
import simd
@testable import Tinyfolk

final class ProjectionTests: XCTestCase {
    private func assertClose(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ tol: Float = 1e-3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }

    private func xy(_ v: SIMD3<Float>) -> SIMD2<Float> { SIMD2(v.x, v.y) }

    /// The surface's corners land exactly on the corners of the image, wherever the eye is.
    func testCornersMapToImageCorners() {
        let s = DisplayLayout.window(size: SIMD2(0.07, 0.15))
        for eye in [SIMD3<Float>(0, 0, 0.3), SIMD3(0.12, -0.2, 0.25), SIMD3(-0.3, 0.1, 0.5)] {
            let o = OffAxis(eye: eye, surface: s)
            assertClose(xy(o.ndc(s.point(0, 0))), SIMD2(-1, -1))
            assertClose(xy(o.ndc(s.point(1, 0))), SIMD2(1, -1))
            assertClose(xy(o.ndc(s.point(0, 1))), SIMD2(-1, 1))
            assertClose(xy(o.ndc(s.point(1, 1))), SIMD2(1, 1))
            assertClose(xy(o.ndc(s.point(0.25, 0.7))), SIMD2(-0.5, 0.4))
        }
    }

    /// A point behind the glass appears where the line from the eye through it crosses the glass.
    func testPointsProjectAlongSightLines() {
        let s = DisplayLayout.window(size: SIMD2(0.07, 0.15))
        let eye = SIMD3<Float>(0.05, -0.08, 0.31)
        let o = OffAxis(eye: eye, surface: s)
        let p = SIMD3<Float>(-0.01, 0.02, -0.06)
        let hit = s.hit(from: eye, through: p)!
        assertClose(xy(o.ndc(p)), hit * 2 - SIMD2(1, 1))
    }

    /// Depth stays in the clip range for points inside the scene.
    func testDepthInRange() {
        let s = DisplayLayout.window(size: SIMD2(0.07, 0.15))
        let o = OffAxis(eye: SIMD3(0, 0, 0.3), surface: s, near: 0.01, far: 4)
        let z = o.ndc(SIMD3(0, 0, -0.1)).z
        XCTAssert(z > -1 && z < 1)
        // Nearer points have smaller depth.
        XCTAssertLessThan(o.ndc(SIMD3(0, 0, 0.1)).z, z)
    }

    /// The camera looks into the glass and its axes follow the surface.
    func testCameraOrientation() {
        let (upper, _) = DisplayLayout.stage(hingeDegrees: 100, upper: SIMD2(0.11, 0.079), lower: SIMD2(0.11, 0.079))
        let o = OffAxis(eye: SIMD3(0, 0.2, 0.35), surface: upper)
        let forward = -SIMD3(o.cameraTransform.columns.2.x, o.cameraTransform.columns.2.y, o.cameraTransform.columns.2.z)
        XCTAssertLessThan(simd_dot(forward, upper.normal), -0.99)
        XCTAssertEqual(o.cameraTransform.columns.3.y, 0.2, accuracy: 1e-5)
    }

    /// An eye behind the glass is pushed in front so the frustum stays valid.
    func testEyeBehindGlassIsClamped() {
        let s = DisplayLayout.window(size: SIMD2(0.07, 0.15))
        let o = OffAxis(eye: SIMD3(0, 0, -0.2), surface: s)
        XCTAssertGreaterThanOrEqual(s.distance(o.eye), OffAxis.minDistance - 1e-5)
        XCTAssertFalse(o.projection.columns.0.x.isNaN)
    }

    // MARK: Stage (two halves)

    func testStageGeometry() {
        let (upper, lower) = DisplayLayout.stage(hingeDegrees: 90, upper: SIMD2(0.11, 0.08), lower: SIMD2(0.11, 0.07))
        XCTAssertEqual(lower.normal.y, 1, accuracy: 1e-5)                // floor faces up
        XCTAssertEqual(upper.normal.z, 1, accuracy: 1e-5)                // wall faces the viewer
        XCTAssertEqual(upper.point(0.5, 1).y, 0.08, accuracy: 1e-5)      // top of the upright half
        XCTAssertEqual(lower.point(0.5, 0).z, 0.07, accuracy: 1e-5)      // near edge of the floor half
        XCTAssertEqual(lower.point(0.5, 1).z, 0, accuracy: 1e-5)         // floor's top edge is the fold
        // Leaning back past 90°: the upper half tilts away from the viewer.
        let (lean, _) = DisplayLayout.stage(hingeDegrees: 120, upper: SIMD2(0.11, 0.08), lower: SIMD2(0.11, 0.07))
        XCTAssertLessThan(lean.point(0.5, 1).z, 0)
        // Flat: both halves in one plane.
        let (flatUp, flatLow) = DisplayLayout.stage(hingeDegrees: 180, upper: SIMD2(0.11, 0.08), lower: SIMD2(0.11, 0.07))
        XCTAssertEqual(flatUp.normal.y, 1, accuracy: 1e-5)
        XCTAssertEqual(flatLow.normal.y, 1, accuracy: 1e-5)
    }

    /// The heart of the app: a virtual point is drawn on whichever half the sight line crosses, at exactly that
    /// spot, for every hinge angle — so the floor and backdrop look continuous across the fold.
    func testSeamlessAcrossTheFold() {
        let sizeU = SIMD2<Float>(0.111, 0.079), sizeL = SIMD2<Float>(0.111, 0.079)
        let eye = SIMD3<Float>(0.03, 0.22, 0.36)
        for angle: Float in [80, 95, 110, 125, 140] {
            let (upper, lower) = DisplayLayout.stage(hingeDegrees: angle, upper: sizeU, lower: sizeL)
            let ou = OffAxis(eye: eye, surface: upper), ol = OffAxis(eye: eye, surface: lower)
            // A point on the virtual floor just behind the fold, and one on the fold line itself.
            for p in [SIMD3<Float>(0.01, 0, -0.01), SIMD3<Float>(-0.02, 0, 0)] {
                if let hu = upper.hit(from: eye, through: p), (0...1).contains(hu.x), (0...1).contains(hu.y) {
                    assertClose(xy(ou.ndc(p)), hu * 2 - SIMD2(1, 1))
                }
                if let hl = lower.hit(from: eye, through: p), (0...1).contains(hl.x), (0...1).contains(hl.y) {
                    assertClose(xy(ol.ndc(p)), hl * 2 - SIMD2(1, 1))
                }
            }
            // The fold line itself is the shared edge: bottom of the upper image, top of the lower image.
            let f = SIMD3<Float>(0.0, 0, 0)
            XCTAssertEqual(ou.ndc(f).y, -1, accuracy: 1e-3)
            XCTAssertEqual(ol.ndc(f).y, 1, accuracy: 1e-3)
            XCTAssertEqual(ou.ndc(f).x, ol.ndc(f).x, accuracy: 1e-3)
        }
    }

    /// A character standing at the fold is seen through the screens behind it.
    func testCharacterAtFoldIsVisible() {
        let (upper, lower) = DisplayLayout.stage(hingeDegrees: 105, upper: SIMD2(0.111, 0.079), lower: SIMD2(0.111, 0.079))
        let eye = SIMD3<Float>(0, 0.2, 0.35)
        for p in [SIMD3<Float>(0, 0.06, 0.013), SIMD3<Float>(0, 0.002, 0.02)] {
            let onUpper = upper.hit(from: eye, through: p).map { (0...1).contains($0.x) && (0...1).contains($0.y) } ?? false
            let onLower = lower.hit(from: eye, through: p).map { (0...1).contains($0.x) && (0...1).contains($0.y) } ?? false
            XCTAssert(onUpper || onLower, "point \(p) not visible")
        }
    }

    // MARK: Camera → eye

    func testFaceDepthFromBoxSize() {
        let cam = CameraModel(imageSize: SIMD2(480, 640), longSideFOV: 70)
        let near = cam.position(of: FaceBox(x: 0.3, y: 0.3, w: 0.4, h: 0.4, yaw: 0))
        let far = cam.position(of: FaceBox(x: 0.4, y: 0.4, w: 0.2, h: 0.2, yaw: 0))
        XCTAssertEqual(far.z / near.z, 2, accuracy: 0.01)
        XCTAssert(near.z > 0.1 && near.z < 0.6)
        // Centered face → on the axis horizontally.
        XCTAssertEqual(near.x, 0, accuracy: 1e-4)
        // A face to the right of the image is to the right of the camera.
        let right = cam.position(of: FaceBox(x: 0.6, y: 0.3, w: 0.3, h: 0.3, yaw: 0))
        XCTAssertGreaterThan(right.x, 0)
    }

    func testEyeFromUpperHalfCamera() {
        let (upper, _) = DisplayLayout.stage(hingeDegrees: 90, upper: SIMD2(0.11, 0.08), lower: SIMD2(0.11, 0.07))
        // Camera at the top middle of the upright half; face 0.3 m straight out.
        let e = CameraMount.eye(SIMD3(0, 0, 0.3), on: upper, u: 0.5, v: 1)
        XCTAssertEqual(e.x, 0, accuracy: 1e-5)
        XCTAssertEqual(e.y, 0.08, accuracy: 1e-5)
        XCTAssertEqual(e.z, 0.3, accuracy: 1e-5)
    }
}
