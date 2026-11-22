import Foundation

/// Synthesizer voices. Raw values index the render code's instrument switch.
enum Instrument: Int32, CaseIterable {
    case musicBox = 0, ePiano, pluck, pad, bass, kick, brush, flute, celesta, chirp, knock, kanun
}

enum Style { case waltz, folk, ballad, march, bossa, rag }

/// One note for the synthesizer, positioned in beats from the start of the loop.
struct NoteEvent: Equatable {
    var beat: Double
    var dur: Double
    var midi: Int
    var vel: Float
    var inst: Instrument
    var pan: Float
}

/// An instrumental piece: a melody with chord hints, arranged at load time for the chosen style. Titles stay in
/// their original form in every language.
struct Piece: Identifiable {
    let id: String
    let title: String
    let origin: String
    let tempo: Double
    let meter: Int
    let style: Style
    let lead: Instrument
    let lead2: Instrument
    let free: Bool
    /// Beats of pickup before the first full bar.
    var pickup: Double = 0
    /// Octaves to shift the melody (music box and celesta like it high).
    var octave: Int = 0
    let melody: String
}

enum Pitch {
    private static let names: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

    /// "C4" → 60, "F#3" → 54, "Bb5" → 82.
    static func midi(_ s: String) -> Int? {
        var chars = Array(s)
        guard let first = chars.first, let base = names[String(first).uppercased()] else { return nil }
        chars.removeFirst()
        var acc = 0
        while let c = chars.first, c == "#" || c == "b" {
            acc += c == "#" ? 1 : -1
            chars.removeFirst()
        }
        guard let octave = Int(String(chars)) else { return nil }
        return 12 * (octave + 1) + base + acc
    }

    static func frequency(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }
}

/// A chord symbol: root pitch class and intervals above it.
struct Chord: Equatable {
    var root: Int
    var intervals: [Int]

    static func parse(_ s: String) -> Chord? {
        var chars = Array(s)
        guard let first = chars.first else { return nil }
        let table: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard var root = table[first] else { return nil }
        chars.removeFirst()
        if let c = chars.first, c == "#" || c == "b" {
            root += c == "#" ? 1 : -1
            chars.removeFirst()
        }
        let q = String(chars)
        let iv: [Int]
        switch q {
        case "", "maj": iv = [0, 4, 7]
        case "m": iv = [0, 3, 7]
        case "7": iv = [0, 4, 7, 10]
        case "maj7": iv = [0, 4, 7, 11]
        case "m7": iv = [0, 3, 7, 10]
        case "maj9": iv = [0, 4, 11, 14]
        case "m9": iv = [0, 3, 10, 14]
        case "9": iv = [0, 4, 10, 14]
        case "6": iv = [0, 4, 7, 9]
        case "m6": iv = [0, 3, 7, 9]
        case "sus4": iv = [0, 5, 7]
        case "sus2": iv = [0, 2, 7]
        case "dim": iv = [0, 3, 6]
        case "13": iv = [0, 4, 10, 21]
        default: return nil
        }
        return Chord(root: (root + 12) % 12, intervals: iv)
    }

    /// Bass note in the second octave (E2…D#3).
    var bass: Int { 40 + (root + 8) % 12 }
    var fifth: Int { bass + (intervals.contains(6) ? 6 : 7) - (bass + 7 > 50 ? 12 : 0) }

    /// Close voicing around the middle of the keyboard (F3…E4 for the root).
    var voicing: [Int] {
        let base = 53 + (root + 7) % 12
        return intervals.prefix(4).map { base + $0 }
    }
}

struct MelodyNote: Equatable {
    var beat: Double
    var dur: Double
    var midi: Int?
}

