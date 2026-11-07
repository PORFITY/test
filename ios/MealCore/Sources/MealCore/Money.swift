import Foundation

/// Деньги в копейках (целое число — никаких ошибок округления Double при суммировании).
public struct Money: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public var kopecks: Int
    public init(kopecks: Int) { self.kopecks = kopecks }
    public static let zero = Money(kopecks: 0)

    /// Из рублей (Double) с математическим округлением до копейки.
    public static func rub(_ value: Double) -> Money {
        let x = value * 100
        return Money(kopecks: Int((x + (x >= 0 ? 1e-6 : -1e-6)).rounded()))
    }
    public static func rub(_ value: Int) -> Money { Money(kopecks: value * 100) }

    public var rubles: Double { Double(kopecks) / 100 }

    public static func + (a: Money, b: Money) -> Money { Money(kopecks: a.kopecks + b.kopecks) }
    public static func - (a: Money, b: Money) -> Money { Money(kopecks: a.kopecks - b.kopecks) }
    public static func * (a: Money, n: Int) -> Money { Money(kopecks: a.kopecks * n) }
    public static func += (a: inout Money, b: Money) { a.kopecks += b.kopecks }
    public static func -= (a: inout Money, b: Money) { a.kopecks -= b.kopecks }
    public static func < (a: Money, b: Money) -> Bool { a.kopecks < b.kopecks }

    /// Умножение на дробный коэффициент с округлением до копейки (half away from zero).
    public func scaled(_ factor: Double) -> Money { Money(kopecks: Int((Double(kopecks) * factor).rounded())) }

    /// Деление на целое с округлением (для «на человека», «на день»).
    public func divided(by n: Int) -> Money {
        guard n > 0 else { return self }
        return Money(kopecks: Int((Double(kopecks) / Double(n)).rounded()))
    }

    public static func sum<S: Sequence>(_ items: S) -> Money where S.Element == Money {
        var t = Money.zero
        for i in items { t += i }
        return t
    }

    /// «1 234 ₽» или «1 234,50 ₽».
    public var description: String { formatted() }

    public func formatted(showKopecks: Bool? = nil) -> String {
        let neg = kopecks < 0
        let k = abs(kopecks)
        let whole = k / 100
        let frac = k % 100
        var s = String(whole)
        var grouped = ""
        var count = 0
        for ch in s.reversed() {
            if count > 0 && count % 3 == 0 { grouped.append("\u{00A0}") }
            grouped.append(ch)
            count += 1
        }
        s = String(grouped.reversed())
        let withKop = showKopecks ?? (frac != 0)
        let body = withKop ? "\(s),\(frac < 10 ? "0" : "")\(frac)" : s
        return (neg ? "−" : "") + body + "\u{00A0}₽"
    }
}
