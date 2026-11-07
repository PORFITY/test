import Foundation

public struct PlanInput: Sendable {
    public var settings: PlanSettings
    public var people: [PersonProfile]
    public var stores: [StoreInfo]
    public var offers: [Offer]
    public var pantry: [PantryItem]
    public var kitchen: Kitchen
    public var extraRecipes: [Recipe]
    public var locked: [SlotKey: LockedChoice]
    public var excludedRecipeIDs: Set<String>
    public var seed: UInt64
    public init(settings: PlanSettings, people: [PersonProfile], stores: [StoreInfo], offers: [Offer], pantry: [PantryItem] = [], kitchen: Kitchen, extraRecipes: [Recipe] = [], locked: [SlotKey: LockedChoice] = [:], excludedRecipeIDs: Set<String> = [], seed: UInt64 = 7) {
        self.settings = settings; self.people = people; self.stores = stores; self.offers = offers; self.pantry = pantry; self.kitchen = kitchen
        self.extraRecipes = extraRecipes; self.locked = locked; self.excludedRecipeIDs = excludedRecipeIDs; self.seed = seed
    }
}

struct SplitMix64 {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
}

/// Кандидат-рецепт, подготовленный для оптимизации.
struct Candidate {
    let recipe: Recipe
    let method: CookingMethod
    let batchesByScale: [Int]               // для каждого масштаба; 0 — недопустим
    let demand: [[(idx: Int, amt: Int)]]    // [scale] → спарс-вектор спроса группы
    let nutrition: Nutrition                // на 1.0 порцию
    let pref: Double                        // очки предпочтений (отрицательное — хорошо)
    let mainTags: Set<String>
    let locked: Bool
}

public final class MealPlanner {
    public let library: Library
    public init(library: Library = .shared) { self.library = library }

    static let scales: [Double] = [1.0, 1.25, 1.5, 2.0]
    static let mainTagSet: Set<String> = ["poultry", "beef", "fish", "seafood", "pasta", "rice", "potato", "buckwheat", "legumes", "eggs", "sausage", "liver", "mushroom", "cabbage"]
    static let unavailablePenalty = 5_000_000.0

    // MARK: - Публичный вход

    public func plan(_ input: PlanInput) throws -> MealPlan {
        let ctx = try Context(planner: self, input: input)
        return try ctx.run()
    }

    // MARK: - Контекст расчёта

    final class Context {
        let lib: Library
        let input: PlanInput
        let settings: PlanSettings
        let slots: [MealSlotConfig]
        let M: Int
        let N: Int                       // всего слотов
        let portions: Double             // Σ коэффициентов порций
        let factors: [Double]
        let allergens: Set<Allergen>
        let hardDislikeKeys: Set<String>
        let softDislikeKeys: Set<String>
        let hardDislikeTexts: [String]
        let favKeys: Set<String>
        let vegetarianOnly: Bool
        let allRecipes: [Recipe]
        let ingKeys: [String]
        let ingIndex: [String: Int]
        let pantryUsable: [Int]
        let pantryLots: [String: [PantryLot]]
        let offersByIng: [String: [Offer]]
        let estimateOffersByIng: [String: [Offer]]
        let storeByID: [String: StoreInfo]
        var coverCache: [String: PackCover?] = [:]
        var candidates: [Candidate] = []       // статические кандидаты
        var filterReport: [String: Int] = [:]
        let rng0: UInt64
        let startDate: Date

        struct PantryLot { var amount: Int; var expiryDay: Int }

