import Foundation

public enum Sex: String, Codable, Sendable, CaseIterable { case male, female
    public var title: String { self == .male ? "Мужской" : "Женский" } }

public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
    case sedentary, light, moderate, high
    public var factor: Double {
        switch self { case .sedentary: return 1.2; case .light: return 1.375; case .moderate: return 1.55; case .high: return 1.725 }
    }
    public var title: String {
        switch self { case .sedentary: return "Сидячий образ жизни"; case .light: return "Лёгкая активность"; case .moderate: return "Умеренная активность"; case .high: return "Высокая активность" }
    }
}

public enum DietGoal: String, Codable, Sendable, CaseIterable, Identifiable {
    case balanced, economy, healthy, weightLoss, muscleGain, maintain, highProtein, vegetarian
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .balanced: return "Сбалансированное питание"
        case .economy: return "Максимально экономное"
        case .healthy: return "Правильное питание"
        case .weightLoss: return "Снижение калорийности"
        case .muscleGain: return "Набор мышечной массы"
        case .maintain: return "Поддержание веса"
        case .highProtein: return "Высокобелковое"
        case .vegetarian: return "Вегетарианское"
        }
    }
}

public enum Strictness: String, Codable, Sendable { case strict, soft }

/// Профиль питания человека. Аллергены — всегда строгие ограничения.
public struct PersonProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var allergens: Set<Allergen>
    public var dislikes: [String]
    public var dislikeStrictness: Strictness
    public var favorites: [String]
    public var vegetarian: Bool
    public var sex: Sex?
    public var ageYears: Int?
    public var heightCm: Double?
    public var weightKg: Double?
    public var activity: ActivityLevel?

    public init(id: UUID = UUID(), name: String, allergens: Set<Allergen> = [], dislikes: [String] = [], dislikeStrictness: Strictness = .strict, favorites: [String] = [], vegetarian: Bool = false, sex: Sex? = nil, ageYears: Int? = nil, heightCm: Double? = nil, weightKg: Double? = nil, activity: ActivityLevel? = nil) {
        self.id = id; self.name = name; self.allergens = allergens; self.dislikes = dislikes; self.dislikeStrictness = dislikeStrictness
        self.favorites = favorites; self.vegetarian = vegetarian; self.sex = sex; self.ageYears = ageYears; self.heightCm = heightCm; self.weightKg = weightKg; self.activity = activity
    }
}

public enum Energy {
    /// Ориентир суточной калорийности «стандартной порции» рецептов (порция = 1.0).
    public static let referenceKcal = 2000.0

    /// Суточная потребность, ккал (Mifflin–St Jeor × активность; корректировка по цели). Без данных — эталон 2000.
    public static func dailyKcal(_ p: PersonProfile, goal: DietGoal) -> Double {
        var base = referenceKcal
        if let sex = p.sex, let age = p.ageYears, let h = p.heightCm, let w = p.weightKg, age > 0, h > 0, w > 0 {
            let bmr = 10 * w + 6.25 * h - 5 * Double(age) + (sex == .male ? 5 : -161)
            base = bmr * (p.activity ?? .light).factor
        }
        switch goal {
        case .weightLoss: base *= 0.8
        case .muscleGain: base *= 1.12
        default: break
        }
        return min(4000, max(1200, base))
    }

    /// Коэффициент порции человека относительно эталонной порции.
    public static func portionFactor(_ p: PersonProfile, goal: DietGoal) -> Double {
        min(1.8, max(0.4, dailyKcal(p, goal: goal) / referenceKcal))
    }
}