enum Score {
    /// Parses `C4:1 F#4:.5 R:1 [Am] |` text into notes and chord changes (beat positions from 0).
    static func parse(_ text: String) -> (notes: [MelodyNote], chords: [(beat: Double, chord: Chord)], length: Double) {
        var notes: [MelodyNote] = []
        var chords: [(beat: Double, chord: Chord)] = []
        var beat = 0.0
        for raw in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let tok = String(raw)
            if tok == "|" { continue }
            if tok.hasPrefix("[") && tok.hasSuffix("]") {
                if let c = Chord.parse(String(tok.dropFirst().dropLast())) { chords.append((beat, c)) }
                continue
            }
            let parts = tok.split(separator: ":", maxSplits: 1).map(String.init)
            let dur = parts.count > 1 ? (Double(parts[1]) ?? 1) : 1
            let pitch = parts[0].uppercased() == "R" ? nil : Pitch.midi(parts[0])
            notes.append(MelodyNote(beat: beat, dur: dur, midi: pitch))
            beat += dur
        }
        return (notes, chords, beat)
    }

    /// The chord sounding at a beat (the last change at or before it, else the first chord).
    static func chord(at beat: Double, in chords: [(beat: Double, chord: Chord)]) -> Chord? {
        var current = chords.first?.chord
        for c in chords where c.beat <= beat + 1e-6 { current = c.chord }
        return current
    }

    /// Full arrangement: the melody twice (second time with another lead and a soft octave double), over an
    /// accompaniment in the piece's style. Returns the events and the loop length in beats.
    static func arrange(_ p: Piece) -> (events: [NoteEvent], loop: Double) {
        let parsed = parse(p.melody)
        let m = Double(p.meter)
        let lead = (m - p.pickup.truncatingRemainder(dividingBy: m)).truncatingRemainder(dividingBy: m)
        let body = lead + parsed.length
        let length = (body / m).rounded(.up) * m
        var ev: [NoteEvent] = []
        let chords = parsed.chords.map { (beat: $0.beat + lead, chord: $0.chord) }

        for pass in 0..<2 {
            let off = Double(pass) * length
            // Melody.
            for n in parsed.notes {
                guard let raw = n.midi else { continue }
                let midi = raw + 12 * p.octave
                let b = off + lead + n.beat
                let inst = pass == 0 ? p.lead : p.lead2
                ev.append(NoteEvent(beat: b, dur: n.dur * 0.94, midi: midi, vel: 0.72, inst: inst, pan: 0.04))
                if pass == 1 {
                    ev.append(NoteEvent(beat: b, dur: n.dur * 0.9, midi: midi + 12, vel: 0.2, inst: .celesta, pan: -0.2))
                }
            }
            // Accompaniment, bar by bar.
            var bar = 0.0
            while bar < length - 1e-6 {
                accompany(p.style, bar: bar, meter: p.meter, pass: pass, chordAt: { Score.chord(at: $0, in: chords) }, off: off, into: &ev)
                bar += m
            }
        }
        ev.sort { $0.beat < $1.beat }
        return (ev, length * 2)
    }

    private static func accompany(_ style: Style, bar: Double, meter: Int, pass: Int, chordAt: (Double) -> Chord?,
                                  off: Double, into ev: inout [NoteEvent]) {
        func add(_ beat: Double, _ dur: Double, _ midi: Int, _ vel: Float, _ inst: Instrument, _ pan: Float) {
            ev.append(NoteEvent(beat: off + bar + beat, dur: dur, midi: midi, vel: vel, inst: inst, pan: pan))
        }
        func chord(_ beat: Double) -> Chord? { chordAt(bar + beat) }
        func stack(_ beat: Double, _ dur: Double, _ vel: Float, _ inst: Instrument, _ pan: Float) {
            guard let c = chord(beat) else { return }
            for (i, n) in c.voicing.enumerated() { add(beat + Double(i) * 0.012, dur, n, vel, inst, pan + Float(i) * 0.05) }
        }
        let fill = pass == 1
        switch style {
        case .waltz:
            if let c = chord(0) { add(0, 1.1, c.bass, 0.62, .bass, 0) }
            stack(1, 0.8, 0.26, .pluck, -0.25)
            stack(2, 0.8, 0.22, .pluck, -0.25)
            if fill, let c = chord(0) { for n in c.voicing { add(0, Double(meter) * 0.98, n, 0.1, .pad, 0) } }
        case .folk:
            if let c = chord(0) { add(0, 1.6, c.bass, 0.6, .bass, 0); add(2, 1.6, chord(2)?.bass ?? c.bass, 0.52, .bass, 0) }
            for i in 0..<8 {
                let b = Double(i) * 0.5
                guard let c = chord(b) else { continue }
                let v = c.voicing
                let order = [0, 1, 2, 1, 3 % v.count, 2, 1, 2]
                add(b, 0.7, v[min(order[i], v.count - 1)] + 12, i % 2 == 0 ? 0.3 : 0.22, .pluck, -0.3)
            }
            if fill { add(0, 0.3, 36, 0.42, .kick, 0); add(2, 0.3, 36, 0.32, .kick, 0) }
            add(1, 0.1, 80, 0.22, .brush, 0.3); add(3, 0.1, 80, 0.22, .brush, 0.3)
        case .ballad:
            if let c = chord(0) { add(0, 3.6, c.bass, 0.55, .bass, 0) }
            if let c = chord(2), c != chord(0) { add(2, 1.8, c.bass, 0.5, .bass, 0) }
            stack(0, 1.9, 0.3, .ePiano, 0.15)
            stack(2, 1.9, 0.26, .ePiano, 0.15)
            if fill {
                for i in 0..<8 { add(Double(i) * 0.5, 0.1, 80, i % 2 == 0 ? 0.14 : 0.09, .brush, 0.35) }
                add(0, 0.3, 36, 0.3, .kick, 0)
            }
        case .march:
            if let c = chord(0) { add(0, 0.45, c.bass, 0.6, .bass, 0) }
            if let c = chord(1) { add(1, 0.45, c.fifth, 0.5, .bass, 0) }
            stack(0.5, 0.35, 0.22, .pluck, -0.3)
            stack(1.5, 0.35, 0.22, .pluck, -0.3)
            add(0, 0.25, 41, 0.45, .kick, 0)
            if fill { add(0.75, 0.08, 82, 0.16, .brush, 0.3); add(1.5, 0.08, 82, 0.2, .brush, 0.3) }
            add(1, 0.1, 84, 0.24, .brush, 0.3)
        case .bossa:
            if let c = chord(0) {
                add(0, 1.4, c.bass, 0.58, .bass, 0); add(1.5, 0.45, c.fifth, 0.45, .bass, 0)
            }
            if let c = chord(2) { add(2, 1.4, c.bass, 0.55, .bass, 0); add(3.5, 0.45, c.fifth, 0.45, .bass, 0) }
            let even = Int(bar / Double(meter)) % 2 == 0
            let hits: [Double] = even ? [0, 1.5, 3] : [0.5, 2]
            for h in hits { stack(h, 0.9, 0.24, .ePiano, 0.15) }
            for i in 0..<8 { add(Double(i) * 0.5, 0.08, 82, i % 2 == 0 ? 0.16 : 0.1, .brush, 0.35) }
            let clave: [Double] = even ? [0, 1.5, 3] : [1, 2]
            if fill { for h in clave { add(h, 0.06, 76, 0.2, .knock, -0.35) } }
        case .rag:
            if let c = chord(0) { add(0, 0.45, c.bass, 0.6, .bass, 0) }
            if let c = chord(1) { add(1, 0.45, c.fifth, 0.5, .bass, 0) }
            stack(0.5, 0.4, 0.24, .ePiano, 0.15)
            stack(1.5, 0.4, 0.24, .ePiano, 0.15)
            if fill { add(0.5, 0.08, 82, 0.12, .brush, 0.3); add(1.5, 0.08, 82, 0.12, .brush, 0.3) }
        }
    }
}

