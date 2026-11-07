import Foundation

/// Намерение пользователя для ассистента. Источник — локальный разбор текста или ответ AI (формат тот же).
public struct AssistantIntent: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case replaceMeal, moreVariety, cheaper, explain, useLeftovers, chat, unknown }
    public var action: Action
    public var day: Int?          // 0-based
    public var slot: Int?         // индекс приёма пищи
    public var include: [String]  // хотим (свободный текст/ключи)
    public var avoid: [String]
    public var recipeID: String?
    public var reply: String?
    public init(action: Action, day: Int? = nil, slot: Int? = nil, include: [String] = [], avoid: [String] = [], recipeID: String? = nil, reply: String? = nil) {
        self.action = action; self.day = day; self.slot = slot; self.include = include; self.avoid = avoid; self.recipeID = recipeID; self.reply = reply
    }
}

public enum AssistantParser {
    static let weekdays: [(names: [String], weekday: Int)] = [
        (["воскресенье", "воскресенью", "вс"], 1), (["понедельник", "понедельнику", "пн"], 2), (["вторник", "вторнику", "вт"], 3),
        (["среда", "среду", "среде", "ср"], 4), (["четверг", "четвергу", "чт"], 5), (["пятница", "пятницу", "пятнице", "пт"], 6), (["суббота", "субботу", "субботе", "сб"], 7),
    ]

    /// Локальный разбор русских команд (работает без интернета).
    public static func parse(_ text: String, plan: MealPlan, library: Library, now: Date = Date()) -> AssistantIntent {
        let t = TextNorm.normalize(text)
        let tokens = t.split(separator: " ").map(String.init)
        func has(_ words: [String]) -> Bool { words.contains { w in tokens.contains { $0.hasPrefix(w) } } }

        if has(["разнообраз", "однообраз", "надоел"]) { return AssistantIntent(action: .moreVariety) }
        if has(["дешевл", "эконом", "подешевл", "дорог"]) && !has(["замен"]) { return AssistantIntent(action: .cheaper) }
        if has(["остатк", "остал"]) && has(["использ", "приготов", "примен", "делать"]) { return AssistantIntent(action: .useLeftovers) }

        if has(["замен", "поменя", "измен", "друг"]) {
            var intent = AssistantIntent(action: .replaceMeal)
            // приём пищи
            let slots = plan.settings.slots
            for (i, s) in slots.enumerated() {
                let n = TextNorm.tokens(s.name)
                if n.contains(where: { w in tokens.contains { $0.hasPrefix(String(w.prefix(max(4, w.count - 2)))) } }) { intent.slot = i; break }
            }
            if intent.slot == nil {
                let typeWords: [(String, MealType)] = [("завтрак", .breakfast), ("обед", .lunch), ("ужин", .dinner), ("перекус", .snack), ("полдник", .snack)]
                for (w, ty) in typeWords where tokens.contains(where: { $0.hasPrefix(w) }) {
                    if let i = slots.firstIndex(where: { $0.type == ty }) { intent.slot = i; break }
                }
            }
            // день
            let cal = Calendar(identifier: .gregorian)
            if let idx = tokens.firstIndex(where: { $0 == "день" || $0 == "дня" }), idx + 1 < tokens.count, let n = Int(tokens[idx + 1]), n >= 1, n <= plan.settings.days { intent.day = n - 1 }
            else if tokens.contains("сегодня") { intent.day = 0 }
            else if tokens.contains("завтра") { intent.day = min(1, plan.settings.days - 1) }
            else {
                for w in weekdays where w.names.contains(where: { tokens.contains($0) }) {
                    for d in 0..<min(plan.settings.days, 7) {
                        let date = cal.date(byAdding: .day, value: d, to: plan.settings.startDate)!
                        if cal.component(.weekday, from: date) == w.weekday { intent.day = d; break }
                    }
                    break
                }
            }
            // что хотим: после « с », « на »
            let resolver = DislikeResolver(library: library)
            var wanted = Set<String>()
            if let ci = tokens.firstIndex(where: { $0 == "с" || $0 == "со" }) {
                wanted.formUnion(resolver.ingredientKeys(for: tokens[(ci + 1)...].joined(separator: " ")))
            }
            if wanted.isEmpty {
                for tok in tokens where tok.count >= 4 && !["замени", "ужин", "обед", "завтрак", "среду", "что", "нибудь"].contains(tok) {
                    wanted.formUnion(resolver.ingredientKeys(for: tok))
                }
            }
            intent.include = wanted.sorted()
            if let bi = tokens.firstIndex(where: { $0 == "без" }) {
                intent.avoid = resolver.ingredientKeys(for: tokens[(bi + 1)...].joined(separator: " ")).sorted()
            }
            return intent
        }
        if has(["объясн", "как приготов", "упрост"]) { return AssistantIntent(action: .explain) }
        return AssistantIntent(action: .unknown)
    }
}

