import Foundation
import simd

/// A face found in one camera frame, in the camera image after it has been turned upright and mirrored so that
/// image axes match the screen the camera sits in (x right, y up).
struct FaceBox: Equatable {
    /// Normalised box, origin bottom-left (Vision convention).
    var x: Float, y: Float, w: Float, h: Float
    /// Yaw of the face in radians if known (0 = facing the camera).
    var yaw: Float?
}

/// Pinhole model of the front camera to place a face in 3-D from its box size.
struct CameraModel: Equatable {
    /// Image size in pixels after orientation (width, height).
    var imageSize: SIMD2<Float>
    /// Horizontal field of view of the sensor's long side, in degrees (AVCaptureDevice.Format.videoFieldOfView).
    var longSideFOV: Float
    /// Typical width of a face box in metres (Vision boxes span roughly ear to ear).
    var faceWidth: Float = 0.15

    var focalPixels: Float {
        let long = max(imageSize.x, imageSize.y)
        return (long / 2) / tan(longSideFOV * .pi / 360)
    }

    /// Position of the point between the eyes relative to the camera: x right, y up, z out of the screen.
    func position(of box: FaceBox) -> SIMD3<Float> {
        let f = focalPixels
        // Box area is steadier than its width alone (Vision's box breathes as the head turns).
        let sizePx = max((box.w * imageSize.x * box.h * imageSize.y).squareRoot(), 1)
        let z = f * faceWidth / sizePx
        let cx = (box.x + box.w / 2) * imageSize.x - imageSize.x / 2
        // Eyes sit a little above the middle of the box.
        let cy = (box.y + box.h * 0.58) * imageSize.y - imageSize.y / 2
        return SIMD3(cx * z / f, cy * z / f, z)
    }
}

/// Where the front camera sits: on which display surface and where on it (fractions across and up).
struct CameraMount: Equatable {
    var onUpper: Bool
    var u: Float
    var v: Float

    /// Eye position in the world given the camera-relative position and the surface the camera is in.
    static func eye(_ local: SIMD3<Float>, on surface: Surface, u: Float, v: Float) -> SIMD3<Float> {
        surface.point(u, v) + surface.vr * local.x + surface.vu * local.y + surface.normal * local.z
    }
}

/// One person seen by the camera, in world coordinates.
struct Detection: Equatable {
    var position: SIMD3<Float>
    /// True when the face is turned toward the display.
    var looking: Bool
}

enum ViewerEvent: Equatable {
    case arrived(id: Int)
    /// A second person joined someone already watching: the character's big moment.
    case secondArrived(id: Int)
    case left(id: Int)
    case primaryChanged(id: Int)
}

/// Keeps up to two viewers across frames, picks the primary viewer (whose eye the perspective follows) and the one
/// the character pays attention to. Pure logic so it can be unit-tested with synthetic frames.
struct ViewerTracker {
    struct Track: Equatable {
        let id: Int
        var position: SIMD3<Float>
        var firstSeen: Double
        var lastSeen: Double
        var hits: Int
        var looking: Bool
        var lookingSince: Double?
        var lastLooked: Double
        var announced = false
        var confirmed: Bool { hits >= 3 }
    }

    static let maxViewers = 2
    static let matchDistance: Float = 0.3
    static let lostAfter = 1.6
    static let switchLookAway = 1.2
    static let switchNearer = 1.6
    static let attentionDwell = 3.6
    static let newLookerFocus = 2.4

    private(set) var tracks: [Track] = []
    private(set) var primaryID: Int?
    private(set) var attentionID: Int?
    private var nextID = 1
    private var attentionSince: Double = 0
    private var otherBetterSince: Double?
    private var filters: [Int: OneEuro3] = [:]

    var confirmed: [Track] { tracks.filter(\.confirmed) }
    var primary: Track? { tracks.first { $0.id == primaryID } }
    var attention: Track? { tracks.first { $0.id == attentionID } }

    mutating func reset() {
        tracks = []; primaryID = nil; attentionID = nil; filters = [:]; otherBetterSince = nil
    }

