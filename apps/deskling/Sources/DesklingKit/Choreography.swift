import Foundation

public enum Facing {
    case left, right
}

/// Hands out every act once, in random order, before repeating any.
public struct ActQueue {
    private let names: [String]
    private var remaining: [String] = []

    public init(names: [String]) {
        self.names = names
    }

    public mutating func next<R: RandomNumberGenerator>(using rng: inout R) -> String? {
        if remaining.isEmpty { remaining = names.shuffled(using: &rng) }
        return remaining.popLast()
    }
}

/// The rules of Clawd's routine, carried over from the web page.
public enum Choreography {
    /// Walking speed in Clawd-widths per second (the page's 140px/s at 360px wide).
    public static let walkSpeedFactor: CGFloat = 140.0 / 360.0
    /// Acts shorter than this many frames play twice.
    public static let shortActFrames = 40
    public static let teleportChance = 0.25
    /// Longest movement tick honored, so a stalled clock cannot make him leap.
    public static let maxStep: TimeInterval = 0.05
    /// How fast he falls on his entrance, in points per second squared: about 0.9s from the top of a laptop screen.
    public static let gravity: CGFloat = 2400

    /// Where a fall from `top` toward `floor` has got to after `elapsed` seconds (y is up, so top > floor).
    public static func drop(from top: CGFloat, to floor: CGFloat, elapsed: TimeInterval) -> (y: CGFloat, landed: Bool) {
        let seconds = CGFloat(max(elapsed, 0))
        let y = top - 0.5 * gravity * seconds * seconds
        return y <= floor ? (floor, true) : (y, false)
    }

    /// The fall played backwards, for his exit: where a lift from `floor` toward `top` has got to after `elapsed` seconds.
    public static func rise(from floor: CGFloat, to top: CGFloat, elapsed: TimeInterval) -> (y: CGFloat, gone: Bool) {
        let seconds = CGFloat(max(elapsed, 0))
        let y = floor + 0.5 * gravity * seconds * seconds
        return y >= top ? (top, true) : (y, false)
    }

    public static func plays(forFrameCount frameCount: Int) -> Int {
        frameCount < shortActFrames ? 2 : 1
    }

    /// A Clawd kept at the bottom never teleports; one allowed to roam does about one time in four.
    public static func shouldTeleport<R: RandomNumberGenerator>(roams: Bool, using rng: inout R) -> Bool {
        roams && Double.random(in: 0..<1, using: &rng) < teleportChance
    }

    /// Where to walk next: at least a third of the way across, alternating direction when there is room.
    /// `x` and the result are offsets in `0...maxX`.
    public static func nextWalkStop<R: RandomNumberGenerator>(
        from x: CGFloat, facing: Facing, maxX: CGFloat, using rng: inout R
    ) -> CGFloat {
        let minHop = maxX / 3
        let goRight = facing == .left ? x + minHop <= maxX : x - minHop < 0
        let roll = CGFloat.random(in: 0..<1, using: &rng)
        let stop = goRight
            ? x + minHop + roll * max(0, maxX - x - minHop)
            : roll * max(0, x - minHop)
        return min(max(stop, 0), max(maxX, 0))
    }

    /// One movement tick toward `target`.
    public static func step(
        x: CGFloat, toward target: CGFloat, width: CGFloat, elapsed: TimeInterval
    ) -> (x: CGFloat, arrived: Bool) {
        let distance = width * walkSpeedFactor * CGFloat(min(max(elapsed, 0), maxStep))
        if abs(target - x) <= distance { return (target, true) }
        return (x + (target > x ? distance : -distance), false)
    }
}
