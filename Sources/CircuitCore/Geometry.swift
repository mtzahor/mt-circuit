/// A point on the schematic grid, in grid units.
public struct GridPoint: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public static let zero = GridPoint(0, 0)

    public static func + (lhs: GridPoint, rhs: GridPoint) -> GridPoint {
        GridPoint(lhs.x + rhs.x, lhs.y + rhs.y)
    }

    public static func - (lhs: GridPoint, rhs: GridPoint) -> GridPoint {
        GridPoint(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    /// Rotates an offset by `quarterTurns` × 90° clockwise (screen coordinates, y pointing down).
    public func rotated(by quarterTurns: Int) -> GridPoint {
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1: GridPoint(-y, x)
        case 2: GridPoint(-x, -y)
        case 3: GridPoint(y, -x)
        default: self
        }
    }

    public var description: String { "(\(x), \(y))" }
}

extension GridPoint {
    /// Whether `self` lies on the axis-aligned or diagonal segment `a`–`b` (endpoints included).
    public func lies(onSegmentFrom a: GridPoint, to b: GridPoint) -> Bool {
        let cross = (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)
        guard cross == 0 else { return false }
        return x >= min(a.x, b.x) && x <= max(a.x, b.x)
            && y >= min(a.y, b.y) && y <= max(a.y, b.y)
    }
}
