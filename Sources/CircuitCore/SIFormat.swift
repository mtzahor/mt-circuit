import Foundation

/// Parsing and formatting of values with SI prefixes ("4.7k", "10 µF", "4k7", "1MHz").
public enum SIFormat {
    private static let prefixes: [(symbol: String, exponent: Int)] = [
        ("a", -18), ("f", -15), ("p", -12), ("n", -9), ("µ", -6), ("m", -3),
        ("", 0), ("k", 3), ("M", 6), ("G", 9), ("T", 12),
    ]

    private static let parsePrefixes: [Character: Double] = [
        "f": 1e-15, "p": 1e-12, "n": 1e-9, "u": 1e-6, "µ": 1e-6, "μ": 1e-6,
        "m": 1e-3, "k": 1e3, "K": 1e3, "M": 1e6, "G": 1e9, "T": 1e12,
    ]

    private static let units: Set<String> = [
        "ω", "ohm", "ohms", "f", "h", "v", "a", "hz", "s", "sec", "°", "deg", "db",
    ]

    /// Formats `value` with an SI prefix and up to `significantDigits` significant digits.
    public static func string(_ value: Double, unit: String = "", significantDigits: Int = 3) -> String {
        let separator = unit.isEmpty ? "" : " "
        guard value.isFinite else { return value.isNaN ? "NaN" : (value > 0 ? "∞" : "-∞") }
        if value == 0 { return "0\(separator)\(unit)" }

        let magnitude = abs(value)
        var exponent = Int(floor(log10(magnitude) / 3)) * 3
        exponent = min(max(exponent, prefixes.first!.exponent), prefixes.last!.exponent)
        var scaled = value / pow(10, Double(exponent))

        // Rounding can push 999.7 up to 1000; move to the next prefix when that happens.
        let rounded = roundToSignificant(scaled, digits: significantDigits)
        if abs(rounded) >= 1000, exponent < prefixes.last!.exponent {
            exponent += 3
            scaled = value / pow(10, Double(exponent))
        }
        let prefix = prefixes.first { $0.exponent == exponent }?.symbol ?? ""
        let number = trimmed(roundToSignificant(scaled, digits: significantDigits), significantDigits: significantDigits)
        if prefix.isEmpty && unit.isEmpty { return number }
        return "\(number) \(prefix)\(unit)"
    }

    /// Formats a value without a unit, using SI prefixes (handy for text fields: "4.7k").
    public static func compact(_ value: Double, significantDigits: Int = 4) -> String {
        string(value, unit: "", significantDigits: significantDigits).replacingOccurrences(of: " ", with: "")
    }

    /// Parses a number with an optional SI prefix and optional unit.
    ///
    /// Accepts "1e-3", "4.7k", "10uF", "100 nF", "1meg", "2.2µ", "4k7", "1MHz", "-5V".
    /// Note: "m" is milli and "M" is mega; "meg" (any case) is also mega.
    public static func parse(_ text: String) -> Double? {
        var s = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !s.isEmpty else { return nil }

        // Leading number (with optional sign, decimal point, and exponent).
        var numberEnd = s.startIndex
        var seenDigit = false, seenDot = false
        var i = s.startIndex
        if i < s.endIndex, s[i] == "+" || s[i] == "-" { i = s.index(after: i) }
        while i < s.endIndex {
            let c = s[i]
            if c.isASCII && c.isNumber {
                seenDigit = true
            } else if c == "." && !seenDot {
                seenDot = true
            } else {
                break
            }
            i = s.index(after: i)
            numberEnd = i
        }
        guard seenDigit else { return nil }
        // Exponent: only when "e" is followed by an (optionally signed) digit.
        if numberEnd < s.endIndex, s[numberEnd] == "e" || s[numberEnd] == "E" {
            var j = s.index(after: numberEnd)
            if j < s.endIndex, s[j] == "+" || s[j] == "-" { j = s.index(after: j) }
            if j < s.endIndex, s[j].isASCII, s[j].isNumber {
                while j < s.endIndex, s[j].isASCII, s[j].isNumber { j = s.index(after: j) }
                numberEnd = j
            }
        }
        guard var number = Double(s[s.startIndex..<numberEnd]) else { return nil }
        s = s[numberEnd...].drop(while: { $0 == " " })

        // SI prefix.
        if s.lowercased().hasPrefix("meg") {
            number *= 1e6
            s = s.dropFirst(3)
        } else if let first = s.first, let multiplier = parsePrefixes[first] {
            // A bare "F" or "H" etc. is a unit, but "f" is femto. "m" alone is milli.
            let rest = s.dropFirst()
            // "4k7" notation: prefix acts as the decimal point.
            if !rest.isEmpty, rest.allSatisfy({ $0.isASCII && $0.isNumber }), !seenDot {
                guard let fraction = Double("0." + rest) else { return nil }
                return (number + (number < 0 ? -fraction : fraction)) * multiplier
            }
            if rest.isEmpty || units.contains(rest.lowercased()) {
                return number * multiplier
            }
            // Could be a unit that starts with a prefix letter (none currently), fall through.
            if units.contains(String(s).lowercased()) { return number }
            return nil
        }

        let unit = s.trimmingCharacters(in: .whitespaces).lowercased()
        if unit.isEmpty || units.contains(unit) { return number }
        return nil
    }

    private static func roundToSignificant(_ x: Double, digits: Int) -> Double {
        guard x != 0 else { return 0 }
        let magnitude = Int(floor(log10(abs(x)))) + 1
        let factor = pow(10, Double(digits - magnitude))
        return (x * factor).rounded() / factor
    }

    private static func trimmed(_ x: Double, significantDigits: Int) -> String {
        let magnitude = x == 0 ? 1 : Int(floor(log10(abs(x)))) + 1
        let decimals = max(0, significantDigits - magnitude)
        var text = String(format: "%.\(decimals)f", x)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return text
    }
}