public struct ReplacementSuggestion: Identifiable, Sendable {
    public var id: String { recipe.id }
    public let recipe: Recipe
    public let estimatedCost: Money
    public let kcal: Double
}

public struct AssistantOutcome: Sendable {
    public var message: String
    public var suggestions: [ReplacementSuggestion] = []
    public var updatedInput: PlanInput?
    public var updatedPlan: MealPlan?
}

public enum PlanAnalysis {
    /// Остатки закупленных продуктов (куплено − израсходовано), базовые единицы.
    public static func leftovers(_ plan: MealPlan, library: Library) -> [String: Int] {
        var recipes = library.recipeIndex
        for r in plan.extraRecipes { recipes[r.id] = r }
        let portions = plan.portionFactors.values.reduce(0, +)
        var used: [String: Int] = [:]
        for m in plan.meals {
            guard let r = recipes[m.recipeID] else { continue }
            for ri in r.ingredients {
                guard let info = library.ingredients[ri.key] else { continue }
                let raw = ri.amount * portions * m.scale / Double(max(1, r.servings))
                used[ri.key, default: 0] += info.unit == .pcs ? max(1, Int(raw.rounded())) : max(1, Int(raw.rounded(.up)))
            }
        }
        var bought: [String: Int] = [:]
        for p in plan.purchases { bought[p.ingredientKey, default: 0] += p.packs * p.packBase }
        var out: [String: Int] = [:]
        for (k, b) in bought { let left = b + (plan.usedPantry[k] ?? 0) - (used[k] ?? 0); if left > 0 { out[k] = left } }
        return out
    }
}

/// Исполняет намерения: AI/локальный разбор предлагает, а детерминированный движок проверяет цену, аллергены, технику и бюджет.
public final class AssistantEngine {
    public let planner: MealPlanner
    public init(planner: MealPlanner = MealPlanner()) { self.planner = planner }
    var library: Library { planner.library }

    public func handle(text: String, input: PlanInput, plan: MealPlan) -> AssistantOutcome {
        let intent = AssistantParser.parse(text, plan: plan, library: library)
        return handle(intent: intent, input: input, plan: plan)
    }

    public func handle(intent: AssistantIntent, input: PlanInput, plan: MealPlan) -> AssistantOutcome {
        switch intent.action {
        case .replaceMeal: return replace(intent, input: input, plan: plan)
        case .moreVariety:
            var inp = lockingAll(input: input, plan: plan, except: [])
            inp.locked = [:]
            inp.settings.variety = min(1, input.settings.variety + 0.3)
            inp.settings.budget = input.settings.budget
            guard let p2 = try? planner.plan(inp) else { return AssistantOutcome(message: "Не удалось пересчитать меню с большим разнообразием.") }
            let before = Set(plan.meals.map { $0.recipeID }).count, after = Set(p2.meals.map { $0.recipeID }).count
            if p2.status == .overBudget { return AssistantOutcome(message: "С таким разнообразием меню не укладывается в бюджет. Оставляю прежнее.") }
            return AssistantOutcome(message: "Пересчитал меню: разных блюд стало \(after) вместо \(before). Бюджет не превышен: \(p2.basketTotal) из \(p2.budget).", updatedInput: inp, updatedPlan: p2)
        case .cheaper:
            var inp = input; inp.settings.goal = .economy
            guard let p2 = try? planner.plan(inp) else { return AssistantOutcome(message: "Не удалось пересчитать в экономном режиме.") }
            let saving = plan.basketTotal - p2.basketTotal
            return AssistantOutcome(message: saving.kopecks > 0 ? "В экономном режиме корзина дешевле на \(saving): \(p2.basketTotal)." : "Текущий рацион уже близок к минимальной стоимости: \(plan.basketTotal).", updatedInput: inp, updatedPlan: p2)
        case .useLeftovers:
            let left = PlanAnalysis.leftovers(plan, library: library)
            guard !left.isEmpty else { return AssistantOutcome(message: "Заметных остатков продуктов нет.") }
            let names = left.keys.sorted { (left[$0] ?? 0) > (left[$1] ?? 0) }.prefix(5).compactMap { k in library.ingredients[k].map { "\($0.name) (\(Fmt.amount(Double(left[k]!), unit: $0.unit)))" } }
            let sug = library.recipes.filter { r in r.ingredients.contains { left[$0.key] != nil } && !plan.meals.contains { $0.recipeID == r.id } }
                .sorted { a, b in a.ingredients.filter { left[$0.key] != nil }.count > b.ingredients.filter { left[$0.key] != nil }.count }.prefix(3)
            return AssistantOutcome(message: "Остатки после закупки: " + names.joined(separator: ", ") + ". Можно использовать в блюдах: " + sug.map { $0.name }.joined(separator: "; ") + ".")
        case .explain:
            return AssistantOutcome(message: "Откройте рецепт и нажмите «Готовить» — там пошаговый режим с таймерами и пересчётом порций.")
        case .chat:
            return AssistantOutcome(message: intent.reply ?? "")
        case .unknown:
            return AssistantOutcome(message: "Не понял команду. Попробуйте: «Замени ужин в среду на что-нибудь с курицей», «Хочу питаться разнообразнее», «Сделай подешевле», «Что приготовить из остатков?».")
        }
    }

