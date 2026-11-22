import SwiftUI
import StoreKit
import ReplayKit

enum Sheet: Identifiable, Equatable {
    case picker(PickerTab), settings, paywall
    var id: String {
        switch self {
        case .picker(let t): return "picker-\(t)"
        case .settings: return "settings"
        case .paywall: return "paywall"
        }
    }
}

enum PickerTab: String, CaseIterable { case cast, stages, music }

extension View {
    /// Liquid Glass on iOS 26 and later, a thin material before.
    @ViewBuilder func glass<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }
}

struct RootView: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var store: Store
    @EnvironmentObject var recorder: Recorder
    @Environment(\.requestReview) private var requestReview
    @State private var sheet: Sheet?
    @State private var lastTouch = Date()
    @State private var controlsVisible = true
    @State private var cameraCard = false
    @State private var cameraCardDismissed = false
    @State private var hintText: String?
    @AppStorage("debugUnlocked") private var debugUnlocked = false
    @State private var showDebug = false

    private var stage: some View {
        GeometryReader { proxy in
            let fold = foldFrame(proxy)
            ZStack {
                HoloContainer(engine: engine, fold: fold, onTouch: touched)
                    .ignoresSafeArea()
                overlay(fold: fold, size: proxy.size)
            }
        }
        .ignoresSafeArea()
        .modifier(HingeReader(engine: engine))
        .modifier(OuterDisplay(engine: engine))
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private var withSheets: some View {
        stage
        .sheet(item: $sheet) { s in sheetView(s) }
        .sheet(isPresented: Binding(get: { recorder.preview != nil }, set: { if !$0 { recorder.preview = nil } })) {
            if let p = recorder.preview { PreviewController(controller: p) { recorder.preview = nil }.ignoresSafeArea() }
        }
    }

    @ViewBuilder
    private func sheetContent(_ s: Sheet) -> some View {
        switch s {
        case .picker(let tab): PickerSheet(tab: tab, sheet: $sheet)
        case .settings: SettingsSheet(sheet: $sheet, showDebug: $showDebug)
        case .paywall: PaywallSheet(sheet: $sheet)
        }
    }

    private func sheetView(_ s: Sheet) -> some View {
        let large: Set<PresentationDetent> = [.large]
        let both: Set<PresentationDetent> = [.medium, .large]
        let full = s == .paywall || s == .settings
        return sheetContent(s)
            .environmentObject(engine)
            .environmentObject(store)
            .presentationDetents(full ? large : both)
            .presentationBackground(.regularMaterial)
    }

    var body: some View {
        withSheets
        .onChange(of: engine.askReview) { _, ask in
            if ask { requestReview(); engine.askReview = false }
        }
        .onChange(of: engine.posture) { _, p in showHint(for: p) }
        .onChange(of: engine.shotSheet) { _, s in sheet = s }
        .task {
            if ShotsTour.active { return }
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if engine.tracking == .needsPermission && !cameraCardDismissed { withAnimation(.spring(duration: 0.5)) { cameraCard = true } }
        }
        .task {
            // Controls fade away when nobody touches the screen.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let idle = Date().timeIntervalSince(lastTouch) > 6
                if idle == controlsVisible && sheet == nil && !cameraCard && !showDebug && !ShotsTour.active {
                    withAnimation(.easeInOut(duration: 0.6)) { controlsVisible = !idle }
                }
            }
        }
    }

    private func touched() {
        lastTouch = Date()
        if !controlsVisible { withAnimation(.easeOut(duration: 0.25)) { controlsVisible = true } }
    }

    private func showHint(for p: Posture) {
        guard !ShotsTour.active else { return }
        switch p {
        case .book: hintText = String(localized: "Turn iPhone Duo on its side and stand it half open, like a tiny laptop.")
        default: hintText = nil
        }
    }

    // MARK: Overlay

    @ViewBuilder
    private func overlay(fold: CGRect?, size: CGSize) -> some View {
        VStack(spacing: 10) {
            HStack {
                if recorder.recording { RecordingBadge(started: recorder.startedAt) }
                Spacer()
            }
            .padding(.top, 54)
            .padding(.horizontal, 20)
            if let hintText {
                Text(hintText)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glass(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 30)
                    .transition(.opacity)
            }
            Spacer()
            if cameraCard {
                CameraCard(allow: {
                    withAnimation { cameraCard = false }
                    cameraCardDismissed = true
                    engine.enableTracking()
                }, later: {
                    withAnimation { cameraCard = false }
                    cameraCardDismissed = true
                })
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if showDebug {
                DebugPanel(close: { showDebug = false })
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom))
            } else if !ShotsTour.hideControls {
                controls
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
            }
        }
        .padding(.bottom, 26)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            RoundButton(symbol: "face.smiling", label: "Friends") { touched(); sheet = .picker(.cast) }
            RoundButton(symbol: "sparkles", label: "Stages") { touched(); sheet = .picker(.stages) }
            RoundButton(symbol: engine.musicOn ? "music.note" : "speaker.slash", label: "Music") { touched(); sheet = .picker(.music) }
            RoundButton(symbol: recorder.recording ? "stop.circle.fill" : "record.circle", label: recorder.recording ? "Stop recording" : "Record",
                        tint: recorder.recording ? .red : nil) {
                touched()
                if !store.pro { sheet = .paywall } else { recorder.toggle() }
            }
            RoundButton(symbol: "ellipsis", label: "Settings") { touched(); sheet = .settings }
        }
        .padding(6)
        .glass(Capsule())
    }
}

struct RoundButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint ?? .primary)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

struct RecordingBadge: View {
    let started: Date?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = Int(ctx.date.timeIntervalSince(started ?? ctx.date))
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(String(format: "%d:%02d", s / 60, s % 60)).font(.caption.monospacedDigit().weight(.semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glass(Capsule())
        }
    }
}

struct CameraCard: View {
    let allow: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "eye").font(.title3.weight(.semibold))
                Text("See them in true 3D").font(.headline)
            }
            Text("Tinyfolk can follow where your eyes are with the front camera, so the little world shifts like real depth as you move. Video is analysed on this device and never stored or sent.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Not now", action: later).buttonStyle(.bordered)
                Spacer()
                Button(action: allow) { Text("Follow my eyes").bold() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: 460)
    }
}

/// Presents ReplayKit's preview (trim, save, share).
struct PreviewController: UIViewControllerRepresentable {
    let controller: RPPreviewViewController
    let done: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> RPPreviewViewController {
        controller.previewControllerDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ vc: RPPreviewViewController, context: Context) {}

    final class Coordinator: NSObject, RPPreviewViewControllerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func previewControllerDidFinish(_ previewController: RPPreviewViewController) { done() }
    }
}

/// Feeds the iPhone Duo hinge (iOS 27.1) into the engine. Elsewhere it does nothing.
struct HingeReader: ViewModifier {
    let engine: Engine

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, ctx in
                let h: DeviceHinge? = ctx.hinge
                guard let h else { return }
                engine.hingeChanged(angle: h.angle.degrees, closed: h.status == .closed)
            }
        } else {
            content
        }
    }
}

/// The division (fold) reserved region of an iPhone Duo in this geometry's coordinates, if any.
func foldFrame(_ proxy: GeometryProxy) -> CGRect? {
    if #available(iOS 27.1, *) {
        if let d = proxy.reservedRegions(kind: .division, options: [.includeInactive]).first {
            return d.frame
        }
    }
    return nil
}
