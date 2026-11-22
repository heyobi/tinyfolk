import SwiftUI
import SceneKit

/// Two scene views over one shared scene: on a half-open iPhone Duo the upper one covers the upper half (the
/// backdrop) and the lower one the lower half (the floor), each with its own off-axis camera. On a flat screen the
/// lower view covers everything. A display link drives the engine and the world once per frame.
final class HoloView: UIView {
    let engine: Engine
    let upperView = SCNView(frame: .zero)
    let lowerView = SCNView(frame: .zero)
    var fold: CGRect? { didSet { if fold != oldValue { setNeedsLayout() } } }
    var onTouch: (() -> Void)?

    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var shownPresentation: Presentation?
    private var shownFold: CGRect?
    private var shownSize: CGSize = .zero

    init(engine: Engine) {
        self.engine = engine
        super.init(frame: .zero)
        backgroundColor = .black
        for v in [upperView, lowerView] {
            v.scene = engine.world.scene
            v.antialiasingMode = .multisampling4X
            v.preferredFramesPerSecond = 60
            v.rendersContinuously = true
            v.isPlaying = true
            v.backgroundColor = .black
            v.isUserInteractionEnabled = false
            v.isJitteringEnabled = false
            addSubview(v)
        }
        upperView.pointOfView = engine.world.camUpper
        lowerView.pointOfView = engine.world.camLower
        upperView.isHidden = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Tinyfolk stage")
        accessibilityHint = String(localized: "Tap the character to make it laugh.")
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = CADisplayLink(target: LinkProxy(self), selector: #selector(LinkProxy.step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var g = engine.geometry
        g.size = bounds.size
        g.fold = fold
        g.insets = window?.safeAreaInsets ?? safeAreaInsets
        g.interface = window?.windowScene?.interfaceOrientation ?? .portrait
        g.isPad = traitCollection.userInterfaceIdiom == .pad
        g.nativeScale = window?.screen.nativeScale ?? UIScreen.main.nativeScale
        if g != engine.geometry { engine.geometry = g }
        arrange(force: true)
    }

    fileprivate func step(_ link: CADisplayLink) {
        let t = link.targetTimestamp
        let dt = lastTime > 0 ? Float(t - lastTime) : 1 / 60
        lastTime = t
        engine.tick(t: t, dt: dt)
        arrange(force: false)
    }

    /// Positions the two scene views for the presentation the world is actually showing.
    private func arrange(force: Bool) {
        let p = engine.world.layout?.presentation ?? .diorama
        guard force || p != shownPresentation || fold != shownFold || bounds.size != shownSize else { return }
        shownPresentation = p
        shownFold = fold
        shownSize = bounds.size
        if p == .stage, let f = fold {
            upperView.isHidden = false
            upperView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: f.minY)
            lowerView.frame = CGRect(x: 0, y: f.maxY, width: bounds.width, height: bounds.height - f.maxY)
        } else {
            upperView.isHidden = true
            lowerView.frame = bounds
        }
        backgroundColor = engine.world.stage.background
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        onTouch?()
        let p = g.location(in: self)
        let target = (!upperView.isHidden && upperView.frame.contains(p)) ? upperView : lowerView
        let local = convert(p, to: target)
        engine.tap(at: local, in: target, viewPoint: p)
    }

    /// Renders the lower (or only) view to an image, for sharing a still.
    func snapshot() -> UIImage { lowerView.snapshot() }
}

@MainActor
private final class LinkProxy: NSObject {
    weak var view: HoloView?
    init(_ v: HoloView) { view = v }
    @objc func step(_ link: CADisplayLink) {
        guard let view else { link.invalidate(); return }
        view.step(link)
    }
}

struct HoloContainer: UIViewRepresentable {
    let engine: Engine
    let fold: CGRect?
    var onTouch: () -> Void = {}

    func makeUIView(context: Context) -> HoloView {
        let v = HoloView(engine: engine)
        v.onTouch = onTouch
        return v
    }

    func updateUIView(_ v: HoloView, context: Context) {
        v.fold = fold
        v.onTouch = onTouch
    }
}
