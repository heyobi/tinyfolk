import AVFoundation
import Vision
import UIKit
import ImageIO

/// Finds up to a few faces in the front camera with Vision, entirely on the device. Frames are analysed and
/// dropped immediately: nothing is stored, recorded or sent anywhere.
///
/// The front camera's mounting differs between devices (the iPhone Duo's inner camera sits under the display), so
/// the image orientation is calibrated automatically: if no upright face is found for a moment, the next of the
/// four mirrored orientations is tried, and the one that finds upright faces is remembered per screen orientation.
final class FaceTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Frame {
        var faces: [FaceBox]
        var camera: CameraModel
        var time: Double
        var diagnostics: String
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "tinyfolk.faces", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private var fov: Float = 70
    private let lock = NSLock()
    private var _interface: UIInterfaceOrientation = .portrait
    private var _contextKey = "phone"

    /// Called on the main queue for every analysed frame.
    var onFrame: ((Frame) -> Void)?
    /// Called on the main queue when the running state changes.
    var onRunning: ((Bool) -> Void)?

    // Calibration (queue only).
    private static let candidates: [CGImagePropertyOrientation] = [.leftMirrored, .rightMirrored, .upMirrored, .downMirrored]
    private var orientation: CGImagePropertyOrientation = .leftMirrored
    private var orientationKey = ""
    private var lastUpright: Double = 0
    private var lastSwitch: Double = 0
    private var locked = false

    static var authorized: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    static var denied: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .video)
        return s == .denied || s == .restricted
    }
    static var available: Bool { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil }

    /// Screen orientation and a key for the display in use (inner/outer/phone), set from the main thread.
    func setContext(interface: UIInterfaceOrientation, key: String) {
        lock.lock()
        _interface = interface
        _contextKey = key
        lock.unlock()
    }

    private func context() -> (UIInterfaceOrientation, String) {
        lock.lock(); defer { lock.unlock() }
        return (_interface, _contextKey)
    }

    func requestAccess(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { done(ok) } }
    }

    func start() {
        guard Self.authorized else { return }
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured { self.configure() }
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            DispatchQueue.main.async { self.onRunning?(running) }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.onRunning?(false) }
        }
    }

    private func configure() {
        session.beginConfiguration()
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        fov = device.activeFormat.videoFieldOfView > 1 ? device.activeFormat.videoFieldOfView : 70
        if (try? device.lockForConfiguration()) != nil {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        }
        configured = true
    }

    /// Standard front-camera orientation for a screen orientation (iPhone mounting).
    static func defaultOrientation(_ io: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch io {
        case .portraitUpsideDown: return .rightMirrored
        case .landscapeLeft: return .upMirrored
        case .landscapeRight: return .downMirrored
        default: return .leftMirrored
        }
    }

    private func refreshOrientationKey(now: Double) {
        let (io, ctx) = context()
        let key = "orient.\(ctx).\(io.rawValue)"
        guard key != orientationKey else { return }
        orientationKey = key
        if let raw = UserDefaults.standard.object(forKey: key) as? UInt32, let o = CGImagePropertyOrientation(rawValue: raw) {
            orientation = o
            locked = true
        } else {
            orientation = Self.defaultOrientation(io)
            locked = false
        }
        lastUpright = now
        lastSwitch = now
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CACurrentMediaTime()
        refreshOrientationKey(now: now)

        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: orientation, options: [:])
        try? handler.perform([request])
        let observations = request.results ?? []

        var w = Float(CVPixelBufferGetWidth(pb)), h = Float(CVPixelBufferGetHeight(pb))
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored: swap(&w, &h)
        default: break
        }

        // Only upright faces count (a sideways face means the orientation is wrong).
        var faces: [FaceBox] = []
        for o in observations.prefix(4) {
            let roll = o.roll?.floatValue ?? 0
            guard abs(roll) < 0.7, o.confidence > 0.5 else { continue }
            let b = o.boundingBox
            faces.append(FaceBox(x: Float(b.origin.x), y: Float(b.origin.y), w: Float(b.width), h: Float(b.height), yaw: o.yaw?.floatValue))
        }

        if !faces.isEmpty {
            lastUpright = now
            if !locked {
                locked = true
                UserDefaults.standard.set(orientation.rawValue, forKey: orientationKey)
            }
        } else {
            // Nobody upright for a while: try the next orientation (slower once one has worked here).
            let wait = locked ? 4.0 : 1.2
            if now - lastUpright > wait && now - lastSwitch > 0.9 {
                let i = Self.candidates.firstIndex(of: orientation) ?? 0
                orientation = Self.candidates[(i + 1) % Self.candidates.count]
                lastSwitch = now
                if locked { locked = false; UserDefaults.standard.removeObject(forKey: orientationKey) }
            }
        }
        let diagnostics = "faces \(faces.count)/\(observations.count) · orientation \(orientation.rawValue)\(locked ? " locked" : "") · fov \(Int(fov))°"
        let frame = Frame(faces: faces, camera: CameraModel(imageSize: SIMD2(w, h), longSideFOV: fov), time: now, diagnostics: diagnostics)
        DispatchQueue.main.async { [weak self] in self?.onFrame?(frame) }
    }
}
