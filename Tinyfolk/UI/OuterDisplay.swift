import SwiftUI

/// iPhone Duo outer display, while the camera runs (the only time iOS lets an app draw there besides the inner
/// display). Standing half open, the outer display faces the people across the table: they get a small marquee
/// with the friend's portrait and the piece that is playing.
struct OuterDisplay: ViewModifier {
    @ObservedObject var engine: Engine

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.sceneAccessory {
                CameraCaptureAccessory(isEnabled: Binding(get: { engine.tracking == .running }, set: { _ in })) {
                    OuterCompanion(engine: engine)
                }
                .onAvailabilityChange { available in engine.outerDisplay = available }
            }
        } else {
            content
        }
    }
}

struct OuterCompanion: View {
    @ObservedObject var engine: Engine

    var body: some View {
        let spec = Cast.spec(engine.characterID)
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: [Color(uiColor: engine.world.stage.background), .black], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 14) {
                    Image(uiImage: Thumbnails.character(spec))
                        .resizable().scaledToFit()
                        .frame(maxWidth: 260)
                        .offset(y: CGFloat(sin(t * 2.4)) * 6)
                        .rotationEffect(.degrees(sin(t * 1.2) * 4))
                    Text(spec.name).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    if engine.musicOn, let piece = Library.piece(engine.songID) {
                        Label(piece.title, systemImage: "music.note")
                            .font(.headline)
                            .foregroundStyle(Color(uiColor: spec.tint))
                            .lineLimit(1)
                    }
                }
                .padding(24)
            }
        }
    }
}
