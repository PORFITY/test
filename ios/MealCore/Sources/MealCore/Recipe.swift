import Foundation

public enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack
    public var title: String {
        switch self { case .breakfast: return "Завтрак"; case .lunch: return "Обед"; case .dinner: return "Ужин"; case .snack: return "Перекус" }
    }
}

public struct RecipeIngredient: Codable, Hashable, Sendable {
    public let key: String
    public let amount: Double   // в базовых единицах ингредиента на базовое число порций
    public init(key: String, amount: Double) { self.key = key; self.amount = amount }
}

public struct RecipeStep: Codable, Hashable, Sendable {
    public let text: String
    public let timerMin: Int   // 0 — без таймера
    public init(text: String, timerMin: Int = 0) { self.text = text; self.timerMin = timerMin }
}

public struct CookingMethod: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let heat: [String]      // нужен хотя бы один из источников нагрева
    public let vessels: [String]   // нужна хотя бы одна из посудин
    public let tools: [String]     // нужны все
    public let vesselMl: Int       // мл готового блюда на порцию (для проверки вместимости)
    public let steps: [RecipeStep]
    public init(id: String, label: String, heat: [String], vessels: [String], tools: [String], vesselMl: Int, steps: [RecipeStep]) {
        self.id = id; self.label = label; self.heat = heat; self.vessels = vessels; self.tools = tools; self.vesselMl = vesselMl; self.steps = steps
    }
}

public struct Recipe: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var meals: [MealType]
    public var servings: Int
    public var prep: Int
    public var cook: Int
    public var tags: [String]
    public var diets: [String]
    public var ingredients: [RecipeIngredient]
    public var methods: [CookingMethod]
    public var note: String?
    public var isUserCreated: Bool

    public init(id: String, name: String, meals: [MealType], servings: Int, prep: Int, cook: Int, tags: [String] = [], diets: [String] = [], ingredients: [RecipeIngredient], methods: [CookingMethod], note: String? = nil, isUserCreated: Bool = false) {
        self.id = id; self.name = name; self.meals = meals; self.servings = servings; self.prep = prep; self.cook = cook
        self.tags = tags; self.diets = diets; self.ingredients = ingredients; self.methods = methods; self.note = note; self.isUserCreated = isUserCreated
    }

    public var isVegetarian: Bool { diets.contains("vegetarian") || diets.contains("vegan") }
    public var totalMinutes: Int { prep + cook }

    // JSON-формат библиотеки: ing: [[key, amount]], steps: [[text, timer]]
    enum K: String, CodingKey { case id, name, meals, servings, prep, cook, tags, diets, ing, methods, note, isUserCreated }
    struct MethodJSON: Codable {
        let id: String; let label: String; let heat: [String]; let vessels: [String]; let tools: [String]; let vesselMl: Int
        let steps: [StepJSON]
    }
    struct StepJSON: Codable {
        let text: String; let timer: Int
        init(text: String, timer: Int) { self.text = text; self.timer = timer }
        init(from d: Decoder) throws {
            var c = try d.unkeyedContainer()
            text = try c.decode(String.self)
            timer = (try? c.decode(Int.self)) ?? 0
        }
        func encode(to e: Encoder) throws {
            var c = e.unkeyedContainer(); try c.encode(text); try c.encode(timer)
        }
    }
    struct IngJSON: Codable {
        let key: String; let amount: Double
        init(key: String, amount: Double) { self.key = key; self.amount = amount }
        init(from d: Decoder) throws {
            var c = try d.unkeyedContainer()
            key = try c.decode(String.self); amount = try c.decode(Double.self)
        }
        func encode(to e: Encoder) throws { var c = e.unkeyedContainer(); try c.encode(key); try c.encode(amount) }
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let mealStrings = try c.decode([String].self, forKey: .meals)
        meals = mealStrings.compactMap { MealType(rawValue: $0) }
        servings = try c.decode(Int.self, forKey: .servings)
        prep = try c.decodeIfPresent(Int.self, forKey: .prep) ?? 0
        cook = try c.decodeIfPresent(Int.self, forKey: .cook) ?? 0
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        diets = try c.decodeIfPresent([String].self, forKey: .diets) ?? []
        ingredients = try c.decode([IngJSON].self, forKey: .ing).map { RecipeIngredient(key: $0.key, amount: $0.amount) }
        methods = try c.decode([MethodJSON].self, forKey: .methods).map { mj in
            CookingMethod(id: mj.id, label: mj.label, heat: mj.heat, vessels: mj.vessels, tools: mj.tools, vesselMl: mj.vesselMl,
                          steps: mj.steps.map { RecipeStep(text: $0.text, timerMin: $0.timer) })
        }
        note = try c.decodeIfPresent(String.self, forKey: .note)
        isUserCreated = try c.decodeIfPresent(Bool.self, forKey: .isUserCreated) ?? false
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(meals.map { $0.rawValue }, forKey: .meals)
        try c.encode(servings, forKey: .servings); try c.encode(prep, forKey: .prep); try c.encode(cook, forKey: .cook)
        try c.encode(tags, forKey: .tags); try c.encode(diets, forKey: .diets)
        try c.encode(ingredients.map { IngJSON(key: $0.key, amount: $0.amount) }, forKey: .ing)
        try c.encode(methods.map { m in MethodJSON(id: m.id, label: m.label, heat: m.heat, vessels: m.vessels, tools: m.tools, vesselMl: m.vesselMl, steps: m.steps.map { StepJSON(text: $0.text, timer: $0.timerMin) }) }, forKey: .methods)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encode(isUserCreated, forKey: .isUserCreated)
    }
}