/// The music library: originals written for Tinyfolk and public-domain tunes. Instrumental only.
enum Library {
    static let all: [Piece] = [lanternWaltz, paperBoats, slowTide, uskudar, bossaLumen, greensleeves, entertainer, wiegenlied]
    static func piece(_ id: String) -> Piece? { all.first { $0.id == id } }

    static let lanternWaltz = Piece(
        id: "lantern", title: "Lantern Waltz", origin: String(localized: "Original for Tinyfolk"), tempo: 138, meter: 3,
        style: .waltz, lead: .musicBox, lead2: .celesta, free: true, melody: """
        [D] F#5:2 A5:1 | D6:2 C#6:.5 B5:.5 | [Bm] A5:2 F#5:1 | D5:3 | [G] B4:1 D5:1 G5:1 | [A] A5:2 G5:.5 F#5:.5 | [D] F#5:1.5 E5:.5 D5:1 | [A] E5:3 |
        [D] F#5:2 A5:1 | D6:2 E6:.5 F#6:.5 | [Bm] D6:2 B5:1 | F#5:3 | [Em] G5:1 B5:1 E6:1 | [A] C#6:1.5 B5:.5 A5:1 | [D] D6:2 A5:1 | D6:3
        """)

    static let paperBoats = Piece(
        id: "boats", title: "Paper Boats", origin: String(localized: "Original for Tinyfolk"), tempo: 104, meter: 4,
        style: .folk, lead: .celesta, lead2: .flute, free: true, melody: """
        [G] B4:1 D5:1 G5:1.5 F#5:.5 | [Em] E5:2 B4:2 | [C] C5:1 E5:1 G5:1 E5:1 | [D] F#5:3 R:1 |
        [G] B4:1 D5:1 G5:1.5 A5:.5 | [Em] B5:2 G5:2 | [Am7] A5:1 G5:1 E5:1 C5:1 | [D] D5:3 R:1 |
        [C] E5:1.5 G5:.5 C6:2 | [D] B5:1 A5:1 F#5:2 | [Bm] D5:1 F#5:1 B5:1.5 A5:.5 | [Em] G5:3 R:1 |
        [Am] C5:1 E5:1 A5:1 G5:1 | [D] F#5:1 A5:1 D6:1 C6:1 | [G] B5:2 A5:1 F#5:1 | [G] G5:4
        """)