    @discardableResult
    mutating func update(_ detections: [Detection], t: Double) -> [ViewerEvent] {
        var events: [ViewerEvent] = []
        var unmatched = Array(detections.prefix(4))
        // Greedy nearest-neighbour association: tracks are few, so this is enough.
        var used = Set<Int>()
        let order = tracks.indices.sorted { tracks[$0].lastSeen > tracks[$1].lastSeen }
        for i in order {
            var best: (Int, Float)?
            for (j, d) in unmatched.enumerated() {
                let dist = simd_distance(d.position, tracks[i].position)
                if dist < Self.matchDistance && (best == nil || dist < best!.1) { best = (j, dist) }
            }
            if let found = best {
                let d = unmatched.remove(at: found.0)
                apply(d, to: i, t: t)
                used.insert(tracks[i].id)
            }
        }
        // New tracks for what is left, nearest first.
        for d in unmatched.sorted(by: { $0.position.z < $1.position.z }) where tracks.count < Self.maxViewers {
            let id = nextID
            nextID += 1
            tracks.append(Track(id: id, position: d.position, firstSeen: t, lastSeen: t, hits: 1, looking: d.looking,
                                lookingSince: d.looking ? t : nil, lastLooked: d.looking ? t : 0))
            var f = OneEuro3(minCutoff: 0.7, beta: 0.45)
            _ = f.filter(d.position, t: t)
            filters[id] = f
        }
        // Drop lost tracks.
        let lost = tracks.filter { t - $0.lastSeen > Self.lostAfter }
        for l in lost {
            if l.announced { events.append(.left(id: l.id)) }
            filters[l.id] = nil
        }
        tracks.removeAll { t - $0.lastSeen > Self.lostAfter }

        // Announce confirmed arrivals.
        for i in tracks.indices where tracks[i].confirmed && !tracks[i].announced {
            tracks[i].announced = true
            let others = tracks.filter { $0.id != tracks[i].id && $0.announced }
            events.append(others.isEmpty ? .arrived(id: tracks[i].id) : .secondArrived(id: tracks[i].id))
        }

        if let changed = choosePrimary(t: t) { events.append(.primaryChanged(id: changed)) }
        chooseAttention(t: t)
        return events
    }

    private mutating func apply(_ d: Detection, to i: Int, t: Double) {
        let id = tracks[i].id
        var f = filters[id] ?? OneEuro3(minCutoff: 0.7, beta: 0.45)
        tracks[i].position = f.filter(d.position, t: t)
        filters[id] = f
        tracks[i].lastSeen = t
        tracks[i].hits += 1
        if d.looking {
            if !tracks[i].looking { tracks[i].lookingSince = t }
            tracks[i].lastLooked = t
        } else {
            tracks[i].lookingSince = nil
        }
        tracks[i].looking = d.looking
    }

    /// Keeps the primary viewer steady; hands over when they look away while the other looks, or when the other
    /// is clearly nearer for a while. Returns the new id when it changed.
    private mutating func choosePrimary(t: Double) -> Int? {
        let live = confirmed
        guard !live.isEmpty else {
            if primaryID != nil && primary == nil { primaryID = nil }
            return nil
        }
        guard let current = live.first(where: { $0.id == primaryID }) else {
            let pick = live.min { $0.position.z < $1.position.z }!
            primaryID = pick.id
            otherBetterSince = nil
            return pick.id
        }
        guard let other = live.first(where: { $0.id != current.id }) else { otherBetterSince = nil; return nil }
        let lookingHandOff = other.looking && !current.looking && t - current.lastLooked > Self.switchLookAway
        let nearer = other.position.z < current.position.z * 0.75
        if lookingHandOff {
            primaryID = other.id
            otherBetterSince = nil
            return other.id
        }
        if nearer {
            if let s = otherBetterSince, t - s > Self.switchNearer {
                primaryID = other.id
                otherBetterSince = nil
                return other.id
            }
            if otherBetterSince == nil { otherBetterSince = t }
        } else {
            otherBetterSince = nil
        }
        return nil
    }

    /// Whom the character looks at: whoever is looking; a new looker gets a moment of focus; two lookers share it.
    private mutating func chooseAttention(t: Double) {
        let live = confirmed
        guard !live.isEmpty else { attentionID = nil; return }
        let lookers = live.filter(\.looking)
        func set(_ id: Int) { if attentionID != id { attentionID = id; attentionSince = t } }
        switch lookers.count {
        case 0:
            if let p = primaryID { set(p) } else { set(live[0].id) }
        case 1:
            set(lookers[0].id)
        default:
            // Someone who just started looking gets the character's attention first.
            if let fresh = lookers.max(by: { ($0.lookingSince ?? 0) < ($1.lookingSince ?? 0) }),
               let since = fresh.lookingSince, t - since < Self.newLookerFocus, attentionID != fresh.id,
               since > attentionSince {
                set(fresh.id)
            } else if attentionID == nil || !lookers.contains(where: { $0.id == attentionID }) {
                set(lookers[0].id)
            } else if t - attentionSince > Self.attentionDwell {
                if let other = lookers.first(where: { $0.id != attentionID }) { set(other.id) }
            }
        }
    }
}

/// Smoothly hands the rendering eye from one viewer to another (ease in-out over a fixed time) and follows the
/// primary viewer otherwise.
struct EyeBlender {
    static let duration = 0.7
    private(set) var eye: SIMD3<Float>
    private var from: SIMD3<Float>
    private var startedAt: Double = -10
    private var followingID: Int?

    init(_ eye: SIMD3<Float>) {
        self.eye = eye
        self.from = eye
    }

    mutating func update(target: SIMD3<Float>, id: Int?, t: Double) -> SIMD3<Float> {
        if id != followingID {
            from = eye
            startedAt = t
            followingID = id
        }
        let p = min(max((t - startedAt) / Self.duration, 0), 1)
        let e = Float(p * p * (3 - 2 * p))
        eye = from + (target - from) * e
        return eye
    }
}
