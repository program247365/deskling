import Foundation

public enum CharacterSize: String, CaseIterable {
    case small, medium, large

    public var width: CGFloat {
        switch self {
        case .small: 120
        case .medium: 180
        case .large: 280
        }
    }

    /// The animations are 2750 x 1850.
    public var size: CGSize { CGSize(width: width, height: width * 1850 / 2750) }
}

/// Where Clawd can be: the usable area of the display and his window size. AppKit coordinates (y up).
public struct Stage: Equatable {
    public let visibleFrame: CGRect
    public let size: CGSize

    /// Share of the canvas height that is empty below his feet in the walking animation.
    public static let footInsetFraction: CGFloat = 0

    public init(visibleFrame: CGRect, size: CGSize) {
        self.visibleFrame = visibleFrame
        self.size = size
    }

    /// Window origin.y that puts his feet on the bottom of the usable area.
    public var floorY: CGFloat { visibleFrame.minY - size.height * Self.footInsetFraction }

    /// How far he can travel horizontally.
    public var maxX: CGFloat { max(0, visibleFrame.width - size.width) }

    public func floorOrigin(x offset: CGFloat) -> CGPoint {
        CGPoint(x: visibleFrame.minX + min(max(offset, 0), maxX), y: floorY)
    }

    /// Where his launch entrance begins: just above the usable area, over the same spot on the floor.
    public func entranceOrigin(x offset: CGFloat) -> CGPoint {
        CGPoint(x: floorOrigin(x: offset).x, y: visibleFrame.maxY)
    }

    /// How wide the entrance spotlight is where it meets the floor, in Clawd-widths.
    public static let spotlightWidthFactor: CGFloat = 1.5

    /// How far from the middle of the spotlight his walk into it begins when he leaves, in Clawd-widths.
    public static let exitApproachFactor: CGFloat = 0.75

    /// The entrance spotlight: a column from the floor to the top of the usable area, centred on him.
    public func spotlightFrame(x offset: CGFloat) -> CGRect {
        let width = size.width * Self.spotlightWidthFactor
        let centre = floorOrigin(x: offset).x + size.width / 2
        return CGRect(x: centre - width / 2, y: visibleFrame.minY, width: width, height: visibleFrame.height)
    }

    /// A random spot where he is fully on screen.
    public func teleportOrigin<R: RandomNumberGenerator>(using rng: inout R) -> CGPoint {
        let roomX = visibleFrame.width - size.width
        let roomY = visibleFrame.height - size.height
        guard roomX > 0, roomY > 0 else { return visibleFrame.origin }
        return CGPoint(
            x: visibleFrame.minX + CGFloat.random(in: 0...roomX, using: &rng),
            y: visibleFrame.minY + CGFloat.random(in: 0...roomY, using: &rng))
    }

    /// The nearest position inside the usable area.
    public func clamp(_ origin: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.minX + maxX),
            y: min(max(origin.y, floorY), max(floorY, visibleFrame.maxY - size.height)))
    }
}