    static let slowTide = Piece(
        id: "tide", title: "Slow Tide", origin: String(localized: "Original for Tinyfolk"), tempo: 72, meter: 4,
        style: .ballad, lead: .flute, lead2: .musicBox, free: true, melody: """
        [Dmaj7] R:1 A4:1 F#5:1.5 E5:.5 | [Bm7] D5:2 C#5:1 B4:1 | [Gmaj7] B4:1.5 D5:.5 F#5:2 | [A7] E5:3 R:1 |
        [Dmaj7] R:1 A4:1 F#5:1.5 G5:.5 | [F#m7] A5:2 E5:2 | [Gmaj7] F#5:1 E5:1 D5:1 B4:1 | [A7] C#5:2 E5:2 |
        [Bm7] D5:1.5 C#5:.5 B4:2 | [F#m7] C#5:1.5 B4:.5 A4:2 | [Gmaj7] B4:1 D5:1 F#5:1 A5:1 | [A7] G5:2 E5:2 |
        [Dmaj7] F#5:1.5 E5:.5 D5:2 | [Bm7] B4:1 D5:1 F#5:2 | [Gmaj7] E5:1 F#5:1 [A7] E5:1 C#5:1 | [Dmaj7] D5:4
        """)

    static let uskudar = Piece(
        id: "uskudar", title: "Üsküdar'a Gider İken (Kâtibim)", origin: String(localized: "Traditional, Türkiye"), tempo: 92, meter: 2,
        style: .march, lead: .kanun, lead2: .flute, free: true, melody: """
        [Gm] G4:.75 D5:.25 D5:.5 D5:.5 | [Cm] Eb5:.25 D5:.25 Eb5:.25 F5:.25 [Gm] D5:.5 D5:.5 | [Cm] C5:.5 C5:.25 C5:.25 Bb4:.5 C5:.5 | [D7] D5:.25 Eb5:.25 D5:.25 C5:.25 Bb4:.25 A4:.25 [Gm] G4:.5 |
        [Gm] G4:.75 D5:.25 D5:.5 D5:.5 | [Cm] Eb5:.25 D5:.25 Eb5:.25 F5:.25 [Gm] D5:.5 D5:.5 | [Cm] C5:.5 C5:.25 C5:.25 Bb4:.5 C5:.5 | [Gm] D5:.25 Eb5:.25 D5:.25 C5:.25 Bb4:.25 C5:.25 D5:.5 |
        [Gm] G4:.75 A4:.25 Bb4:.5 C5:.5 | [D7] D5:.25 Eb5:.25 D5:.25 C5:.25 Bb4:.25 A4:.25 [Gm] G4:.5 | [Cm] A4:.25 C5:.25 Bb4:.25 A4:.25 [D7] A4:.25 G4:.25 F#4:.25 G4:.25 | [D7] A4:1 R:1 |
        [Gm] G4:.75 A4:.25 Bb4:.5 C5:.5 | [D7] D5:.25 Eb5:.25 D5:.25 C5:.25 Bb4:.25 A4:.25 [Gm] G4:.5 | [Cm] A4:.25 C5:.25 Bb4:.25 A4:.25 [D7] A4:.25 G4:.25 G4:.25 F#4:.25 | [Gm] G4:2
        """)

