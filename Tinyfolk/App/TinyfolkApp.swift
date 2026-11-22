import SwiftUI

@main
struct TinyfolkApp: App {
    @StateObject private var engine = Engine()
    @StateObject private var store = Store()
    @StateObject private var recorder = Recorder()
    @Environment(\.scenePhase) private var phase

    init() {
        ReviewGate.countLaunch()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(store)
                .environmentObject(recorder)
                .preferredColorScheme(.dark)
                .task {
                    if ShotsTour.active { await ShotsTour(engine: engine).run() }
                }
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active: engine.activate()
            case .background:
                if recorder.recording { recorder.stop() }
                engine.deactivate()
            default: break
            }
        }
    }
}
