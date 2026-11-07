import Foundation

extension MealPlanner.Context {
    func assemble(_ r: SolveResult, stores chosen: Set<String>) -> MealPlan {
        let pool = r.pool
        let sched = r.schedule
        let budget = settings.budget
        var warnings: [PlanWarning] = []

        // Предложения по id
        var offerByID: [String: Offer] = [:]
        for o in input.offers { offerByID[o.id] = o }
        for (_, list) in estimateOffersByIng { for o in list { offerByID[o.id] = o } }

        // Закупки
        var purchases: [PurchaseLine] = []
        var priceMix: [String: Int] = [:]
        for l in sched.lines {
            guard let o = offerByID[l.offerID], let info = lib.ingredients[l.key] else { continue }
            let total = Money(kopecks: l.price * l.packs)
            var advice = info.store.title
            if l.needsFreezing { advice = "Часть заморозьте сразу после покупки (в холодильнике хранится ~\(info.shelf) сут.)" }
            purchases.append(PurchaseLine(ingredientKey: l.key, ingredientName: info.name, offerID: l.offerID, storeID: l.storeID, productName: o.name, brand: o.brand,
                                          imageURL: o.imageURL, url: o.url, packs: l.packs, packBase: l.packSize, unit: info.unit, unitPrice: Money(kopecks: l.price), total: total,
                                          purchaseDay: l.day, quality: o.quality, priceDate: o.priceDate, promoText: o.promoText, warning: o.warning,
                                          storageAdvice: advice, purchased: false))
            priceMix[o.quality.rawValue, default: 0] += total.kopecks
        }
        purchases.sort { ($0.purchaseDay, $0.storeID, $0.ingredientName) < ($1.purchaseDay, $1.storeID, $1.ingredientName) }

        // Средняя цена за единицу по ингредиенту
        func unitCost(_ key: String) -> Double {
            if let c = sched.costByKey[key], let b = sched.purchasedBase[key], b > 0 { return Double(c) / Double(b) }
            let offs = (offersByIng[key] ?? []).filter { chosen.contains($0.storeID) } + (estimateOffersByIng[key] ?? [])
            return offs.map { $0.unitPrice }.min() ?? 0
        }

        // Блюда
        var meals: [PlannedMeal] = []
        var dayStats: [DayStat] = []
        var dayCost = [Int](repeating: 0, count: settings.days)
        for i in 0..<N {
            let cand = pool[r.choiceC[i]]
            let sIdx = r.choiceS[i]
            let scale = MealPlanner.scales[sIdx]
            let day = i / M, slot = i % M
            var cost = 0.0
            for e in cand.demand[sIdx] { cost += Double(e.amt) * unitCost(ingKeys[e.idx]) }
            let money = Money(kopecks: Int(cost.rounded()))
            dayCost[day] += money.kopecks
            let isLocked = input.locked[SlotKey(day: day, slot: slot)] != nil
            meals.append(PlannedMeal(day: day, slot: slot, slotName: slots[slot].name, type: slots[slot].type, recipeID: cand.recipe.id, recipeName: cand.recipe.name,
                                     scale: scale, portions: portions * scale, methodID: cand.method.id, batches: cand.batchesByScale[sIdx],
                                     cost: money, nutritionPerPortion: cand.nutrition.scaled(scale), locked: isLocked, done: false))
        }
        for d in 0..<settings.days {
            var n = Nutrition.zero
            for m in meals where m.day == d { n += m.nutritionPerPortion }
            dayStats.append(DayStat(day: d, kcalReference: n.kcal, protein: n.protein, fat: n.fat, carbs: n.carbs, cost: Money(kopecks: dayCost[d])))
        }

        // Визиты в магазины
        var visitMap: [String: (day: Int, store: String, total: Int, lines: Int)] = [:]
        for p in purchases where p.storeID != ReferencePrices.storeID {
            let k = "\(p.purchaseDay)|\(p.storeID)"
            var v = visitMap[k] ?? (p.purchaseDay, p.storeID, 0, 0)
            v.total += p.total.kopecks; v.lines += 1
            visitMap[k] = v
        }
        let visits = visitMap.values.sorted { ($0.day, $0.store) < ($1.day, $1.store) }.map { StoreVisit(day: $0.day, storeID: $0.store, total: Money(kopecks: $0.total), lines: $0.lines) }

        // Остатки в деньгах
        var leftover = 0.0
        for (k, amt) in sched.leftoverBase { leftover += Double(amt) * unitCost(k) }

        let basket = Money(kopecks: sched.totalCost)
        let status: PlanStatus = basket > budget ? .overBudget : .ok

        // Предупреждения
        let estMoney = priceMix[PriceQuality.estimate.rawValue] ?? 0
        if estMoney > 0 {
            warnings.append(PlanWarning(kind: .estimatePrices, message: "Часть цен — ориентировочные (не данные магазина): \(Money(kopecks: estMoney)) из \(basket). Проверьте их в магазине или введите реальные цены."))
        }
        let stale = purchases.filter { p in p.quality == .crowdsourced && (p.priceDate.map { Date().timeIntervalSince($0) > 30 * 86400 } ?? true) }
        if !stale.isEmpty { warnings.append(PlanWarning(kind: .stalePrices, message: "Для \(stale.count) поз. цены старше 30 дней (краудсорсинг) — реальная цена может отличаться.")) }
        let unconfirmed = purchases.filter { $0.warning != nil && $0.quality != .estimate }
        if !unconfirmed.isEmpty && !allergens.isEmpty {
            warnings.append(PlanWarning(kind: .unconfirmedComposition, message: "У \(unconfirmed.count) товаров состав не подтверждён источником — при аллергии проверьте упаковку."))
        }
        if !sched.missing.isEmpty {
            let names = sched.missing.keys.compactMap { lib.ingredients[$0]?.name }.sorted().joined(separator: ", ")
            warnings.append(PlanWarning(kind: .missingPrices, message: "Нет цен для: \(names). Эти продукты не включены в стоимость."))
        }
        let avgKcal = dayStats.map { $0.kcalReference }.reduce(0, +) / Double(max(1, dayStats.count))
        if avgKcal < Energy.referenceKcal * 0.85 {
            warnings.append(PlanWarning(kind: .lowCalories, message: "При \(M) приёмах пищи рацион даёт в среднем \(Int(avgKcal)) ккал на стандартную порцию в день (ориентир \(Int(Energy.referenceKcal))). Добавьте приёмы пищи или увеличьте порции."))
        }
        if meals.contains(where: { $0.batches > 1 }) {
            warnings.append(PlanWarning(kind: .batches, message: "Часть блюд придётся готовить в несколько подходов — посуда мала для всей порции сразу."))
        }
        if purchases.contains(where: { ($0.storageAdvice ?? "").contains("заморозьте") }) {
            warnings.append(PlanWarning(kind: .freezing, message: "Часть продуктов нужно заморозить после покупки, чтобы они дожили до использования."))
        }
        if status == .overBudget {
            warnings.append(PlanWarning(kind: .overBudget, message: "Минимально возможная стоимость при ваших ограничениях — \(basket), это больше бюджета \(budget) на \(basket - budget)."))
        }

        // Советы
        var tips: [SavingsTip] = []
        if status == .overBudget {
            let ratio = Double(budget.kopecks) / Double(max(1, basket.kopecks))
            let fit = max(1, Int((Double(settings.days) * ratio).rounded(.down)))
            if fit < settings.days { tips.append(SavingsTip(text: "На этот бюджет хватает примерно на \(fit) дн. вместо \(settings.days).", estimatedSaving: nil)) }
            tips.append(SavingsTip(text: "Чтобы уложиться в \(settings.days) дн., потребуется бюджет не менее \(basket).", estimatedSaving: nil))
            if slots.contains(where: { $0.type == .snack }) {
                tips.append(SavingsTip(text: "Уберите перекусы — это сократит закупку.", estimatedSaving: nil))
            }
            if input.stores.count < 3 { tips.append(SavingsTip(text: "Выберите больше магазинов — цены на одни и те же товары различаются.", estimatedSaving: nil)) }
            if !hardDislikeKeys.isEmpty { tips.append(SavingsTip(text: "Смягчите строгость нежелательных продуктов: больше рецептов — ниже цена.", estimatedSaving: nil)) }
        } else if settings.goal != .economy && basket.kopecks > 0 {
            tips.append(SavingsTip(text: "Включите цель «Максимально экономное питание», чтобы снизить стоимость.", estimatedSaving: nil))
        }

        var usedPantry: [String: Int] = [:]
        for (k, v) in sched.usedPantry { usedPantry[k] = v }

        var pk: [String: Double] = [:], pf: [String: Double] = [:]
        for (i, p) in input.people.enumerated() {
            pk[p.id.uuidString] = Energy.dailyKcal(p, goal: settings.goal)
            pf[p.id.uuidString] = factors[i]
        }
        let dishTotal = Money.sum(meals.map { $0.cost })
        let usedExtra = input.extraRecipes.filter { rr in meals.contains { $0.recipeID == rr.id } }
        let title = "Рацион на \(settings.days) \(MealPlanner.plural(settings.days, "день", "дня", "дней"))"
        return MealPlan(id: UUID(), createdAt: Date(), title: title, settings: settings, people: input.people, meals: meals, purchases: purchases,
                        stores: input.stores.filter { st in chosen.contains(st.id) || visits.contains(where: { v in v.storeID == st.id }) },
                        visits: visits, basketTotal: basket, dishCostTotal: dishTotal, leftoverValue: Money(kopecks: Int(leftover.rounded())), budget: budget,
                        status: status, dayStats: dayStats, personKcal: pk, portionFactors: pf, priceMix: priceMix, warnings: warnings, tips: tips,
                        usedPantry: usedPantry, extraRecipes: usedExtra, minimumAchievable: status == .overBudget ? basket : nil)
    }
}

extension MealPlanner {
    public static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = abs(n) % 100, b = a % 10
        if a > 10 && a < 20 { return many }
        if b > 1 && b < 5 { return few }
        if b == 1 { return one }
        return many
    }
}