/// Слот приёма пищи.
public struct MealSlotConfig: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var type: MealType
    public var share: Double       // доля суточной калорийности
    public init(id: UUID = UUID(), name: String, type: MealType, share: Double) { self.id = id; self.name = name; self.type = type; self.share = share }

    /// Раскладка по умолчанию для любого количества приёмов (1…N).
    public static func defaults(count: Int) -> [MealSlotConfig] {
        let n = max(1, count)
        var list: [(String, MealType, Double)]
        switch n {
        case 1: list = [("Основной приём", .dinner, 1.0)]
        case 2: list = [("Завтрак", .breakfast, 0.4), ("Ужин", .dinner, 0.6)]
        case 3: list = [("Завтрак", .breakfast, 0.25), ("Обед", .lunch, 0.40), ("Ужин", .dinner, 0.35)]
        case 4: list = [("Завтрак", .breakfast, 0.25), ("Обед", .lunch, 0.35), ("Полдник", .snack, 0.10), ("Ужин", .dinner, 0.30)]
        case 5: list = [("Завтрак", .breakfast, 0.22), ("Второй завтрак", .snack, 0.08), ("Обед", .lunch, 0.35), ("Полдник", .snack, 0.08), ("Ужин", .dinner, 0.27)]
        default:
            list = [("Завтрак", .breakfast, 0.20), ("Второй завтрак", .snack, 0.08), ("Обед", .lunch, 0.30), ("Полдник", .snack, 0.08), ("Ужин", .dinner, 0.26), ("Перекус", .snack, 0.08)]
            if n > 6 { for i in 7...n { list.append(("Перекус \(i - 5)", .snack, 0.05)) } }
        }
        let total = list.reduce(0) { $0 + $1.2 }
        return list.map { MealSlotConfig(name: $0.0, type: $0.1, share: $0.2 / total) }
    }
}

public enum ShoppingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case cheapest, nearest, singleStore, balanced
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cheapest: return "Максимальная экономия"
        case .nearest: return "Ближайшие магазины"
        case .singleStore: return "Один магазин"
        case .balanced: return "Оптимальный баланс"
        }
    }
    /// Стоимость времени пользователя, ₽ за минуту (для штрафа за походы).
    var timeValuePerMin: Double {
        switch self { case .cheapest: return 0.4; case .balanced: return 3; case .nearest: return 25; case .singleStore: return 3 }
    }
}

public enum PricePolicy: String, Codable, Sendable {
    /// Только реальные цены; блюда с ингредиентами без цены исключаются.
    case verifiedOnly
    /// Недостающие цены закрываются ориентирами (всегда помечаются в плане).
    case allowEstimates
}

public struct PlanSettings: Codable, Hashable, Sendable {
    public var days: Int
    public var budget: Money
    public var slots: [MealSlotConfig]
    public var goal: DietGoal
    public var shoppingMode: ShoppingMode
    public var pricePolicy: PricePolicy
    public var unknownComposition: UnknownCompositionPolicy
    public var avoidTraces: Bool
    public var stageDays: Int?            // длина этапа закупок; nil — авто
    public var maxBatches: Int
    public var variety: Double            // 0…1
    public var startDate: Date
    public var maxPriceAgeDays: Int
    public init(days: Int, budget: Money, slots: [MealSlotConfig], goal: DietGoal = .balanced, shoppingMode: ShoppingMode = .balanced, pricePolicy: PricePolicy = .verifiedOnly, unknownComposition: UnknownCompositionPolicy = .allowWithWarning, avoidTraces: Bool = true, stageDays: Int? = nil, maxBatches: Int = 3, variety: Double = 0.6, startDate: Date = Date(), maxPriceAgeDays: Int = 180) {
        self.days = days; self.budget = budget; self.slots = slots; self.goal = goal; self.shoppingMode = shoppingMode; self.pricePolicy = pricePolicy
        self.unknownComposition = unknownComposition; self.avoidTraces = avoidTraces; self.stageDays = stageDays; self.maxBatches = maxBatches
        self.variety = variety; self.startDate = startDate; self.maxPriceAgeDays = maxPriceAgeDays
    }
}

// MARK: - Домашние запасы

public struct PantryItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var ingredientKey: String
    public var amount: Double          // в базовых единицах (г/мл/шт)
    public var expiry: Date?
    public var storage: StorageKind?
    public init(id: UUID = UUID(), ingredientKey: String, amount: Double, expiry: Date? = nil, storage: StorageKind? = nil) {
        self.id = id; self.ingredientKey = ingredientKey; self.amount = amount; self.expiry = expiry; self.storage = storage
    }
}
