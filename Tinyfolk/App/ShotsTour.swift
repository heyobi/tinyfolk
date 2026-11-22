import SwiftUI
import simd

/// App Store screenshot tour, only when launched with `-shots` (scripts/sim-shots.sh). Sets each scene up with
/// simulated viewers, writes its name to Documents/shots/ready and waits for the script's answer in
/// Documents/shots/next. A name ending in "@<degrees>" asks the script to set the iPhone Duo simulator's hinge
/// first. For stage shots it also writes <name>.json with the eye and surface sizes, so the composer can draw the
/// half-open phone from exactly the viewer's point of view.
@MainActor
struct ShotsTour {
    nonisolated static var active: Bool { ProcessInfo.processInfo.arguments.contains("-shots") }
    nonisolated static var inner: Bool { ProcessInfo.processInfo.arguments.contains("-shotsInner") }
    nonisolated static var hideControls: Bool { active }

    let engine: Engine

    private var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("shots")
    }

    func run() async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("next"))
        engine.simulate = true
        engine.demoOrbit = false
        engine.musicOn = true
        try? await Task.sleep(for: .seconds(3))

        if Self.inner {
            // On the inner display the tall window (fold across) is "portrait".
            orient(.portrait)
            try? await Task.sleep(for: .seconds(2))
            await stage(name: "1-stage@112", character: "pim", stage: "studio", song: "lantern", hinge: 112,
                        a: SIMD3(-0.02, 0.21, 0.36), b: nil, greet: true)
            await stage(name: "2-two@118", character: "juni", stage: "garden", song: "boats", hinge: 118,
                        a: SIMD3(-0.08, 0.2, 0.37), b: SIMD3(0.2, 0.17, 0.33), greet: false)
            await stage(name: "3-dance@106", character: "odette", stage: "rooftop", song: "bossa", hinge: 106,
                        a: SIMD3(0.06, 0.18, 0.35), b: nil, greet: false)
            await stage(name: "4-tide@120", character: "cosmo", stage: "tide", song: "tide", hinge: 120,
                        a: SIMD3(0.0, 0.22, 0.34), b: nil, greet: false)
            // Fully open: the floor gives way and the friend lands in the lantern well.
            orient(.landscape)
            engine.hingeOverride = 180
            engine.presentationOverride = .well
            engine.simA = SIMD3(0, -0.1, 0.3)
            try? await Task.sleep(for: .seconds(9))
            await step("5-well@180")
            engine.presentationOverride = nil
        } else {
            await window(name: "1-box", presentation: .diorama, character: "pim", stage: "studio", song: "lantern",
                         a: SIMD3(-0.03, -0.02, 0.32), b: nil, greet: true)
            await window(name: "2-two", presentation: .diorama, character: "juni", stage: "garden", song: "boats",
                         a: SIMD3(-0.05, -0.03, 0.33), b: SIMD3(0.13, 0.0, 0.3), greet: false)
            await window(name: "3-well", presentation: .well, character: "lumen", stage: "rooftop", song: "tide",
                         a: SIMD3(0.0, -0.1, 0.3), b: nil, greet: false, wait: 10)
            await window(name: "4-snow", presentation: .diorama, character: "kumo", stage: "winter", song: "wiegenlied",
                         a: SIMD3(0.04, 0.0, 0.32), b: nil, greet: false)
        }

        // Picker and paywall.
        engine.presentationOverride = nil
        engine.characterID = "mossy"
        engine.stageID = "garden"
        engine.shotSheet = .picker(.cast)
        await step("6-friends")
        engine.shotSheet = nil
        try? await Task.sleep(for: .seconds(1))
        engine.shotSheet = .paywall
        await step("7-paywall")
        engine.shotSheet = nil
        write("ready", "done")
    }

    private func configure(character: String, stage: String, song: String, a: SIMD3<Float>, b: SIMD3<Float>?) async {
        engine.characterID = character
        engine.stageID = stage
        engine.songID = song
        engine.simBOn = false
        try? await Task.sleep(for: .seconds(0.5))
        engine.simA = a
        if let b { engine.simB = b }
    }

    private func stage(name: String, character: String, stage: String, song: String, hinge: Double,
                       a: SIMD3<Float>, b: SIMD3<Float>?, greet: Bool) async {
        engine.hingeOverride = hinge
        engine.presentationOverride = .stage
        await configure(character: character, stage: stage, song: song, a: a, b: b)
        try? await Task.sleep(for: .seconds(3))
        engine.simA = a
        if b != nil {
            engine.simBOn = true
            try? await Task.sleep(for: .seconds(1.2))
        } else if greet {
            engine.world.greetNewcomer()
            try? await Task.sleep(for: .seconds(0.5))
        } else {
            try? await Task.sleep(for: .seconds(2))
        }
        writeGeometry(name: String(name.split(separator: "@")[0]), eye: a, hinge: hinge)
        await step(name, settle: false)
    }

    private func window(name: String, presentation: Presentation, character: String, stage: String, song: String,
                        a: SIMD3<Float>, b: SIMD3<Float>?, greet: Bool, wait: Double = 3) async {
        engine.presentationOverride = presentation
        await configure(character: character, stage: stage, song: song, a: a, b: b)
        try? await Task.sleep(for: .seconds(wait))
        engine.simA = a
        if b != nil {
            engine.simBOn = true
            try? await Task.sleep(for: .seconds(1.2))
        } else if greet {
            engine.world.greetNewcomer()
            try? await Task.sleep(for: .seconds(0.5))
        }
        await step(name, settle: false)
    }

    private func writeGeometry(name: String, eye: SIMD3<Float>, hinge: Double) {
        let g = engine.geometry
        let fold = g.fold ?? .zero
        var json = String(format: "{\"hinge\":%.2f,\"eye\":[%.4f,%.4f,%.4f],\"size\":[%.1f,%.1f],\"fold\":[%.1f,%.1f,%.1f,%.1f],\"interface\":%ld,\"scale\":%.2f",
                          hinge, eye.x, eye.y, eye.z, g.size.width, g.size.height, fold.minX, fold.minY, fold.width, fold.height,
                          g.interface.rawValue, g.nativeScale)
        if let l = engine.world.layout, let up = l.upper {
            json += String(format: ",\"presentation\":\"stage\",\"upper\":[%.4f,%.4f],\"lower\":[%.4f,%.4f]", up.width, up.height, l.lower.width, l.lower.height)
        } else {
            json += ",\"presentation\":\"\(engine.world.layout.map { "\($0.presentation)" } ?? "none")\""
        }
        json += "}"
        write("\(name).json", json)
    }

    private func step(_ name: String, settle: Bool = true) async {
        if settle { try? await Task.sleep(for: .seconds(2.5)) }
        write("ready", name)
        for _ in 0..<1200 {
            if let s = try? String(contentsOf: dir.appendingPathComponent("next"), encoding: .utf8), s == name { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Asks the scene for an interface orientation (the half-open stage needs the fold running across the window).
    private func orient(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func write(_ file: String, _ text: String) {
        try? text.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }
}
