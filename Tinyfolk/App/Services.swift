import SwiftUI
import StoreKit
import ReplayKit

/// One-time Pro unlock (StoreKit 2): four more friends, three more stages, four more pieces and screen recording.
@MainActor
final class Store: ObservableObject {
    static let productID = "com.heyobi.tinyfolk.pro"

    @Published private(set) var pro = UserDefaults.standard.bool(forKey: "pro")
    @Published private(set) var product: Product?
    @Published var busy = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    init() {
        if ShotsTour.active { pro = true }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish(); await self?.refresh() }
            }
        }
        Task { await load(); await refresh() }
    }

    func load() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { owned = true }
        }
        if ShotsTour.active { owned = true }
        set(owned)
    }

    private func set(_ owned: Bool) {
        pro = owned
        UserDefaults.standard.set(owned, forKey: "pro")
    }

    func buy() async {
        if product == nil { await load() }
        guard let product else { message = String(localized: "The App Store is not reachable right now. Try again later."); return }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let v):
                if case .verified(let t) = v { await t.finish(); set(true) }
            case .pending: message = String(localized: "The purchase is waiting for approval.")
            default: break
            }
        } catch {
            message = String(localized: "The purchase did not go through. Nothing was charged.")
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        message = pro ? String(localized: "Tinyfolk Pro is unlocked.") : String(localized: "No earlier purchase was found for this Apple Account.")
    }

    var priceText: String? { product?.displayPrice }
}

/// Asks for a rating only right after a delight moment (a second person was greeted, or the character landed in
/// the well), after at least three such moments, at most once per version and never more than every four months.
enum ReviewGate {
    static func delight() {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: "delights") + 1, forKey: "delights")
    }

    static func shouldAsk() -> Bool {
        guard !ShotsTour.active else { return false }
        let d = UserDefaults.standard
        guard d.integer(forKey: "delights") >= 3, d.integer(forKey: "launches") >= 2 else { return false }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        if d.string(forKey: "reviewVersion") == version { return false }
        let last = d.double(forKey: "reviewAskedAt")
        if last > 0, Date().timeIntervalSince1970 - last < 120 * 86_400 { return false }
        d.set(version, forKey: "reviewVersion")
        d.set(Date().timeIntervalSince1970, forKey: "reviewAskedAt")
        return true
    }

    static func countLaunch() {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: "launches") + 1, forKey: "launches")
    }
}

/// Screen recording with ReplayKit (Pro). The system shows its own consent prompt; the clip opens in the system
/// preview to trim, save or share. Microphone off: only the app's picture and sound.
@MainActor
final class Recorder: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var startedAt: Date?
    @Published var preview: RPPreviewViewController?
    @Published var error: String?

    var available: Bool { RPScreenRecorder.shared().isAvailable }

    func toggle() { recording ? stop() : start() }

    func start() {
        let r = RPScreenRecorder.shared()
        r.isMicrophoneEnabled = false
        r.startRecording { [weak self] err in
            Task { @MainActor in
                guard let self else { return }
                if let err {
                    self.error = err.localizedDescription
                } else {
                    self.recording = true
                    self.startedAt = Date()
                }
            }
        }
    }

    func stop() {
        guard recording else { return }
        RPScreenRecorder.shared().stopRecording { [weak self] vc, err in
            Task { @MainActor in
                guard let self else { return }
                self.recording = false
                self.startedAt = nil
                if let vc { self.preview = vc } else if let err { self.error = err.localizedDescription }
            }
        }
    }
}
