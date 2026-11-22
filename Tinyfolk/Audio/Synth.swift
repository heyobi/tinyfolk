import AVFoundation

/// Music and sound effects, synthesized on the device (no samples, nothing to license). Every piece is arranged
/// into note events at launch; the render block runs the sequencer sample-accurately, so the beat it reports is
/// exactly what you hear and the cast can dance on it.
///
/// Threading: the main thread writes small values into `params` and pushes one-shot sounds into a ring buffer; the
/// render block owns the voices. Aligned 32/64-bit reads and writes are atomic on arm64, which is all this needs.
final class Synth {
    static let shared = Synth()

    static let maxVoices = 48
    static let ksLength = 2048
    static let ringSize = 64

    struct Params {
        var song: Int32 = -1          // requested piece index, -1 = none
        var playing: Int32 = 0
        var music: Float = 0.8
        var sfx: Float = 0.9
        var beatOut: Double = 0       // written by the render block
        var songOut: Int32 = -1
    }

    struct SongInfo { var offset: Int32; var count: Int32; var loop: Double; var tempo: Double }

    struct Event { var beat: Double; var dur: Float; var freq: Float; var vel: Float; var inst: Int32; var pan: Float }

    struct Cmd { var inst: Int32; var freq: Float; var vel: Float; var pan: Float; var dur: Float }

    struct Voice {
        var active: Int32 = 0
        var inst: Int32 = 0
        var freq: Float = 440
        var vel: Float = 0
        var panL: Float = 0.7
        var panR: Float = 0.7
        var t: Float = 0
        var dur: Float = 1
        var gate: Float = 1
        var release: Float = 0.999
        var p0: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0
        var a0: Float = 0, a1: Float = 0, a2: Float = 0, a3: Float = 0
        var k0: Float = 1, k1: Float = 1, k2: Float = 1, k3: Float = 1
        var lp1: Float = 0, lp2: Float = 0
        var ksPos: Int32 = 0
        var ksLen: Int32 = 0
        var noise: UInt32 = 22_222
        var music: Int32 = 1
    }

    struct Seq {
        var current: Int32 = -1
        var beat: Double = 0
        var index: Int32 = 0
    }

    let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private let reverb = AVAudioUnitReverb()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let params: UnsafeMutablePointer<Params>
    private let voices: UnsafeMutablePointer<Voice>
    private let ks: UnsafeMutablePointer<Float>
    private let ring: UnsafeMutablePointer<Cmd>
    private let ringHead: UnsafeMutablePointer<Int32>   // written by main
    private let ringTail: UnsafeMutablePointer<Int32>   // written by render
    private let seq: UnsafeMutablePointer<Seq>
    private var events: UnsafeMutablePointer<Event>
    private var songs: UnsafeMutablePointer<SongInfo>
    private(set) var pieceIDs: [String] = []
    private var started = false
    private(set) var lastError: String?
    private var sampleRate: Double = 48_000

    init() {
        params = .allocate(capacity: 1); params.initialize(to: Params())
        voices = .allocate(capacity: Self.maxVoices); voices.initialize(repeating: Voice(), count: Self.maxVoices)
        ks = .allocate(capacity: Self.maxVoices * Self.ksLength); ks.initialize(repeating: 0, count: Self.maxVoices * Self.ksLength)
        ring = .allocate(capacity: Self.ringSize); ring.initialize(repeating: Cmd(inst: 0, freq: 0, vel: 0, pan: 0, dur: 0), count: Self.ringSize)
        ringHead = .allocate(capacity: 1); ringHead.initialize(to: 0)
        ringTail = .allocate(capacity: 1); ringTail.initialize(to: 0)
        seq = .allocate(capacity: 1); seq.initialize(to: Seq())
        // Arrange every piece once.
        var all: [Event] = []
        var infos: [SongInfo] = []
        for p in Library.all {
            let a = Score.arrange(p)
            infos.append(SongInfo(offset: Int32(all.count), count: Int32(a.events.count), loop: a.loop, tempo: p.tempo))
            for e in a.events {
                all.append(Event(beat: e.beat, dur: Float(e.dur * 60 / p.tempo), freq: Float(Pitch.frequency(Double(e.midi))),
                                 vel: e.vel, inst: e.inst.rawValue, pan: e.pan))
            }
            pieceIDs.append(p.id)
        }
        events = .allocate(capacity: max(1, all.count))
        events.initialize(from: all, count: all.count)
        songs = .allocate(capacity: max(1, infos.count))
        songs.initialize(from: infos, count: infos.count)
    }

