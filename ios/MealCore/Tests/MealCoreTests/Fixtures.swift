import Foundation
@testable import MealCore

/// ТЕСТОВЫЕ данные (не реальные цены): синтетический каталог магазина на основе ориентировочной таблицы.
enum Fixtures {
    static let lib = Library.shared

    static func store(_ id: String, name: String, km: Double) -> StoreInfo {
        StoreInfo(id: id, name: name, address: "Тестовый адрес", lat: 55.75, lon: 37.62, distanceM: km * 1000, shopType: "supermarket", catalog: .imported, source: "test")
    }

    static func products(store: String, factor: Double = 1.0, drop: Set<String> = [], textFor: [String: String] = [:]) -> [CatalogProduct] {
        var out: [CatalogProduct] = []
        for (key, packs) in ReferencePrices.entries() where !drop.contains(key) {
            guard let info = lib.ingredients[key] else { continue }
            for (i, p) in packs.enumerated() {
                let size = Fmt.amount(p.size, unit: info.unit)
                let name = "\(info.name) \(size)"
                out.append(CatalogProduct(id: "\(store):\(key):\(i)", storeID: store, name: name, quantityText: size, price: Money.rub(p.price * factor),
                                          ingredientsText: textFor[key], priceDate: Date(), quality: .imported, source: "test-fixture"))
            }
        }
        return out
    }

    static func offers(_ products: [CatalogProduct], allergens: Set<Allergen> = []) -> [Offer] {
        OfferBuilder(library: lib, allergens: allergens).build(from: products).offers
    }

    static func settings(days: Int = 7, budget: Int = 7000, meals: Int = 3, goal: DietGoal = .balanced, mode: ShoppingMode = .balanced) -> PlanSettings {
        PlanSettings(days: days, budget: .rub(budget), slots: MealSlotConfig.defaults(count: meals), goal: goal, shoppingMode: mode, startDate: Date(timeIntervalSince1970: 1_800_000_000))
    }

    static var fullKitchen: Kitchen {
        Kitchen(equipment: ["gas_stove", "oven", "microwave", "freezer", "blender"],
                cookware: ["frying_pan", "pot", "saucepan", "kazan", "baking_tray", "baking_dish", "bowl", "knife", "cutting_board", "grater", "colander"].map { Cookware(kind: $0) })
    }
    /// Кухня из примера ТЗ: плита, микроволновка; сковорода и кастрюля (+ базовые инструменты).
    static var specKitchen: Kitchen {
        Kitchen(equipment: ["gas_stove", "microwave", "freezer"], cookware: ["frying_pan", "pot", "bowl", "knife", "cutting_board"].map { Cookware(kind: $0) })
    }
}

