import Foundation

public enum TextNorm {
    /// Нижний регистр, ё→е, всё кроме букв/цифр → пробелы, схлопывание пробелов.
    public static func normalize(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var lastSpace = true
        for ch in s.lowercased() {
            var c = ch
            if c == "ё" { c = "е" }
            if c.isLetter || c.isNumber {
                out.append(c); lastSpace = false
            } else if !lastSpace {
                out.append(" "); lastSpace = true
            }
        }
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    public static func tokens(_ s: String) -> [String] {
        normalize(s).split(separator: " ").map(String.init)
    }
}
