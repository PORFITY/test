import Foundation

public struct SlotKey: Hashable, Codable, Sendable { public let day: Int; public let slot: Int
    public init(day: Int, slot: Int) { self.day = day; self.slot = slot } }

public struct LockedChoice: Codable, Hashable, Sendable {
    public var recipeID: String
    public var scale: Double
    public init(recipeID: String, scale: Double = 1) { self.recipeID = recipeID; self.scale = scale }
}

public struct PlannedMeal: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "d\(day)-s\(slot)" }
    public var day: Int
    public var slot: Int
    public var slotName: String
    public var type: MealType
    public var recipeID: String
    public var recipeName: String
    public var scale: Double             // масштаб порции (1.0, 1.25 …)
    public var portions: Double          // сумма коэффициентов порций всех людей × scale
    public var methodID: String
    public var batches: Int
    public var cost: Money               // стоимость блюда по использованным граммам
    public var nutritionPerPortion: Nutrition   // на 1.0 порцию с учётом scale
    public var locked: Bool
    public var done: Bool
}

public struct PurchaseLine: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(purchaseDay)|\(offerID)" }
    public var ingredientKey: String
    public var ingredientName: String
    public var offerID: String
    public var storeID: String
    public var productName: String
    public var brand: String?
    public var imageURL: String?
    public var url: String?
    public var packs: Int
    public var packBase: Int
    public var unit: BaseUnit
    public var unitPrice: Money           // цена упаковки
    public var total: Money
    public var purchaseDay: Int
    public var quality: PriceQuality
    public var priceDate: Date?
    public var promoText: String?
    public var warning: String?
    public var storageAdvice: String?
    public var purchased: Bool
    public var totalBase: Int { packs * packBase }
}

public struct DayStat: Codable, Hashable, Sendable {
    public var day: Int
    public var kcalReference: Double     // ккал на 1.0 порцию в день
    public var protein: Double
    public var fat: Double
    public var carbs: Double
    public var cost: Money
}

public struct PlanWarning: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case estimatePrices, stalePrices, unconfirmedComposition, lowCalories, overBudget, batches, missingPrices, freezing, other }
    public var id: String { kind.rawValue + message }
    public var kind: Kind
    public var message: String
}

public struct SavingsTip: Codable, Hashable, Sendable, Identifiable {
    public var id: String { text }
    public var text: String
    public var estimatedSaving: Money?
}

public struct StoreVisit: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(day)|\(storeID)" }
    public var day: Int
    public var storeID: String
    public var total: Money
    public var lines: Int
}

public enum PlanStatus: String, Codable, Sendable { case ok, overBudget }

public struct MealPlan: Codable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var settings: PlanSettings
    public var people: [PersonProfile]
    public var meals: [PlannedMeal]
    public var purchases: [PurchaseLine]
    public var stores: [StoreInfo]
    public var visits: [StoreVisit]
    public var basketTotal: Money
    public var dishCostTotal: Money
    public var leftoverValue: Money
    public var budget: Money
    public var status: PlanStatus
    public var dayStats: [DayStat]
    public var personKcal: [String: Double]       // id человека → ккал/день (цель)
    public var portionFactors: [String: Double]
    public var priceMix: [String: Int]            // PriceQuality.rawValue → копейки
    public var warnings: [PlanWarning]
    public var tips: [SavingsTip]
    public var usedPantry: [String: Int]          // ingredientKey → базовые единицы
    public var extraRecipes: [Recipe]
    public var minimumAchievable: Money?

    public var remaining: Money { budget - basketTotal }
    public var usedPercent: Double { budget.kopecks > 0 ? Double(basketTotal.kopecks) / Double(budget.kopecks) * 100 : 0 }
    public var perDay: Money { basketTotal.divided(by: max(1, settings.days)) }
    public var perPersonPerDay: Money { basketTotal.divided(by: max(1, settings.days * max(1, people.count))) }
    public var estimateShare: Double {
        let total = priceMix.values.reduce(0, +)
        guard total > 0 else { return 0 }
        return Double(priceMix[PriceQuality.estimate.rawValue] ?? 0) / Double(total)
    }
}

public enum PlanError: Error, LocalizedError, Sendable {
    case invalidInput(String)
    case noPriceData
    case noRecipes(MealType, String)
    case infeasible(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let s): return s
        case .noPriceData: return "Нет достоверных цен ни по одному выбранному магазину. Загрузите каталог или введите цены вручную — либо разрешите расчёт по ориентировочным ценам (он будет явно помечен)."
        case .noRecipes(let t, let why): return "Для приёма пищи «\(t.title)» не осталось подходящих рецептов. \(why)"
        case .infeasible(let s): return s
        }
    }
}