    static let bossaLumen = Piece(
        id: "bossa", title: "Bossa Lumen", origin: String(localized: "Original for Tinyfolk"), tempo: 128, meter: 4,
        style: .bossa, lead: .flute, lead2: .ePiano, free: false, melody: """
        [Dmaj7] F#5:1.5 E5:.5 F#5:1 A5:1 | [Em7] G5:3 R:1 | [A7] E5:1.5 D5:.5 E5:1 G5:1 | [Dmaj7] F#5:3 R:1 |
        [Bm7] D5:1.5 C#5:.5 D5:1 F#5:1 | [Em7] E5:2 B4:2 | [A7] C#5:1 E5:1 G5:1.5 F#5:.5 | [Dmaj7] F#5:2 R:2 |
        [Gmaj7] B5:1.5 A5:.5 F#5:1 D5:1 | [F#m7] E5:1.5 C#5:.5 A4:2 | [Em7] G5:1.5 F#5:.5 E5:1 B4:1 | [A7] C#5:3 R:1 |
        [Dmaj7] F#5:1.5 E5:.5 F#5:1 A5:1 | [Bm7] B5:2 F#5:2 | [Em7] G5:1 E5:1 [A7] C#5:1 E5:1 | [Dmaj7] D5:4
        """)

    static let greensleeves = Piece(
        id: "greensleeves", title: "Greensleeves", origin: String(localized: "Traditional, England"), tempo: 100, meter: 3,
        style: .waltz, lead: .flute, lead2: .kanun, free: false, pickup: 0.5, melody: """
        [Am] A4:.5 | C5:1 D5:.5 E5:.75 F5:.25 E5:.5 | [G] D5:1 B4:.5 G4:.75 A4:.25 B4:.5 | [Am] C5:1 A4:.5 A4:.75 G#4:.25 A4:.5 | [E] B4:1 G#4:.5 E4:1 A4:.5 |
        [Am] C5:1 D5:.5 E5:.75 F5:.25 E5:.5 | [G] D5:1 B4:.5 G4:.75 A4:.25 B4:.5 | [Am] C5:.75 B4:.25 A4:.5 [E] G#4:.75 F#4:.25 G#4:.5 | [Am] A4:1.5 A4:1 |
        [C] G5:1.5 G5:.75 F#5:.25 E5:.5 | [G] D5:1 B4:.5 G4:.75 A4:.25 B4:.5 | [Am] C5:1 A4:.5 A4:.75 G#4:.25 A4:.5 | [E] B4:1 G#4:.5 E4:1 |
        [C] G5:1.5 G5:.75 F#5:.25 E5:.5 | [G] D5:1 B4:.5 G4:.75 A4:.25 B4:.5 | [Am] C5:.75 B4:.25 A4:.5 [E] G#4:.75 F#4:.25 G#4:.5 | [Am] A4:1.5 A4:1
        """)

    static let entertainer = Piece(
        id: "entertainer", title: "The Entertainer", origin: String(localized: "S. Joplin, 1902"), tempo: 80, meter: 2,
        style: .rag, lead: .ePiano, lead2: .musicBox, free: false, pickup: 0.5, melody: """
        [C] D4:.25 D#4:.25 | E4:.25 C5:.5 E4:.25 C5:.5 E4:.25 C5:1.25 | C5:.25 D5:.25 D#5:.25 E5:.25 C5:.25 D5:.25 E5:.5 | [G7] B4:.25 D5:.5 [C] C5:1.25 D4:.25 D#4:.25 |
        [C] E4:.25 C5:.5 E4:.25 C5:.5 E4:.25 C5:1.25 | [F] A4:.25 G4:.25 F#4:.25 A4:.25 C5:.25 E5:.5 D5:.25 | [G7] C5:.25 A4:.25 D5:1.5 | [C] C5:2
        """)

    static let wiegenlied = Piece(
        id: "wiegenlied", title: "Wiegenlied", origin: String(localized: "J. Brahms, 1868"), tempo: 92, meter: 3,
        style: .waltz, lead: .musicBox, lead2: .flute, free: false, pickup: 1, octave: 1, melody: """
        [C] E4:.5 E4:.5 | G4:2 E4:.5 E4:.5 | G4:2 E4:.5 G4:.5 | [G7] C5 B4:1.5 A4:.5 | A4 G4 D4:.5 E4:.5 | F4 D4 D4:.5 E4:.5 | F4:2 D4:.5 F4:.5 |
        [G7] B4:.5 A4:.5 G4 B4 | [C] C5:2 C4:.5 C4:.5 | [F] C5:2 A4:.5 F4:.5 | [C] G4:2 E4:.5 C4:.5 | [G7] F4 G4 A4 | [C] G4:2 C4:.5 C4:.5 |
        [F] C5:2 A4:.5 F4:.5 | [C] G4:2 E4:.5 C4:.5 | [G7] F4 E4 D4 | [C] C4:2
        """)
}
