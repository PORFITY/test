import Foundation

public struct RenderedIngredient: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let amountBase: Double      // в базовых единицах (г/мл/шт)
    public let unit: BaseUnit
    public let grams: Double
    public let display: String         // «150 г», «300 мл», «2 шт»
    public let secondary: String?      // «≈ 110 г · ≈ 2 ч. л.»
}

public struct RenderedStep: Identifiable, Hashable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let text: String
    public let timerMin: Int
}

public struct RenderedRecipe: Sendable {
    public let recipe: Recipe
    public let method: CookingMethod
    public let servings: Double
    public let ingredients: [RenderedIngredient]
    public let steps: [RenderedStep]
    public let nutritionPerServing: Nutrition
    public let totalGrams: Double
}

/// Масштабирование рецептов и подстановка количеств в текст шагов.
public enum RecipeRenderer {
    public static func factor(_ recipe: Recipe, servings: Double) -> Double { servings / Double(max(1, recipe.servings)) }

    public static func scaledAmount(_ ri: RecipeIngredient, info: IngredientInfo, factor: Double) -> Double {
        let raw = ri.amount * factor
        switch info.unit {
        case .pcs: return max(1, raw.rounded())
        default: return raw < 20 ? (raw * 2).rounded() / 2 > 0 ? (raw * 2).rounded() / 2 : 0.5 : raw.rounded()
        }
    }

    public static func renderIngredient(_ ri: RecipeIngredient, info: IngredientInfo, factor: Double) -> RenderedIngredient {
        let amt = scaledAmount(ri, info: info, factor: factor)
        let grams = info.grams(forAmount: amt)
        let display: String
        var secondary: [String] = []
        switch info.unit {
        case .g: display = Fmt.amount(amt, unit: .g)
        case .ml: display = Fmt.amount(amt, unit: .ml); secondary.append("≈ \(Fmt.number(grams.rounded())) г")
        case .pcs: display = "\(Fmt.number(amt)) шт"; secondary.append("≈ \(Fmt.number(grams.rounded())) г")
        }
        if let h = Fmt.household(grams: grams, info: info) { secondary.append(h) }
        return RenderedIngredient(key: info.key, name: info.name, amountBase: amt, unit: info.unit, grams: grams, display: display, secondary: secondary.isEmpty ? nil : secondary.joined(separator: " · "))
    }

    /// {{i:key}} → количество ингредиента, {{600|мл}} → масштабируемое число.
    public static func renderText(_ text: String, recipe: Recipe, servings: Double, library: Library) -> String {
        let f = factor(recipe, servings: servings)
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: "}}") else { out += rest[open.lowerBound...]; rest = ""; break }
            let token = String(afterOpen[..<close.lowerBound])
            out += resolve(token, recipe: recipe, factor: f, library: library)
            rest = afterOpen[close.upperBound...]
        }
        out += rest
        return out
    }

    private static func resolve(_ token: String, recipe: Recipe, factor: Double, library: Library) -> String {
        if token.hasPrefix("i:") {
            let key = String(token.dropFirst(2))
            guard let ri = recipe.ingredients.first(where: { $0.key == key }), let info = library.ingredients[key] else { return "[\(key)]" }
            return renderIngredient(ri, info: info, factor: factor).display
        }
        let parts = token.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2, let v = Double(parts[0].replacingOccurrences(of: ",", with: ".")) {
            let scaled = Fmt.nice(v * factor)
            switch parts[1] {
            case "мл": return Fmt.amount(scaled, unit: .ml)
            case "г": return Fmt.amount(scaled, unit: .g)
            default: return "\(Fmt.number(scaled)) \(parts[1])"
            }
        }
        return token
    }

    public static func render(recipe: Recipe, method: CookingMethod? = nil, servings: Double, library: Library) -> RenderedRecipe {
        let m = method ?? recipe.methods[0]
        let f = factor(recipe, servings: servings)
        var ings: [RenderedIngredient] = []
        var total = 0.0
        for ri in recipe.ingredients {
            guard let info = library.ingredients[ri.key] else { continue }
            let r = renderIngredient(ri, info: info, factor: f)
            ings.append(r); total += r.grams
        }
        let steps = m.steps.enumerated().map { RenderedStep(index: $0.offset, text: renderText($0.element.text, recipe: recipe, servings: servings, library: library), timerMin: $0.element.timerMin) }
        return RenderedRecipe(recipe: recipe, method: m, servings: servings, ingredients: ings, steps: steps, nutritionPerServing: library.nutritionPerServing(recipe), totalGrams: total)
    }
}

/// Сохраняемый прогресс приготовления.
public struct CookingProgress: Codable, Hashable, Sendable {
    public var recipeID: String
    public var methodID: String
    public var servings: Double
    public var currentStep: Int
    public var doneSteps: Set<Int>
    public var timers: [Int: Date]      // шаг → момент окончания таймера
    public var updatedAt: Date

    public init(recipeID: String, methodID: String, servings: Double) {
        self.recipeID = recipeID; self.methodID = methodID; self.servings = servings
        currentStep = 0; doneSteps = []; timers = [:]; updatedAt = Date()
    }
    public mutating func next(total: Int) { doneSteps.insert(currentStep); currentStep = min(total - 1, currentStep + 1); updatedAt = Date() }
    public mutating func previous() { currentStep = max(0, currentStep - 1); updatedAt = Date() }
    public mutating func toggle(_ i: Int) { if doneSteps.contains(i) { doneSteps.remove(i) } else { doneSteps.insert(i) }; updatedAt = Date() }
    public mutating func startTimer(step: Int, minutes: Int, now: Date = Date()) { timers[step] = now.addingTimeInterval(Double(minutes) * 60); updatedAt = now }
    public func remaining(step: Int, now: Date = Date()) -> TimeInterval? { timers[step].map { max(0, $0.timeIntervalSince(now)) } }
    public func isFinished(total: Int) -> Bool { doneSteps.count >= total }
}