    /// Закрепляет все блюда плана, кроме перечисленных слотов (чтобы заменить только их).
    public func lockingAll(input: PlanInput, plan: MealPlan, except: Set<SlotKey>) -> PlanInput {
        var inp = input
        inp.locked = [:]
        for m in plan.meals where !except.contains(SlotKey(day: m.day, slot: m.slot)) {
            inp.locked[SlotKey(day: m.day, slot: m.slot)] = LockedChoice(recipeID: m.recipeID, scale: m.scale)
        }
        for r in plan.extraRecipes where !inp.extraRecipes.contains(where: { $0.id == r.id }) { inp.extraRecipes.append(r) }
        return inp
    }

    /// Подбор вариантов замены, отсортированных по оценке стоимости. Все фильтры (аллергены, техника, нежелательные) применяются.
    public func suggestions(input: PlanInput, plan: MealPlan, day: Int, slot: Int, include: [String], avoid: [String], limit: Int = 5) -> [ReplacementSuggestion] {
        guard let ctx = try? MealPlanner.Context(planner: planner, input: input), slot < plan.settings.slots.count else { return [] }
        let type = plan.settings.slots[slot].type
        let cur = plan.meals.first { $0.day == day && $0.slot == slot }?.recipeID
        let stores = Set(input.stores.map { $0.id })
        let includeKeys = Set(include.flatMap { inc -> [String] in library.ingredients[inc] != nil ? [inc] : Array(DislikeResolver(library: library).ingredientKeys(for: inc)) })
        let avoidKeys = Set(avoid.flatMap { a -> [String] in library.ingredients[a] != nil ? [a] : Array(DislikeResolver(library: library).ingredientKeys(for: a)) })
        var out: [ReplacementSuggestion] = []
        for c in ctx.candidates where !c.locked && c.recipe.id != cur && ctx.slotAccepts(type, c) && ctx.recipeAvailable(c, stores: stores) {
            let keys = Set(c.recipe.ingredients.map { $0.key })
            if !includeKeys.isEmpty && keys.isDisjoint(with: includeKeys) { continue }
            if !keys.isDisjoint(with: avoidKeys) { continue }
            var cost = 0.0
            for e in c.demand[0] {
                let k = ctx.ingKeys[e.idx]
                let offers = (ctx.offersByIng[k] ?? []) + (ctx.estimateOffersByIng[k] ?? [])
                cost += Double(e.amt) * (offers.map { $0.unitPrice }.min() ?? 0)
            }
            out.append(ReplacementSuggestion(recipe: c.recipe, estimatedCost: Money(kopecks: Int(cost.rounded())), kcal: c.nutrition.kcal))
        }
        return Array(out.sorted { $0.estimatedCost < $1.estimatedCost }.prefix(limit))
    }

