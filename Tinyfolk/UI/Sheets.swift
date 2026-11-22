import SwiftUI
import AVFoundation

struct PickerSheet: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var store: Store
    @State var tab: PickerTab
    @Binding var sheet: Sheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Section", selection: $tab) {
                        Text("Friends").tag(PickerTab.cast)
                        Text("Stages").tag(PickerTab.stages)
                        Text("Music").tag(PickerTab.music)
                    }
                    .pickerStyle(.segmented)
                    switch tab {
                    case .cast: castGrid
                    case .stages: stageGrid
                    case .music: musicList
                    }
                    if !store.pro {
                        Button { sheet = .paywall } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("More friends, stages and music with Tinyfolk Pro")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Tinyfolk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 14)]

    private var castGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Cast.all) { c in
                let locked = !c.free && !store.pro
                Button {
                    if locked { sheet = .paywall; return }
                    engine.characterID = c.id
                } label: {
                    VStack(spacing: 6) {
                        Image(uiImage: Thumbnails.character(c))
                            .resizable().scaledToFit()
                            .frame(height: 120)
                            .opacity(locked ? 0.55 : 1)
                        HStack(spacing: 4) {
                            Text(c.name).font(.headline)
                            if locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(card(selected: engine.characterID == c.id, tint: Color(uiColor: c.tint)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(locked ? "\(c.name), Pro" : c.name))
                .accessibilityAddTraits(engine.characterID == c.id ? .isSelected : [])
            }
        }
    }

    private var stageGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Stages.all) { s in
                let locked = !s.free && !store.pro
                Button {
                    if locked { sheet = .paywall; return }
                    engine.stageID = s.id
                } label: {
                    VStack(spacing: 8) {
                        Image(uiImage: Thumbnails.stage(s))
                            .resizable().scaledToFill()
                            .frame(height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .opacity(locked ? 0.55 : 1)
                        HStack(spacing: 4) {
                            Text(s.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            if locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .padding(10)
                    .background(card(selected: engine.stageID == s.id, tint: Color(uiColor: s.ring)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(engine.stageID == s.id ? .isSelected : [])
            }
        }
    }

    private var musicList: some View {
        VStack(spacing: 10) {
            Toggle(isOn: $engine.musicOn) {
                Label("Music", systemImage: "music.note")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06)))
            ForEach(Library.all) { p in
                let locked = !p.free && !store.pro
                let current = engine.songID == p.id && engine.musicOn
                Button {
                    if locked { sheet = .paywall; return }
                    engine.songID = p.id
                    if !engine.musicOn { engine.musicOn = true }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: current ? "speaker.wave.2.fill" : "music.note")
                            .frame(width: 26)
                            .foregroundStyle(current ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Text(p.origin).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if locked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    }
                    .padding(14)
                    .background(card(selected: current, tint: .accentColor))
                }
                .buttonStyle(.plain)
            }
            Text("Every piece is played live on your device by a small synthesizer. The cast dances to the beat.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func card(selected: Bool, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(selected ? tint.opacity(0.22) : Color.primary.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? tint : .clear, lineWidth: 2))
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var store: Store
    @Binding var sheet: Sheet?
    @Binding var showDebug: Bool
    @AppStorage("haptics") private var haptics = true
    @AppStorage("debugUnlocked") private var debugUnlocked = false
    @State private var versionTaps = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch engine.tracking {
                    case .running:
                        Toggle("Follow my eyes", isOn: Binding(get: { true }, set: { if !$0 { engine.disableTracking() } }))
                    case .off, .needsPermission:
                        Toggle("Follow my eyes", isOn: Binding(get: { false }, set: { if $0 { engine.enableTracking() } }))
                    case .denied:
                        Button("Allow the camera in Settings") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }
                    case .unavailable:
                        Text("This device has no front camera.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("3D view")
                } footer: {
                    Text("The front camera finds where your eyes are, up to two people, so the scene is drawn from your point of view. Frames are analysed on this device and dropped at once: nothing is recorded, stored or sent. Without the camera, tilting the phone gives a gentler depth.")
                }
                Section("Feel") {
                    Toggle("Haptics", isOn: $haptics)
                    Toggle("Music", isOn: $engine.musicOn)
                }
                Section {
                    if store.pro {
                        Label("Tinyfolk Pro is unlocked. Thank you!", systemImage: "checkmark.seal.fill")
                    } else {
                        Button { sheet = .paywall } label: { Label("Tinyfolk Pro", systemImage: "sparkles") }
                    }
                    Button("Restore purchase") { Task { await store.restore() } }
                } footer: {
                    if let m = store.message { Text(m) }
                }
                Section("How to use") {
                    Label("On iPhone Duo, stand it half open like a tiny laptop: the friend stands on the fold, in front of you.", systemImage: "laptopcomputer")
                    Label("Open iPhone Duo all the way flat for a surprise.", systemImage: "gift")
                    Label("On other iPhones and iPad, the screen becomes a window into a little box. Lay it flat to look down into a well.", systemImage: "square.3.layers.3d")
                    Label("A second person walking up gets a wave.", systemImage: "hand.wave")
                }
                .font(.subheadline)
                Section("About") {
                    Link(destination: URL(string: "https://heyobi.github.io/tinyfolk/")!) { Label("Website", systemImage: "safari") }
                    Link(destination: URL(string: "https://github.com/heyobi/tinyfolk/blob/main/PRIVACY.md")!) { Label("Privacy", systemImage: "hand.raised") }
                    Button {
                        versionTaps += 1
                        if versionTaps >= 5 { debugUnlocked = true }
                    } label: {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                if debugUnlocked || isSimulator {
                    Section {
                        Button("Simulate viewers and hinge") { showDebug = true; sheet = nil }
                        Text(engine.diagnostics.isEmpty ? String(localized: "Camera not running") : engine.diagnostics)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        if let e = Synth.shared.lastError { Text("Audio: \(e)").font(.caption.monospaced()).foregroundStyle(.orange) }
                    } header: {
                        Text("Developer")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
        }
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

struct PaywallSheet: View {
    @EnvironmentObject var store: Store
    @Binding var sheet: Sheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HStack(spacing: -18) {
                        ForEach(Cast.all.filter { !$0.free }) { c in
                            Image(uiImage: Thumbnails.character(c)).resizable().scaledToFit().frame(width: 92, height: 92)
                        }
                    }
                    .padding(.top, 8)
                    VStack(spacing: 8) {
                        Text("Tinyfolk Pro").font(.largeTitle.bold())
                        Text("One payment, yours for good. Shared with your family. No subscription, no ads.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        feature("face.smiling", "Four more friends", "Cosmo, Tuck, Kumo and Lumen, each with their own dance.")
                        feature("sparkles", "Three more stages", "Tide Pool, First Snow and Lamp Library.")
                        feature("music.note", "Four more pieces", "Bossa Lumen, Greensleeves, The Entertainer and Wiegenlied.")
                        feature("record.circle", "Screen recording", "Capture your tiny friend and share the clip.")
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.06)))
                    Text("Everything you have now stays free forever.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        Task {
                            await store.buy()
                            if store.pro { sheet = nil }
                        }
                    } label: {
                        Group {
                            if store.busy { ProgressView() } else {
                                Text(store.priceText.map { String(localized: "Unlock for \($0)") } ?? String(localized: "Unlock Tinyfolk Pro"))
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.busy)
                    Button("Restore purchase") { Task { await store.restore() } }
                        .font(.subheadline)
                    if let m = store.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { sheet = nil } } }
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 30).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Drives the scene without a camera or hinge: viewer positions, a second viewer, the hinge angle and the
/// presentation. On by default in the simulator; on a device it opens from Settings (tap Version five times).
struct DebugPanel: View {
    @EnvironmentObject var engine: Engine
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Simulator controls").font(.headline)
                Spacer()
                Button("Close", action: close).font(.subheadline.weight(.semibold))
            }
            Toggle("Simulated viewers", isOn: $engine.simulate)
            HStack {
                Toggle("Orbit", isOn: $engine.demoOrbit)
                Toggle("A looks", isOn: $engine.simALooking)
            }
            axis("A x", $engine.simA.x, -0.3...0.3)
            axis("A y", $engine.simA.y, -0.3...0.4)
            axis("A z", $engine.simA.z, 0.15...0.7)
            Toggle("Second viewer B", isOn: $engine.simBOn)
            if engine.simBOn {
                Toggle("B looks", isOn: $engine.simBLooking)
                axis("B x", $engine.simB.x, -0.3...0.3)
                axis("B z", $engine.simB.z, 0.15...0.7)
            }
            HStack {
                Toggle("Hinge", isOn: Binding(get: { engine.hingeOverride != nil }, set: { engine.hingeOverride = $0 ? 110 : nil }))
                if let h = engine.hingeOverride {
                    Slider(value: Binding(get: { h }, set: { engine.hingeOverride = $0 }), in: 0...180)
                    Text("\(Int(h))°").font(.caption.monospacedDigit()).frame(width: 36)
                }
            }
            Picker("View", selection: Binding(get: { engine.presentationOverride.map { "\($0)" } ?? "auto" },
                                               set: { v in
                let map: [String: Presentation] = ["stage": .stage, "well": .well, "diorama": .diorama]
                engine.presentationOverride = map[v]
            })) {
                Text("Auto").tag("auto")
                Text("Stage").tag("stage")
                Text("Well").tag("well")
                Text("Box").tag("diorama")
            }
            .pickerStyle(.segmented)
            Text(engine.diagnostics).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
        }
        .font(.caption)
        .padding(14)
        .glass(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: 520)
    }

    private func axis(_ name: String, _ value: Binding<Float>, _ range: ClosedRange<Float>) -> some View {
        HStack {
            Text(name).font(.caption.monospaced()).frame(width: 34, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue)).font(.caption.monospacedDigit()).frame(width: 40)
        }
    }
}
