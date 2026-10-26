import Foundation

// MARK: - Complex numbers

public struct Complex: Hashable, Sendable, CustomStringConvertible {
    public var re: Double
    public var im: Double

    public init(_ re: Double, _ im: Double = 0) {
        self.re = re
        self.im = im
    }

    public init(magnitude: Double, phase: Double) {
        self.init(magnitude * cos(phase), magnitude * sin(phase))
    }

    public static let zero = Complex(0, 0)
    public static let one = Complex(1, 0)
    public static let i = Complex(0, 1)

    public var magnitude: Double { hypot(re, im) }
    /// Phase angle in radians, in (-π, π].
    public var phase: Double { atan2(im, re) }
    public var conjugate: Complex { Complex(re, -im) }

    public static func + (a: Complex, b: Complex) -> Complex { Complex(a.re + b.re, a.im + b.im) }
    public static func - (a: Complex, b: Complex) -> Complex { Complex(a.re - b.re, a.im - b.im) }
    public static prefix func - (a: Complex) -> Complex { Complex(-a.re, -a.im) }
    public static func * (a: Complex, b: Complex) -> Complex {
        Complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re)
    }
    public static func / (a: Complex, b: Complex) -> Complex {
        // Smith's algorithm, avoids overflow for large/small components.
        if abs(b.re) >= abs(b.im) {
            let r = b.im / b.re, d = b.re + b.im * r
            return Complex((a.re + a.im * r) / d, (a.im - a.re * r) / d)
        } else {
            let r = b.re / b.im, d = b.re * r + b.im
            return Complex((a.re * r + a.im) / d, (a.im * r - a.re) / d)
        }
    }
    public static func += (a: inout Complex, b: Complex) { a = a + b }
    public static func -= (a: inout Complex, b: Complex) { a = a - b }

    public var description: String {
        im >= 0 ? "\(re)+\(im)i" : "\(re)\(im)i"
    }
}

// MARK: - Dense LU solver

/// Field operations needed by the MNA solver; implemented by `Double` and `Complex`.
protocol MNAScalar: Sendable {
    static var zero: Self { get }
    static var one: Self { get }
    static func + (a: Self, b: Self) -> Self
    static func - (a: Self, b: Self) -> Self
    static func * (a: Self, b: Self) -> Self
    static func / (a: Self, b: Self) -> Self
    static prefix func - (a: Self) -> Self
    static func += (a: inout Self, b: Self)
    static func -= (a: inout Self, b: Self)
    var magnitude: Double { get }
}

extension Double: MNAScalar {
    static var one: Double { 1 }
}
extension Complex: MNAScalar {}

struct DenseMatrix<T: MNAScalar> {
    let size: Int
    var storage: [T]

    init(size: Int) {
        self.size = size
        storage = Array(repeating: T.zero, count: size * size)
    }

    subscript(row: Int, column: Int) -> T {
        get { storage[row * size + column] }
        set { storage[row * size + column] = newValue }
    }

    /// Adds `value` at (row, column); `nil` indices refer to the ground node and are dropped.
    mutating func add(_ row: Int?, _ column: Int?, _ value: T) {
        guard let row, let column else { return }
        storage[row * size + column] += value
    }
}

struct SingularMatrixError: Error {
    /// Index of the unknown whose pivot vanished.
    let unknown: Int
}

/// LU factorization with partial pivoting (PA = LU), reusable for many right-hand sides.
struct LUFactorization<T: MNAScalar> {
    private let size: Int
    private var lu: [T]
    private var permutation: [Int]

    init(_ matrix: DenseMatrix<T>) throws {
        let n = matrix.size
        size = n
        lu = matrix.storage
        permutation = Array(0..<n)

        // Column scales, used to judge whether a pivot is negligible.
        var columnScale = Array(repeating: 0.0, count: n)
        for r in 0..<n {
            for c in 0..<n { columnScale[c] = max(columnScale[c], lu[r * n + c].magnitude) }
        }

        for k in 0..<n {
            var pivotRow = k
            var pivotMagnitude = lu[k * n + k].magnitude
            for r in (k + 1)..<n {
                let m = lu[r * n + k].magnitude
                if m > pivotMagnitude {
                    pivotMagnitude = m
                    pivotRow = r
                }
            }
            if pivotMagnitude == 0 || pivotMagnitude < 1e-14 * columnScale[k] {
                throw SingularMatrixError(unknown: k)
            }
            if pivotRow != k {
                for c in 0..<n { lu.swapAt(k * n + c, pivotRow * n + c) }
                permutation.swapAt(k, pivotRow)
            }
            let pivot = lu[k * n + k]
            for r in (k + 1)..<n {
                let factor = lu[r * n + k] / pivot
                if factor.magnitude == 0 { continue }
                lu[r * n + k] = factor
                for c in (k + 1)..<n {
                    lu[r * n + c] -= factor * lu[k * n + c]
                }
            }
        }
    }

    func solve(_ b: [T]) -> [T] {
        let n = size
        var x = permutation.map { b[$0] }
        // Forward substitution (L has a unit diagonal).
        for r in 0..<n {
            var sum = x[r]
            for c in 0..<r { sum -= lu[r * n + c] * x[c] }
            x[r] = sum
        }
        // Back substitution.
        for r in stride(from: n - 1, through: 0, by: -1) {
            var sum = x[r]
            for c in (r + 1)..<n { sum -= lu[r * n + c] * x[c] }
            x[r] = sum / lu[r * n + r]
        }
        return x
    }
}