    // MARK: Control (main thread)

    func play(_ id: String?) {
        if let id, let i = pieceIDs.firstIndex(of: id) {
            params.pointee.song = Int32(i)
            params.pointee.playing = 1
        } else {
            params.pointee.playing = 0
        }
    }

    var isPlaying: Bool { params.pointee.playing == 1 }

    /// Current position in beats of the playing piece, or nil when silent.
    var beat: Double? {
        guard params.pointee.playing == 1, params.pointee.songOut >= 0 else { return nil }
        return params.pointee.beatOut
    }

    var musicVolume: Float {
        get { params.pointee.music }
        set { params.pointee.music = newValue }
    }

    /// A one-shot sound effect.
    func sfx(_ inst: Instrument, midi: Double, vel: Float = 0.7, pan: Float = 0, dur: Float = 0.3) {
        let head = ringHead.pointee
        let next = (head + 1) % Int32(Self.ringSize)
        if next == ringTail.pointee { return }   // full: drop
        ring[Int(head)] = Cmd(inst: inst.rawValue, freq: Float(Pitch.frequency(midi)), vel: vel, pan: pan, dur: dur)
        ringHead.pointee = next
    }

    // MARK: Engine

    func start() {
        guard !started else { resume(); return }
        let session = AVAudioSession.sharedInstance()
        do {
            // Ambient: respects the silent switch and mixes with other audio. Music is a gentle extra here.
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            lastError = "session: \(error.localizedDescription)"
        }
        let rate = session.sampleRate > 0 ? session.sampleRate : 48_000
        buildGraph(sampleRate: rate)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            let first = "engine: \((error as NSError).code)"
            engine.stop()
            engine.disconnectNodeOutput(source)
            engine.disconnectNodeOutput(eq)
            engine.disconnectNodeOutput(reverb)
            engine.connect(source, to: engine.mainMixerNode, format: nil)
            engine.prepare()
            do { try engine.start(); lastError = first + " (dry)" } catch { lastError = first + ", dry \((error as NSError).code)" }
        }
        started = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.resume()
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in self?.resume() }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in self?.resume() }
    }

    func resume() {
        guard started, !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.prepare()
        try? engine.start()
    }

    func pause() { engine.pause() }

    private func buildGraph(sampleRate rate: Double) {
        sampleRate = rate
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        source = AVAudioSourceNode(format: format, renderBlock: Self.makeRender(
            params: params, voices: voices, ks: ks, ring: ring, head: ringHead, tail: ringTail, seq: seq,
            events: events, songs: songs, songCount: Int32(pieceIDs.count), sampleRate: Float(rate)))
        engine.attach(source)
        engine.attach(eq)
        engine.attach(reverb)
        let bands: [(AVAudioUnitEQFilterType, Float, Float, Float)] = [(.highPass, 38, 0, 0.7), (.parametric, 320, -1.5, 1.2), (.highShelf, 9000, -2.5, 0.7)]
        for (i, b) in bands.enumerated() {
            eq.bands[i].filterType = b.0; eq.bands[i].frequency = b.1; eq.bands[i].gain = b.2; eq.bands[i].bandwidth = b.3; eq.bands[i].bypass = false
        }
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 22
        engine.connect(source, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
    }

    /// Offline rendering for tests (no audio hardware).
    func startOffline() throws {
        let out = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: out, maximumFrameCount: 4096)
        buildGraph(sampleRate: 48_000)
        engine.prepare()
        try engine.start()
        started = true
    }

    /// Renders `seconds` offline and returns the RMS of the left channel.
    func renderOfflineRMS(seconds: Double) throws -> Float {
        let format = engine.manualRenderingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { return 0 }
        var total: Double = 0
        var n = 0
        var remaining = Int(seconds * format.sampleRate)
        while remaining > 0 {
            let frames = AVAudioFrameCount(min(4096, remaining))
            let status = try engine.renderOffline(frames, to: buf)
            guard status == .success, let d = buf.floatChannelData else { break }
            for i in 0..<Int(buf.frameLength) { total += Double(d[0][i] * d[0][i]) }
            n += Int(buf.frameLength)
            remaining -= Int(frames)
        }
        return n > 0 ? Float(sqrt(total / Double(n))) : 0
    }

    // MARK: Render

    private static func makeRender(params: UnsafeMutablePointer<Params>, voices: UnsafeMutablePointer<Voice>,
                                   ks: UnsafeMutablePointer<Float>, ring: UnsafeMutablePointer<Cmd>,
                                   head: UnsafeMutablePointer<Int32>, tail: UnsafeMutablePointer<Int32>,
                                   seq: UnsafeMutablePointer<Seq>, events: UnsafeMutablePointer<Event>,
                                   songs: UnsafeMutablePointer<SongInfo>, songCount: Int32,
                                   sampleRate sr: Float) -> AVAudioSourceNodeRenderBlock {
        let invSR = 1 / sr
        let twoPi: Float = 2 * .pi
        let maxVoices = Self.maxVoices
        let ksLength = Self.ksLength
        let ringSize = Self.ringSize

        func noise(_ v: inout Voice) -> Float {
            v.noise ^= v.noise << 13; v.noise ^= v.noise >> 17; v.noise ^= v.noise << 5
            return Float(Int32(bitPattern: v.noise)) / Float(Int32.max)
        }

        func decay(_ seconds: Float) -> Float { expf(-invSR / max(seconds, 0.001)) }

        func trigger(_ inst: Int32, freq: Float, vel: Float, pan: Float, dur: Float, music: Bool) {
            // Free voice, else steal the oldest.
            var slot = 0
            var oldest: Float = -1
            for i in 0..<maxVoices {
                if voices[i].active == 0 { slot = i; oldest = -2; break }
                if voices[i].t > oldest { oldest = voices[i].t; slot = i }
            }
            var v = Voice()
            v.active = 1
            v.inst = inst
            v.freq = freq
            v.vel = vel
            let p = max(-1, min(1, pan))
            v.panL = cosf((p + 1) * .pi / 4)
            v.panR = sinf((p + 1) * .pi / 4)
            v.dur = dur
            v.music = music ? 1 : 0
            v.noise = UInt32(truncatingIfNeeded: slot &* 2_654_435_761 &+ Int(freq * 7)) | 1
            let low = max(0.4, min(1.6, 300 / freq))   // low notes ring longer
            switch Instrument(rawValue: inst) ?? .chirp {
            case .musicBox:
                v.a0 = 1; v.a1 = 0.3; v.a2 = 0.14; v.a3 = 0.05
                v.k0 = decay(1.8 * low); v.k1 = decay(0.7); v.k2 = decay(0.25); v.k3 = decay(0.09)
                v.release = decay(0.5)
            case .celesta:
                v.a0 = 1; v.a1 = 0.22; v.a2 = 0.08; v.a3 = 0.12
                v.k0 = decay(1.2 * low); v.k1 = decay(0.4); v.k2 = decay(0.15); v.k3 = decay(0.02)
                v.release = decay(0.35)
            case .ePiano:
                v.a0 = 1; v.a1 = 2.2; v.a3 = 0.07
                v.k0 = decay(2.2 * low); v.k1 = decay(0.35); v.k3 = decay(0.04)
                v.release = decay(0.14)
            case .pluck, .kanun:
                let len = Int32(max(8, min(Float(ksLength - 1), sr / freq)))
                v.ksLen = len
                let base = slot * ksLength
                var lp: Float = 0
                let bright: Float = inst == Instrument.kanun.rawValue ? 0.85 : 0.55
                for i in 0..<Int(len) {
                    let n = noise(&v)
                    lp += (n - lp) * bright
                    ks[base + i] = lp * 0.9
                }
                v.a0 = 1
                v.k0 = inst == Instrument.kanun.rawValue ? 0.9985 : 0.997
                v.release = decay(0.18)
            case .pad:
                v.a0 = 0
                v.release = decay(0.9)
            case .bass:
                v.a0 = 1; v.k0 = decay(1.6)
                v.release = decay(0.07)
            case .kick:
                v.a0 = 1; v.k0 = decay(0.22); v.lp2 = 1
                v.release = decay(0.2)
            case .brush:
                v.a0 = 1; v.k0 = decay(0.045 + vel * 0.04)
                v.release = decay(0.04)
            case .flute:
                v.a0 = 0
                v.release = decay(0.12)
            case .chirp:
                v.a0 = 1; v.k0 = decay(0.18)
                v.release = decay(0.06)
            case .knock:
                v.a0 = 1; v.a1 = 1; v.k0 = decay(0.05); v.k1 = decay(0.008)
                v.release = decay(0.05)
            }
            voices[slot] = v
        }

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2, let lp = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let rp = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n = Int(frameCount)
            let pr = params.pointee

            // One-shot commands from the main thread.
            while tail.pointee != head.pointee {
                let c = ring[Int(tail.pointee)]
                trigger(c.inst, freq: c.freq, vel: c.vel, pan: c.pan, dur: c.dur, music: false)
                tail.pointee = (tail.pointee + 1) % Int32(ringSize)
            }

            // Sequencer state.
            var s = seq.pointee
            let playing = pr.playing == 1 && pr.song >= 0 && pr.song < songCount
            if playing && s.current != pr.song {
                s.current = pr.song; s.beat = 0; s.index = 0
                // Let the old piece's notes ring out quickly.
                for i in 0..<maxVoices where voices[i].music == 1 { voices[i].dur = min(voices[i].dur, voices[i].t) }
            }
            if !playing && s.current >= 0 {
                for i in 0..<maxVoices where voices[i].music == 1 { voices[i].dur = min(voices[i].dur, voices[i].t) }
                s.current = -1
            }
            let info = s.current >= 0 ? songs[Int(s.current)] : SongInfo(offset: 0, count: 0, loop: 1, tempo: 120)
            let beatInc = info.tempo / 60 / Double(sr)
            let musicGain = pr.music
            let sfxGain = pr.sfx

            for f in 0..<n {
                if s.current >= 0 {
                    while s.index < info.count {
                        let e = events[Int(info.offset + s.index)]
                        if e.beat > s.beat { break }
                        trigger(e.inst, freq: e.freq, vel: e.vel, pan: e.pan, dur: e.dur, music: true)
                        s.index += 1
                    }
                    s.beat += beatInc
                    if s.beat >= info.loop { s.beat -= info.loop; s.index = 0 }
                }

                var l: Float = 0, r: Float = 0
                for i in 0..<maxVoices {
                    if voices[i].active == 0 { continue }
                    var v = voices[i]
                    let dt = invSR
                    if v.t >= v.dur { v.gate *= v.release }
                    var x: Float = 0
                    switch v.inst {
                    case 0: // music box: tine partials
                        v.p0 += v.freq * dt; v.p1 += v.freq * 2.0 * dt; v.p2 += v.freq * 5.4 * dt; v.p3 += v.freq * 8.9 * dt
                        x = v.a0 * sinf(twoPi * v.p0) + v.a1 * sinf(twoPi * v.p1) + v.a2 * sinf(twoPi * v.p2) + v.a3 * sinf(twoPi * v.p3)
                        v.a0 *= v.k0; v.a1 *= v.k1; v.a2 *= v.k2; v.a3 *= v.k3
                        x *= 0.32 * min(1, v.t * 900)
                    case 8: // celesta
                        v.p0 += v.freq * dt; v.p1 += v.freq * 3.0 * dt; v.p2 += v.freq * 6.1 * dt; v.p3 += v.freq * 11.2 * dt
                        x = v.a0 * sinf(twoPi * v.p0) + v.a1 * sinf(twoPi * v.p1) + v.a2 * sinf(twoPi * v.p2) + v.a3 * sinf(twoPi * v.p3)
                        v.a0 *= v.k0; v.a1 *= v.k1; v.a2 *= v.k2; v.a3 *= v.k3
                        x *= 0.3 * min(1, v.t * 600)
                    case 1: // electric piano: two-operator FM with a decaying index, plus a short tine
                        v.p1 += v.freq * dt
                        v.p0 += v.freq * dt
                        v.p3 += v.freq * 7 * dt
                        let mod = (v.a1 + 0.22) * sinf(twoPi * v.p1)
                        x = v.a0 * sinf(twoPi * v.p0 + mod) + v.a3 * sinf(twoPi * v.p3)
                        v.a0 *= v.k0; v.a1 *= v.k1; v.a3 *= v.k3
                        x *= 0.3 * min(1, v.t * 400)
                    case 2, 11: // plucked string (Karplus-Strong)
                        let base = i * ksLength
                        let len = Int(v.ksLen)
                        let pos = Int(v.ksPos)
                        let nxt = (pos + 1) % len
                        let y = ks[base + pos]
                        let damp = v.t >= v.dur ? Float(0.985) : v.k0
                        ks[base + pos] = (y + ks[base + nxt]) * 0.5 * damp
                        v.ksPos = Int32(nxt)
                        x = y * (v.inst == 11 ? 0.55 : 0.5)
                        v.a0 = abs(y) > 1e-4 ? 1 : v.a0 * 0.999
                    case 3: // pad: two detuned soft saws through two low-pass poles
                        v.p0 += v.freq * 1.003 * dt; v.p1 += v.freq * 0.997 * dt
                        v.p0 -= floorf(v.p0); v.p1 -= floorf(v.p1)
                        let saw = (v.p0 * 2 - 1) + (v.p1 * 2 - 1)
                        let c: Float = 0.05
                        v.lp1 += (saw - v.lp1) * c; v.lp2 += (v.lp1 - v.lp2) * c
                        let att = min(1, v.t / 0.5)
                        x = v.lp2 * 0.16 * att
                        v.a0 = 1
                    case 4: // bass: sine with a touch of second harmonic, gently saturated
                        v.p0 += v.freq * dt
                        let raw = sinf(twoPi * v.p0) + 0.28 * sinf(twoPi * v.p0 * 2)
                        let env = (0.55 + 0.45 * v.a0) * min(1, v.t * 300)
                        v.a0 *= v.k0
                        x = tanhf(raw * 1.3) * 0.42 * env
                    case 5: // soft kick / frame drum
                        let f0 = v.freq * (1 + 1.6 * v.lp2)
                        v.lp2 *= 0.9992
                        v.p0 += f0 * dt
                        x = sinf(twoPi * v.p0) * v.a0 * 0.75
                        v.a0 *= v.k0
                    case 6: // brush / shaker: high-passed noise burst
                        let nz = noise(&v)
                        v.lp1 += (nz - v.lp1) * 0.35
                        x = (nz - v.lp1) * v.a0 * 0.28
                        v.a0 *= v.k0
                    case 7: // flute: sine with breath and a vibrato that grows in
                        let vib = 1 + 0.0045 * sinf(twoPi * 5.2 * v.t) * min(1, max(0, (v.t - 0.25) * 2))
                        v.p0 += v.freq * vib * dt
                        let att = min(1, v.t / 0.07)
                        let nz = noise(&v)
                        v.lp1 += (nz - v.lp1) * 0.08
                        x = (sinf(twoPi * v.p0) + 0.12 * sinf(twoPi * v.p0 * 2) + 0.04 * sinf(twoPi * v.p0 * 3) + v.lp1 * 0.25) * 0.3 * att
                        v.a0 = 1
                    case 9: // chirp: a little voice blip that slides up
                        let glide = 1 + 0.6 * min(1, v.t / 0.08)
                        v.p0 += v.freq * glide * dt
                        x = sinf(twoPi * v.p0 + 0.6 * sinf(twoPi * v.p0 * 2)) * v.a0 * 0.35 * min(1, v.t * 500)
                        v.a0 *= v.k0
                    case 10: // knock: a small wooden tok
                        v.p0 += v.freq * dt
                        let nz = noise(&v)
                        x = (sinf(twoPi * v.p0) * v.a0 + nz * v.a1 * 0.5) * 0.55
                        v.a0 *= v.k0; v.a1 *= v.k1
                    default:
                        v.a0 = 0
                    }
                    v.p0 -= floorf(v.p0); v.p1 -= floorf(v.p1); v.p2 -= floorf(v.p2); v.p3 -= floorf(v.p3)
                    let g = v.vel * v.gate * (v.music == 1 ? musicGain : sfxGain)
                    l += x * g * v.panL
                    r += x * g * v.panR
                    v.t += dt
                    let silent = v.gate < 0.0005 || (v.a0 < 0.0003 && v.inst != 3 && v.inst != 7) || v.t > 12
                    if silent { v.active = 0 }
                    voices[i] = v
                }
                // Gentle limiter.
                lp[f] = l / (1 + abs(l))
                rp[f] = r / (1 + abs(r))
            }
            seq.pointee = s
            params.pointee.beatOut = s.beat
            params.pointee.songOut = s.current
            return noErr
        }
    }
}
