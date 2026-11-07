import Foundation

/// Базовая единица ингредиента: граммы, миллилитры или штуки.
public enum BaseUnit: String, Codable, Sendable, CaseIterable {
    case g, ml, pcs
    public var short: String {
        switch self { case .g: return "г"; case .ml: return "мл"; case .pcs: return "шт" }
    }
}

/// Пищевая ценность. Для ингредиентов — на 100 г; для блюд — на порцию (см. контекст использования).
public struct Nutrition: Codable, Hashable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var fat: Double
    public var carbs: Double
    public init(kcal: Double = 0, protein: Double = 0, fat: Double = 0, carbs: Double = 0) {
        self.kcal = kcal; self.protein = protein; self.fat = fat; self.carbs = carbs
    }
    public static let zero = Nutrition()
    public static func + (a: Nutrition, b: Nutrition) -> Nutrition {
        Nutrition(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, fat: a.fat + b.fat, carbs: a.carbs + b.carbs)
    }
    public static func += (a: inout Nutrition, b: Nutrition) { a = a + b }
    public func scaled(_ f: Double) -> Nutrition {
        Nutrition(kcal: kcal * f, protein: protein * f, fat: fat * f, carbs: carbs * f)
    }
}

public enum StorageKind: String, Codable, Sendable {
    case pantry, fridge
    public var title: String { self == .pantry ? "Сухое тёмное место" : "Холодильник (0…+4 °C)" }
}

/// Запись справочника ингредиентов.
public struct IngredientInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let unit: BaseUnit
    public let cat: String
    public let kcal: Double
    public let p: Double
    public let f: Double
    public let c: Double
    public let dens: Double?
    public let pcsG: Double?
    public let shelf: Int
    public let frozen: Int
    public let store: StorageKind
    public let allergens: [String]
    public let tsp: Double?
    public let tbsp: Double?
    public let cup: Double?
    public let kw: [String]
    public let ex: [String]

    /// Масса одной базовой единицы, г.
    public var gramsPerUnit: Double {
        switch unit {
        case .g: return 1
        case .ml: return dens ?? 1
        case .pcs: return pcsG ?? 1
        }
    }
    public func grams(forAmount amount: Double) -> Double { amount * gramsPerUnit }
    public var per100: Nutrition { Nutrition(kcal: kcal, protein: p, fat: f, carbs: c) }
    public func nutrition(forAmount amount: Double) -> Nutrition { per100.scaled(grams(forAmount: amount) / 100) }

    /// Продукты, где состав конкретного товара важен для безопасности (готовые/переработанные).
    public var isProcessed: Bool {
        ["canned", "sauce", "bakery", "nuts", "sweet", "grain", "dairy"].contains(cat) || key == "sausage"
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        unit = try c.decode(BaseUnit.self, forKey: .unit)
        cat = try c.decode(String.self, forKey: .cat)
        kcal = try c.decode(Double.self, forKey: .kcal)
        p = try c.decode(Double.self, forKey: .p)
        f = try c.decode(Double.self, forKey: .f)
        self.c = try c.decode(Double.self, forKey: .c)
        dens = try c.decodeIfPresent(Double.self, forKey: .dens)
        pcsG = try c.decodeIfPresent(Double.self, forKey: .pcsG)
        shelf = try c.decodeIfPresent(Int.self, forKey: .shelf) ?? 30
        frozen = try c.decodeIfPresent(Int.self, forKey: .frozen) ?? 0
        store = try c.decodeIfPresent(StorageKind.self, forKey: .store) ?? .pantry
        allergens = try c.decodeIfPresent([String].self, forKey: .allergens) ?? []
        tsp = try c.decodeIfPresent(Double.self, forKey: .tsp)
        tbsp = try c.decodeIfPresent(Double.self, forKey: .tbsp)
        cup = try c.decodeIfPresent(Double.self, forKey: .cup)
        kw = try c.decodeIfPresent([String].self, forKey: .kw) ?? []
        ex = try c.decodeIfPresent([String].self, forKey: .ex) ?? []
    }
    enum K: String, CodingKey { case key, name, unit, cat, kcal, p, f, c, dens, pcsG, shelf, frozen, store, allergens, tsp, tbsp, cup, kw, ex }
}

/// Форматирование чисел и бытовых мер.
public enum Fmt {
    /// Красивое округление количества для текста рецепта: до 20 — до 0.5, до 100 — до 1, до 1000 — до 5, дальше — до 10.
    public static func nice(_ v: Double) -> Double {
        if v <= 0 { return 0 }
        if v < 5 { return (v * 2).rounded() / 2 > 0 ? (v * 2).rounded() / 2 : 0.5 }
        if v < 100 { return v.rounded() }
        if v < 1000 { return (v / 5).rounded() * 5 }
        return (v / 10).rounded() * 10
    }

    public static func number(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        let s = String(format: "%.1f", v)
        return s.replacingOccurrences(of: ".", with: ",")
    }

    /// 1500 г → «1,5 кг», 800 → «800 г».
    public static func amount(_ v: Double, unit: BaseUnit) -> String {
        switch unit {
        case .g: return v >= 1000 ? "\(number((v / 100).rounded() / 10)) кг" : "\(number(v.rounded())) г"
        case .ml: return v >= 1000 ? "\(number((v / 100).rounded() / 10)) л" : "\(number(v.rounded())) мл"
        case .pcs: return "\(number(v.rounded())) шт"
        }
    }

    /// Бытовая мера для массы граммов ингредиента (чайная/столовая ложка, стакан, штука, щепотка).
    public static func household(grams: Double, info: IngredientInfo) -> String? {
        guard grams > 0 else { return nil }
        if info.cat == "spice" && grams < 1.2 { return "щепотка" }
        if let tsp = info.tsp, grams <= (info.tbsp ?? tsp * 3) * 0.7, grams < (info.tbsp ?? 100) {
            let n = grams / tsp
            if n < 0.3 { return "щепотка" }
            return "≈ \(fraction(n)) ч. л."
        }
        if let tbsp = info.tbsp, grams <= tbsp * 6 {
            return "≈ \(fraction(grams / tbsp)) ст. л."
        }
        if let cup = info.cup, grams >= cup * 0.4, grams <= cup * 4 {
            return "≈ \(fraction(grams / cup)) стак."
        }
        if let pcs = info.pcsG, info.unit != .pcs, pcs >= 20 {
            let n = grams / pcs
            if n >= 0.4 && n <= 12 { return "≈ \(fraction(n)) шт" }
        }
        return nil
    }

    /// 0.5 → «½», 1.5 → «1½», 2 → «2».
    public static func fraction(_ n: Double) -> String {
        let whole = Int(n.rounded(.down))
        let rest = n - Double(whole)
        let (fr, carry): (String, Int) = {
            switch rest {
            case ..<0.125: return ("", 0)
            case ..<0.375: return ("¼", 0)
            case ..<0.625: return ("½", 0)
            case ..<0.875: return ("¾", 0)
            default: return ("", 1)
            }
        }()
        let w = whole + carry
        if w == 0 { return fr.isEmpty ? "0" : fr }
        return "\(w)\(fr)"
    }
}