    private func replace(_ intent: AssistantIntent, input: PlanInput, plan: MealPlan) -> AssistantOutcome {
        guard let day = intent.day, let slot = intent.slot else {
            return AssistantOutcome(message: "Уточните, какой приём пищи и в какой день заменить, например: «Замени ужин в среду на что-нибудь с курицей».")
        }
        let sug = suggestions(input: input, plan: plan, day: day, slot: slot, include: intent.include, avoid: intent.avoid)
        guard !sug.isEmpty else {
            return AssistantOutcome(message: "Не нашёл подходящих блюд с учётом ваших аллергенов, техники, нежелательных продуктов и цен в выбранных магазинах.")
        }
        let key = SlotKey(day: day, slot: slot)
        for s in sug {
            var inp = lockingAll(input: input, plan: plan, except: [key])
            inp.locked[key] = LockedChoice(recipeID: s.recipe.id)
            if let p2 = try? planner.plan(inp), p2.status == .ok || plan.status == .overBudget,
               PlanVerifier.verify(p2, library: library, kitchen: input.kitchen).isEmpty {
                let old = plan.meals.first { $0.day == day && $0.slot == slot }?.recipeName ?? "—"
                let delta = p2.basketTotal - plan.basketTotal
                let sign = delta.kopecks >= 0 ? "+" : "−"
                return AssistantOutcome(message: "Заменил «\(old)» на «\(s.recipe.name)». Стоимость закупки изменилась на \(sign)\(Money(kopecks: abs(delta.kopecks))); итого \(p2.basketTotal) из \(p2.budget). Аллергены, техника и бюджет проверены.",
                                        suggestions: sug, updatedInput: inp, updatedPlan: p2)
            }
        }
        return AssistantOutcome(message: "Подходящие блюда нашлись, но замена выводит рацион за бюджет. Могу предложить: " + sug.map { $0.recipe.name }.joined(separator: "; ") + ".", suggestions: sug)
    }
}

/// Проверка рецепта, предложенного AI или пользователем: только известные ингредиенты, разумные количества.
public enum RecipeValidator {
    public struct Draft: Codable, Sendable {
        public var name: String
        public var meals: [String]
        public var servings: Int
        public var prep: Int?
        public var cook: Int?
        public var ingredients: [DraftIngredient]
        public var steps: [String]
        public var heat: [String]?
        public var vessels: [String]?
        public init(name: String, meals: [String], servings: Int, prep: Int? = nil, cook: Int? = nil, ingredients: [DraftIngredient], steps: [String], heat: [String]? = nil, vessels: [String]? = nil) {
            self.name = name; self.meals = meals; self.servings = servings; self.prep = prep; self.cook = cook
            self.ingredients = ingredients; self.steps = steps; self.heat = heat; self.vessels = vessels
        }
    }
    public struct DraftIngredient: Codable, Sendable {
        public var key: String
        public var amount: Double
        public init(key: String, amount: Double) { self.key = key; self.amount = amount }
    }

    public static func validate(_ d: Draft, library: Library, id: String = "user_" + UUID().uuidString.prefix(8)) -> (Recipe?, [String]) {
        var errs: [String] = []
        if d.name.trimmingCharacters(in: .whitespaces).isEmpty { errs.append("Нет названия.") }
        if d.servings < 1 || d.servings > 50 { errs.append("Некорректное число порций.") }
        if d.ingredients.isEmpty { errs.append("Нет ингредиентов.") }
        if d.steps.count < 2 { errs.append("Слишком мало шагов приготовления.") }
        var ings: [RecipeIngredient] = []
        for i in d.ingredients {
            guard let info = library.ingredients[i.key] else { errs.append("Неизвестный ингредиент «\(i.key)» — рецепт можно собрать только из справочника."); continue }
            if i.amount <= 0 { errs.append("Количество «\(info.name)» должно быть положительным."); continue }
            let grams = info.grams(forAmount: i.amount) / Double(max(1, d.servings))
            if grams > 1500 { errs.append("Подозрительно большое количество «\(info.name)» на порцию (\(Int(grams)) г)."); continue }
            ings.append(RecipeIngredient(key: i.key, amount: i.amount))
        }
        var meals = d.meals.compactMap { MealType(rawValue: $0) }
        if meals.isEmpty { meals = [.lunch, .dinner] }
        guard errs.isEmpty else { return (nil, errs) }
        let steps = d.steps.map { RecipeStep(text: $0, timerMin: 0) }
        let method = CookingMethod(id: "stove", label: "Основной способ", heat: d.heat ?? ["hob"], vessels: d.vessels ?? [], tools: [], vesselMl: 0, steps: steps)
        let recipe = Recipe(id: id, name: d.name, meals: meals, servings: d.servings, prep: d.prep ?? 10, cook: d.cook ?? 20, ingredients: ings, methods: [method], note: "Рецепт предложен ассистентом; пищевая ценность рассчитана по справочнику.", isUserCreated: true)
        return (recipe, [])
    }
}
