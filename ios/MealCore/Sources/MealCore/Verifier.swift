import Foundation

/// Независимая проверка готового плана: пересчитывает деньги, аллергены, технику и покрытие закупками.
/// Не использует внутренности оптимизатора — только итоговые данные плана.
public enum PlanVerifier {
    public static func verify(_ plan: MealPlan, library: Library, kitchen: Kitchen) -> [String] {
        var problems: [String] = []
        let s = plan.settings
        if plan.meals.count != s.days * s.slots.count { problems.append("Число блюд \(plan.meals.count) ≠ дни×приёмы \(s.days * s.slots.count)") }
        let allergens = Set(plan.people.flatMap { $0.allergens })
        let resolver = DislikeResolver(library: library)
        var hardKeys = Set<String>()
        for p in plan.people where p.dislikeStrictness == .strict { for d in p.dislikes { hardKeys.formUnion(resolver.ingredientKeys(for: d)) } }
        var recipes: [String: Recipe] = library.recipeIndex
        for r in plan.extraRecipes { recipes[r.id] = r }
        let portions = plan.portionFactors.values.reduce(0, +)

        var demand: [String: Int] = [:]
        for m in plan.meals {
            guard let r = recipes[m.recipeID] else { problems.append("Рецепт \(m.recipeID) не найден"); continue }
            for ri in r.ingredients {
                guard let info = library.ingredients[ri.key] else { problems.append("Нет ингредиента \(ri.key)"); continue }
                if !AllergenChecker.ingredientContains(info, allergens).isEmpty { problems.append("Аллерген в «\(r.name)»: \(info.name)") }
                if hardKeys.contains(ri.key) && !m.locked { problems.append("Нежелательный продукт в «\(r.name)»: \(info.name)") }
                let raw = ri.amount * portions * m.scale / Double(max(1, r.servings))
                let amt = info.unit == .pcs ? max(1, Int(raw.rounded())) : max(1, Int(raw.rounded(.up)))
                demand[ri.key, default: 0] += amt
            }
            if !r.methods.contains(where: { $0.id == m.methodID }) { problems.append("Способ \(m.methodID) отсутствует в «\(r.name)»") }
            else if let method = r.methods.first(where: { $0.id == m.methodID }), kitchen.batches(for: method, servings: portions * m.scale, maxBatches: s.maxBatches) == nil {
                problems.append("«\(r.name)» нельзя приготовить на вашей технике/посуде (способ «\(method.label)»)")
            }
        }
        var bought: [String: Int] = [:]
        var sum = 0
        for l in plan.purchases {
            if l.total.kopecks != l.unitPrice.kopecks * l.packs { problems.append("Сумма строки \(l.productName) ≠ цена×кол-во") }
            sum += l.total.kopecks
            bought[l.ingredientKey, default: 0] += l.packs * l.packBase
        }
        if sum != plan.basketTotal.kopecks { problems.append("Итог корзины \(plan.basketTotal.kopecks) ≠ сумма строк \(sum)") }
        for (k, need) in demand {
            let have = (bought[k] ?? 0) + (plan.usedPantry[k] ?? 0)
            if have < need { problems.append("Не хватает \(library.ingredients[k]?.name ?? k): нужно \(need), куплено+запас \(have)") }
        }
        if (plan.basketTotal > plan.budget) != (plan.status == .overBudget) { problems.append("Статус бюджета не соответствует сумме") }
        return problems
    }
}