/// Библиотека: справочник ингредиентов + рецепты (встроены в пакет).
public final class Library: @unchecked Sendable {
    public let ingredients: [String: IngredientInfo]
    public let ingredientList: [IngredientInfo]
    public private(set) var recipes: [Recipe]
    public private(set) var recipeIndex: [String: Recipe]

    public init(ingredients: [IngredientInfo], recipes: [Recipe]) {
        self.ingredientList = ingredients
        self.ingredients = Dictionary(uniqueKeysWithValues: ingredients.map { ($0.key, $0) })
        self.recipes = recipes
        self.recipeIndex = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    struct IngFile: Codable { let items: [IngredientInfo] }
    struct RecipeFile: Codable { let items: [Recipe] }

    public static let shared: Library = {
        do { return try Library.loadBundled() } catch { fatalError("Не удалось загрузить встроенную библиотеку: \(error)") }
    }()

    public static func loadBundled() throws -> Library {
        guard let iu = Bundle.module.url(forResource: "ingredients", withExtension: "json"),
              let ru = Bundle.module.url(forResource: "recipes", withExtension: "json") else {
            throw NSError(domain: "MealCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ресурсы не найдены"])
        }
        let ings = try JSONDecoder().decode(IngFile.self, from: Data(contentsOf: iu)).items
        let recs = try JSONDecoder().decode(RecipeFile.self, from: Data(contentsOf: ru)).items
        return Library(ingredients: ings, recipes: recs)
    }

    public func addRecipe(_ r: Recipe) {
        if let idx = recipes.firstIndex(where: { $0.id == r.id }) { recipes[idx] = r } else { recipes.append(r) }
        recipeIndex[r.id] = r
    }

    public func info(_ key: String) -> IngredientInfo? { ingredients[key] }

    /// Пищевая ценность одной порции рецепта (сырые ингредиенты; масло при жарке учтено полностью).
    public func nutritionPerServing(_ r: Recipe) -> Nutrition {
        var total = Nutrition.zero
        for ri in r.ingredients { if let i = ingredients[ri.key] { total += i.nutrition(forAmount: ri.amount) } }
        return total.scaled(1 / Double(max(1, r.servings)))
    }
}