        init(planner: MealPlanner, input: PlanInput) throws {
            self.lib = planner.library
            self.input = input
            let settings = input.settings
            self.settings = settings
            let lib = planner.library
            guard settings.days >= 1 else { throw PlanError.invalidInput("Количество дней должно быть не меньше 1.") }
            guard !input.people.isEmpty else { throw PlanError.invalidInput("Укажите хотя бы одного человека.") }
            guard settings.budget.kopecks > 0 else { throw PlanError.invalidInput("Бюджет должен быть положительным.") }
            guard !settings.slots.isEmpty else { throw PlanError.invalidInput("Укажите хотя бы один приём пищи в день.") }
            slots = settings.slots
            M = slots.count
            N = settings.days * M
            let fs = input.people.map { Energy.portionFactor($0, goal: settings.goal) }
            factors = fs
            portions = fs.reduce(0, +)
            allergens = Set(input.people.flatMap { $0.allergens })
            rng0 = input.seed
            startDate = settings.startDate

            // нежелательные / любимые
            let resolver = DislikeResolver(library: lib)
            var hard = Set<String>(), soft = Set<String>(), fav = Set<String>()
            var hardTexts: [String] = []
            for p in input.people {
                for d in p.dislikes {
                    let keys = resolver.ingredientKeys(for: d)
                    if p.dislikeStrictness == .strict { hard.formUnion(keys); hardTexts.append(d) } else { soft.formUnion(keys) }
                }
                for f in p.favorites { fav.formUnion(resolver.ingredientKeys(for: f)) }
            }
            hardDislikeKeys = hard; softDislikeKeys = soft.subtracting(hard); hardDislikeTexts = hardTexts; favKeys = fav
            vegetarianOnly = settings.goal == .vegetarian || input.people.contains { $0.vegetarian }

            var recs = lib.recipes
            for r in input.extraRecipes { if let i = recs.firstIndex(where: { $0.id == r.id }) { recs[i] = r } else { recs.append(r) } }
            allRecipes = recs

            // индексы ингредиентов
            var keys = Set<String>()
            for r in recs { for i in r.ingredients { keys.insert(i.key) } }
            ingKeys = keys.sorted()
            var idx: [String: Int] = [:]
            for (i, k) in ingKeys.enumerated() { idx[k] = i }
            ingIndex = idx

            // кладовая
            var usable = [Int](repeating: 0, count: ingKeys.count)
            var lots: [String: [PantryLot]] = [:]
            for item in input.pantry where item.amount > 0 {
                guard let info = lib.ingredients[item.ingredientKey] else { continue }
                var expiryDay = Int.max / 4
                if let e = item.expiry { expiryDay = Int((e.timeIntervalSince(settings.startDate) / 86400).rounded(.down)) }
                else if info.store == .fridge || info.shelf < 60 { expiryDay = max(0, info.shelf - 1) }
                if expiryDay < 0 { continue }
                let amt = Int(item.amount.rounded(.down))
                if amt <= 0 { continue }
                lots[item.ingredientKey, default: []].append(PantryLot(amount: amt, expiryDay: expiryDay))
                if let k = idx[item.ingredientKey] { usable[k] += amt }
            }
            pantryUsable = usable
            pantryLots = lots

            // предложения
            let stIDs = Set(input.stores.map { $0.id })
            var byIng: [String: [Offer]] = [:]
            var est: [String: [Offer]] = [:]
            for o in input.offers {
                if o.quality == .estimate { est[o.ingredientKey, default: []].append(o) }
                else if stIDs.contains(o.storeID) { byIng[o.ingredientKey, default: []].append(o) }
            }
            if settings.pricePolicy == .allowEstimates {
                // ориентиры из входных данных или встроенные
                if est.isEmpty {
                    for o in ReferencePrices.offers(library: lib, allergens: Set(input.people.flatMap { $0.allergens })) { est[o.ingredientKey, default: []].append(o) }
                }
            } else { est = [:] }
            offersByIng = byIng
            estimateOffersByIng = est
            storeByID = Dictionary(input.stores.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            try buildCandidates()
        }

        // MARK: Кандидаты

        func isEligibleStatic(_ r: Recipe) -> String? {
            if input.excludedRecipeIDs.contains(r.id) { return "excluded" }
            // аллергены (строго, по ингредиентам справочника)
            for ri in r.ingredients {
                guard let info = lib.ingredients[ri.key] else { return "unknown_ingredient" }
                if !AllergenChecker.ingredientContains(info, allergens).isEmpty { return "allergen" }
            }
            if vegetarianOnly && !r.isVegetarian { return "diet" }
            for ri in r.ingredients where hardDislikeKeys.contains(ri.key) { return "dislike" }
            if !hardDislikeTexts.isEmpty {
                let res = DislikeResolver(library: lib)
                for t in hardDislikeTexts where res.matchesRecipeName(r, text: t) { return "dislike" }
            }
            return nil
        }

        func buildCandidates() throws {
            var cands: [Candidate] = []
            var report: [String: Int] = ["total": allRecipes.count]
            let lockedIDs = Set(input.locked.values.map { $0.recipeID })
            for r in allRecipes {
                var bypassed = false
                let isLockedRecipe = lockedIDs.contains(r.id)
                if let why = isEligibleStatic(r) {
                    // закреплённый пользователем рецепт обходит только предпочтения, но не аллергены
                    if !(isLockedRecipe && (why == "dislike" || why == "diet" || why == "excluded")) {
                        report[why, default: 0] += 1; continue
                    }
                    bypassed = true
                }
                // оборудование/посуда
                var batchesByScale: [Int] = []
                var method: CookingMethod?
                var ok = false
                for s in MealPlanner.scales {
                    if let (m, b) = input.kitchen.bestMethod(for: r, servings: portions * s, maxBatches: settings.maxBatches) {
                        batchesByScale.append(b)
                        if method == nil && s == 1.0 { method = m }
                        ok = true
                    } else { batchesByScale.append(0) }
                }
                guard ok, batchesByScale[0] > 0, let m0 = method else { report["kitchen", default: 0] += 1; continue }
                var demand: [[(idx: Int, amt: Int)]] = []
                for s in MealPlanner.scales {
                    var v: [(idx: Int, amt: Int)] = []
                    let factor = portions * s / Double(max(1, r.servings))
                    for ri in r.ingredients {
                        guard let k = ingIndex[ri.key], let info = lib.ingredients[ri.key] else { continue }
                        let raw = ri.amount * factor
                        let amt = info.unit == .pcs ? max(1, Int(raw.rounded())) : max(1, Int(raw.rounded(.up)))
                        v.append((k, amt))
                    }
                    demand.append(v)
                }
                // предпочтения
                var pref = 0.0
                var favHits = 0
                for ri in r.ingredients {
                    guard let info = lib.ingredients[ri.key] else { continue }
                    let gramsPerServing = info.grams(forAmount: ri.amount) / Double(max(1, r.servings))
                    if favKeys.contains(ri.key) && favHits < 2 { pref -= 700 * min(1, gramsPerServing / 60); favHits += 1 }
                    if softDislikeKeys.contains(ri.key) { pref += 1500 }
                }
                // цели
                let hasTag = { (t: String) in r.tags.contains(t) }
                switch settings.goal {
                case .healthy: if hasTag("fried") { pref += 300 }; if hasTag("sausage") { pref += 700 }; if hasTag("vegetable") || hasTag("legumes") || hasTag("fish") || hasTag("salad") { pref -= 250 }
                case .weightLoss: if hasTag("fried") { pref += 250 }; if hasTag("sausage") { pref += 400 }
                default: break
                }
                let nut = lib.nutritionPerServing(r)
                cands.append(Candidate(recipe: r, method: m0, batchesByScale: batchesByScale, demand: demand, nutrition: nut, pref: pref,
                                       mainTags: Set(r.tags).intersection(MealPlanner.mainTagSet), locked: bypassed))
                report["eligible", default: 0] += 1
            }
            candidates = cands
            filterReport = report
        }

        func slotAccepts(_ slotType: MealType, _ c: Candidate) -> Bool {
            let meals = c.recipe.meals
            if meals.contains(slotType) { return true }
            let isSoup = c.recipe.tags.contains("soup")
            switch slotType {
            case .dinner: return meals.contains(.lunch) && !isSoup
            case .lunch: return meals.contains(.dinner)
            default: return false
            }
        }

        // MARK: Покрытие упаковками

        func cover(_ key: String, stores: Set<String>) -> PackCover? {
            var real = (offersByIng[key] ?? []).filter { stores.contains($0.storeID) }
            if real.isEmpty { real = estimateOffersByIng[key] ?? [] }
            if real.isEmpty { return nil }
            let sig = key + "|" + real.map { $0.id }.sorted().joined(separator: ",")
            if let c = coverCache[sig] { return c }
            let pc = PackCover(offers: real)
            coverCache[sig] = pc
            return pc
        }

        func hasAnyOffer(_ key: String, stores: Set<String>) -> Bool {
            if (offersByIng[key] ?? []).contains(where: { stores.contains($0.storeID) }) { return true }
            return !(estimateOffersByIng[key] ?? []).isEmpty
        }

        // MARK: Запуск

        func run() throws -> MealPlan {
            let allStores = Set(input.stores.map { $0.id })
            // 1. Данные по ценам
            let anyReal = !offersByIng.isEmpty
            if !anyReal && estimateOffersByIng.isEmpty { throw PlanError.noPriceData }

            // 2. Проверка доступности рецептов по типам слотов
            let neededTypes = Set(slots.map { $0.type })
            for t in neededTypes {
                let avail = candidates.filter { slotAccepts(t, $0) && recipeAvailable($0, stores: allStores) }
                if avail.isEmpty {
                    throw PlanError.noRecipes(t, diagnosis(for: t, anyReal: anyReal))
                }
            }

            // 3. Выбор набора магазинов
            let chosen = chooseStores(allStores: allStores)

            // 4. λ-поиск: максимальное качество при бюджете
            var best: SolveResult?
            let budget = settings.budget.kopecks
            let lamMin = 0.3, lamMax = 60.0
            func solveAt(_ lam: Double) -> SolveResult { solve(stores: chosen, lambda: lam) }
            if settings.goal == .economy {
                best = solveAt(lamMax)
            } else {
                let first = solveAt(lamMin)
                if first.finalCost <= budget { best = first }
                else {
                    let top = solveAt(lamMax)
                    if top.finalCost > budget { best = top }   // даже минимум не укладывается
                    else {
                        var lo = lamMin, hi = lamMax
                        var good = top
                        for _ in 0..<9 {
                            let mid = (lo * hi).squareRoot()
                            let r = solveAt(mid)
                            if r.finalCost <= budget { good = r; hi = mid } else { lo = mid }
                        }
                        best = good
                    }
                }
            }
            guard let result = best else { throw PlanError.infeasible("Не удалось построить рацион.") }
            return assemble(result, stores: chosen)
        }

        func recipeAvailable(_ c: Candidate, stores: Set<String>) -> Bool {
            for (k, amt) in c.demand[0].map({ ($0.idx, $0.amt) }) {
                if pantryUsable[k] >= amt { continue }
                if !hasAnyOffer(ingKeys[k], stores: stores) { return false }
            }
            return true
        }

        func diagnosis(for t: MealType, anyReal: Bool) -> String {
            var parts: [String] = []
            let r = filterReport
            if let a = r["allergen"], a > 0 { parts.append("исключено по аллергенам: \(a)") }
            if let a = r["dislike"], a > 0 { parts.append("исключено по нежелательным продуктам: \(a)") }
            if let a = r["diet"], a > 0 { parts.append("не подходят по типу питания: \(a)") }
            if let a = r["kitchen"], a > 0 { parts.append("нельзя приготовить на вашей технике и посуде: \(a)") }
            let priced = candidates.filter { slotAccepts(t, $0) }.count
            if priced > 0 { parts.append("не хватает цен на ингредиенты у выбранных магазинов") }
            return "Из \(r["total"] ?? 0) рецептов " + (parts.isEmpty ? "нет подходящих." : parts.joined(separator: "; ") + ".") + " Ослабьте ограничения, добавьте технику, выберите другие магазины или введите цены вручную."
        }

        // MARK: Выбор магазинов

        func visitPenalty(_ s: StoreInfo, trips: Int) -> Double {
            if s.id == "user" || s.id == ReferencePrices.storeID { return 0 }
            let km = s.distanceM / 1000
            let minutes = 10 + 2 * km * 3
            return minutes * settings.shoppingMode.timeValuePerMin * 100 * Double(trips)
        }

        func tripsEstimate() -> Int {
            if let st = settings.stageDays, st > 0 { return max(1, (settings.days + st - 1) / st) }
            return settings.days > 14 ? (settings.days + 6) / 7 : 1
        }

        /// Эталонный спрос (кол-во по ингредиентам) для оценки наборов магазинов.
        func referenceDemand(stores: Set<String>) -> [Int] {
            let r = solve(stores: stores, lambda: 6, restarts: 1)
            return r.demand
        }

        func proxyCost(_ stores: Set<String>, demand: [Int]) -> Double {
            var total = 0.0
            for (k, d) in demand.enumerated() where d > 0 {
                let need = max(0, d - pantryUsable[k])
                if need == 0 { continue }
                if let c = cover(ingKeys[k], stores: stores) {
                    let v = c.cost(need: need)
                    total += v >= PackCover.infinity ? MealPlanner.unavailablePenalty : Double(v)
                } else { total += 150_000 + Double(need) * 20 }   // непокрытый ингредиент — штраф «заменить рецепт»
            }
            return total
        }

        func chooseStores(allStores: Set<String>) -> Set<String> {
            // магазины с хотя бы одним предложением
            let withOffers = Set(offersByIng.values.flatMap { $0 }.map { $0.storeID })
            var cands = input.stores.filter { withOffers.contains($0.id) }
            if cands.isEmpty { return allStores }   // только ориентиры
            // ограничение числа кандидатов для скорости: по покрытию и расстоянию
            if cands.count > 12 {
                let coverage = Dictionary(grouping: offersByIng.values.flatMap { $0 }, by: { $0.storeID }).mapValues { Set($0.map { $0.ingredientKey }).count }
                cands.sort { (coverage[$0.id] ?? 0, -$0.distanceM) > (coverage[$1.id] ?? 0, -$1.distanceM) }
                cands = Array(cands.prefix(12))
            }
            let ids = Set(cands.map { $0.id })
            if cands.count == 1 { return ids }
            let trips = tripsEstimate()
            let refDemand = referenceDemand(stores: ids)
            func J(_ s: Set<String>) -> Double {
                proxyCost(s, demand: refDemand) + s.reduce(0.0) { $0 + visitPenalty(storeByID[$1]!, trips: trips) }
            }
            if settings.shoppingMode == .singleStore {
                let sorted = cands.sorted { J([$0.id]) < J([$1.id]) }
                return [sorted[0].id]
            }
            // жадный прямой выбор + обратная чистка
            var current: Set<String> = [cands.min { J([$0.id]) < J([$1.id]) }!.id]
            var cur = J(current)
            while true {
                var bestAdd: (String, Double)?
                for s in cands where !current.contains(s.id) {
                    let v = J(current.union([s.id]))
                    if v < cur - 1 && (bestAdd == nil || v < bestAdd!.1) { bestAdd = (s.id, v) }
                }
                guard let add = bestAdd else { break }
                current.insert(add.0); cur = add.1
            }
            var improved = true
            while improved && current.count > 1 {
                improved = false
                for s in current {
                    let v = J(current.subtracting([s]))
                    if v <= cur { current.remove(s); cur = v; improved = true; break }
                }
            }
            return current
        }

        // MARK: Решатель меню

        struct SolveResult {
            var choiceC: [Int]
            var choiceS: [Int]
            var demand: [Int]
            var schedule: Schedule
            var finalCost: Int
            var stores: Set<String>
            var pool: [Candidate]
            var lambda: Double
        }

        func solve(stores: Set<String>, lambda: Double, restarts: Int = 3) -> SolveResult {
            let solver = MenuSolver(ctx: self, stores: stores, lambda: lambda)
            var bestState: MenuSolver.State?
            var bestScore = Double.infinity
            for r in 0..<restarts {
                var st = solver.initialState(seed: rng0 &+ UInt64(r) &* 7919)
                solver.improve(&st, seed: rng0 &+ UInt64(r) &* 104729)
                let sc = solver.fullScore(st)
                if sc < bestScore { bestScore = sc; bestState = st }
            }
            let st = bestState!
            let schedule = ShoppingScheduler(ctx: self, stores: stores).build(choiceC: st.c, choiceS: st.s, pool: solver.pool)
            return SolveResult(choiceC: st.c, choiceS: st.s, demand: st.demand, schedule: schedule, finalCost: schedule.totalCost, stores: stores, pool: solver.pool, lambda: lambda)
        }
    }
}
