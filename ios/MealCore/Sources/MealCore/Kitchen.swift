import Foundation

public struct EquipmentOption: Hashable, Sendable, Identifiable {
    public let key: String
    public let title: String
    public var id: String { key }
}

/// Кухонная техника и посуда пользователя.
public struct Cookware: Codable, Hashable, Sendable, Identifiable {
    public var id: String { kind + ":" + (name ?? "") }
    public var kind: String        // frying_pan, pot, saucepan, ...
    public var name: String?       // пользовательское имя
    public var volumeMl: Int?      // объём (для кастрюль, форм); nil — типовой
    public init(kind: String, name: String? = nil, volumeMl: Int? = nil) { self.kind = kind; self.name = name; self.volumeMl = volumeMl }
}

public enum KitchenCatalog {
    /// Техника (ключи, которые используют рецепты). «hob» — производный: любая плита.
    public static let equipment: [EquipmentOption] = [
        .init(key: "gas_stove", title: "Газовая плита"),
        .init(key: "electric_stove", title: "Электрическая плита"),
        .init(key: "induction_stove", title: "Индукционная плита"),
        .init(key: "oven", title: "Духовка"),
        .init(key: "microwave", title: "Микроволновая печь"),
        .init(key: "multicooker", title: "Мультиварка"),
        .init(key: "air_fryer", title: "Аэрогриль / аэрофритюрница"),
        .init(key: "steamer", title: "Пароварка"),
        .init(key: "blender", title: "Блендер"),
        .init(key: "mixer", title: "Миксер"),
        .init(key: "grill", title: "Электрогриль"),
        .init(key: "toaster", title: "Тостер"),
        .init(key: "freezer", title: "Морозильная камера"),
    ]
    /// Посуда и инструменты.
    public static let cookware: [EquipmentOption] = [
        .init(key: "frying_pan", title: "Сковорода"),
        .init(key: "pot", title: "Кастрюля"),
        .init(key: "saucepan", title: "Ковшик / сотейник"),
        .init(key: "kazan", title: "Казан"),
        .init(key: "wok", title: "Вок"),
        .init(key: "baking_tray", title: "Противень"),
        .init(key: "baking_dish", title: "Форма для запекания"),
        .init(key: "colander", title: "Дуршлаг"),
        .init(key: "bowl", title: "Миска"),
        .init(key: "knife", title: "Нож"),
        .init(key: "cutting_board", title: "Разделочная доска"),
        .init(key: "grater", title: "Тёрка"),
        .init(key: "scale", title: "Кухонные весы"),
    ]
    /// Типовой объём посуды, мл (если пользователь не указал).
    public static func defaultVolumeMl(_ kind: String) -> Int {
        switch kind {
        case "pot": return 3000
        case "saucepan": return 1500
        case "frying_pan": return 2400
        case "kazan": return 4500
        case "wok": return 3000
        case "baking_tray": return 3000
        case "baking_dish": return 2500
        case "bowl": return 2000
        default: return 2000
        }
    }
    /// Какую долю объёма можно реально заполнить едой.
    public static func fillFactor(_ kind: String) -> Double {
        switch kind {
        case "frying_pan", "wok": return 0.6
        case "baking_tray", "baking_dish": return 0.8
        default: return 0.75
        }
    }
    static let toolKinds: Set<String> = ["knife", "cutting_board", "grater", "scale", "colander"]
}

public struct Kitchen: Codable, Hashable, Sendable {
    public var equipment: Set<String>
    public var cookware: [Cookware]
    public var customEquipment: [String]

    public init(equipment: Set<String> = [], cookware: [Cookware] = [], customEquipment: [String] = []) {
        self.equipment = equipment; self.cookware = cookware; self.customEquipment = customEquipment
    }

    /// Разумный набор по умолчанию: плита + базовая посуда (пользователь должен подтвердить).
    public static var starter: Kitchen {
        Kitchen(equipment: ["gas_stove", "freezer"],
                cookware: ["frying_pan", "pot", "saucepan", "bowl", "knife", "cutting_board"].map { Cookware(kind: $0) })
    }

    public var hasHob: Bool { !equipment.isDisjoint(with: ["gas_stove", "electric_stove", "induction_stove"]) }
    public var hasFreezer: Bool { equipment.contains("freezer") }

    public func has(_ key: String) -> Bool {
        if key == "hob" { return hasHob }
        if equipment.contains(key) { return true }
        return cookware.contains { $0.kind == key }
    }
    public func volume(of kind: String) -> Int? {
        let vols = cookware.filter { $0.kind == kind }.map { $0.volumeMl ?? KitchenCatalog.defaultVolumeMl(kind) }
        return vols.max()
    }

    /// Подходит ли способ приготовления: возвращает число «подходов» (1 — всё сразу) или nil, если невозможно.
    public func batches(for method: CookingMethod, servings: Double, maxBatches: Int = 3) -> Int? {
        if !method.heat.isEmpty && !method.heat.contains(where: { has($0) }) { return nil }
        for t in method.tools where !has(t) { return nil }
        if !method.vessels.isEmpty {
            let avail = method.vessels.filter { has($0) }
            if avail.isEmpty { return nil }
            if method.vesselMl > 0 {
                // самая вместительная из подходящих посудин
                var usable = 0.0
                for k in avail {
                    let v = Double(volume(of: k) ?? KitchenCatalog.defaultVolumeMl(k)) * KitchenCatalog.fillFactor(k)
                    usable = max(usable, v)
                }
                guard usable > 0 else { return nil }
                let total = Double(method.vesselMl) * servings
                let b = Int((total / usable).rounded(.up))
                if b > maxBatches { return nil }
                return max(1, b)
            }
        }
        return 1
    }

    /// Первый подходящий способ.
    public func bestMethod(for recipe: Recipe, servings: Double, maxBatches: Int = 3) -> (CookingMethod, Int)? {
        var best: (CookingMethod, Int)?
        for m in recipe.methods {
            if let b = batches(for: m, servings: servings, maxBatches: maxBatches) {
                if best == nil || b < best!.1 { best = (m, b) }
            }
        }
        return best
    }
}
