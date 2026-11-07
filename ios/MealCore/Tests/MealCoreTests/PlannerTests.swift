import XCTest
@testable import MealCore

final class PlannerTests: XCTestCase {
    let lib = Fixtures.lib

    func specInput(days: Int = 7, budget: Int = 7000, meals: Int = 3, people: [PersonProfile]? = nil, kitchen: Kitchen? = nil, goal: DietGoal = .balanced, mode: ShoppingMode = .balanced) -> PlanInput {
        let ppl = people ?? [
            PersonProfile(name: "Человек 1", allergens: [.peanuts], dislikes: ["грибы", "печень"], favorites: ["курица", "рис", "макароны"]),
            PersonProfile(name: "Человек 2", allergens: [.peanuts], dislikes: ["грибы", "печень"], favorites: ["курица", "рис", "макароны"]),
        ]
        let allergens = Set(ppl.flatMap { $0.allergens })
        let stores = [Fixtures.store("A", name: "Тест-А", km: 0.4), Fixtures.store("B", name: "Тест-Б", km: 1.2), Fixtures.store("C", name: "Тест-В", km: 2.5)]
        let offers = Fixtures.offers(Fixtures.products(store: "A") + Fixtures.products(store: "B", factor: 0.92, drop: ["shrimp", "pink_salmon"]) + Fixtures.products(store: "C", factor: 1.1), allergens: allergens)
        return PlanInput(settings: Fixtures.settings(days: days, budget: budget, meals: meals, goal: goal, mode: mode), people: ppl, stores: stores, offers: offers, kitchen: kitchen ?? Fixtures.specKitchen)
    }

    func testSpecScenario() throws {
        let input = specInput()
        let plan = try MealPlanner(library: lib).plan(input)
        // независимая верификация
        XCTAssertEqual(PlanVerifier.verify(plan, library: lib, kitchen: input.kitchen), [])
        XCTAssertEqual(plan.meals.count, 21)
        XCTAssertLessThanOrEqual(plan.basketTotal, plan.budget)
        XCTAssertEqual(plan.status, .ok)
        // в меню нет арахиса, грибов, печени
        for m in plan.meals {
            let r = lib.recipeIndex[m.recipeID]!
            let keys = Set(r.ingredients.map { $0.key })
            XCTAssertFalse(keys.contains("peanut_butter"), r.name)
            XCTAssertFalse(keys.contains("mushrooms"), r.name)
            XCTAssertFalse(keys.contains("chicken_liver"), r.name)
            // без духовки/блендера
            XCTAssertNotEqual(m.methodID, "oven")
        }
        // любимые продукты влияют на меню
        let usesChicken = plan.meals.filter { lib.recipeIndex[$0.recipeID]!.ingredients.contains { $0.key.hasPrefix("chicken") } }.count
        XCTAssertGreaterThanOrEqual(usesChicken, 2)
        // разнообразие: не меньше 8 различных блюд за неделю
        XCTAssertGreaterThanOrEqual(Set(plan.meals.map { $0.recipeID }).count, 8)
        print("СЦЕНАРИЙ ТЗ: корзина \(plan.basketTotal) из \(plan.budget), блюд различных: \(Set(plan.meals.map { $0.recipeID }).count), магазины: \(plan.visits.map { $0.storeID }), остатки на \(plan.leftoverValue)")
        for d in plan.dayStats { print("день \(d.day + 1): \(Int(d.kcalReference)) ккал, белок \(Int(d.protein)), блюд на \(d.cost)") }
    }

    func testBudgetIsNeverFakedWhenTooLow() throws {
        let plan = try MealPlanner(library: lib).plan(specInput(budget: 500))
        XCTAssertEqual(plan.status, .overBudget)
        XCTAssertGreaterThan(plan.basketTotal, plan.budget)
        XCTAssertFalse(plan.tips.isEmpty)
        XCTAssertNotNil(plan.minimumAchievable)
        XCTAssertEqual(PlanVerifier.verify(plan, library: lib, kitchen: Fixtures.specKitchen), [])   // денежные суммы честные
    }

    func testBudgetMonotonic() throws {
        let cheap = try MealPlanner(library: lib).plan(specInput(budget: 100_000, goal: .economy))
        let rich = try MealPlanner(library: lib).plan(specInput(budget: 100_000, goal: .balanced))
        XCTAssertLessThanOrEqual(cheap.basketTotal, rich.basketTotal)
    }

    func testNoPriceDataFailsHonestly() {
        var input = specInput()
        input.offers = []
        XCTAssertThrowsError(try MealPlanner(library: lib).plan(input)) { err in
            guard case PlanError.noPriceData = err else { return XCTFail("\(err)") }
        }
    }

    func testEstimateModeIsLabeled() throws {
        var input = specInput()
        input.offers = []
        input.settings.pricePolicy = .allowEstimates
        let plan = try MealPlanner(library: lib).plan(input)
        XCTAssertGreaterThan(plan.estimateShare, 0.99)
        XCTAssertTrue(plan.warnings.contains { $0.kind == .estimatePrices })
        XCTAssertTrue(plan.purchases.allSatisfy { $0.quality == .estimate })
        XCTAssertEqual(PlanVerifier.verify(plan, library: lib, kitchen: input.kitchen), [])
    }

    func testRealPricesPreferredOverEstimates() throws {
        var input = specInput()
        input.settings.pricePolicy = .allowEstimates
        let plan = try MealPlanner(library: lib).plan(input)
        XCTAssertEqual(plan.estimateShare, 0, accuracy: 0.0001)
    }

    func testLargeGroupAndLongPeriod() throws {
        let people = (1...10).map { PersonProfile(name: "Гость \($0)", allergens: $0 == 3 ? [.milk] : []) }
        var input = specInput(days: 30, budget: 150_000, meals: 4, people: people, kitchen: Fixtures.fullKitchen)
        input.settings.stageDays = 7
        let t0 = Date()
        let plan = try MealPlanner(library: lib).plan(input)
        let dt = Date().timeIntervalSince(t0)
        print("10 чел × 30 дн × 4 приёма: \(plan.basketTotal), время \(String(format: "%.2f", dt)) с, закупок-визитов: \(Set(plan.visits.map { $0.day }).count)")
        XCTAssertEqual(plan.meals.count, 120)
        XCTAssertEqual(PlanVerifier.verify(plan, library: lib, kitchen: input.kitchen), [])
        XCTAssertGreaterThan(Set(plan.visits.map { $0.day }).count, 1, "для 30 дней закупки должны идти этапами")
        // никакого молока у человека №3
        for m in plan.meals { XCTAssertFalse(lib.recipeIndex[m.recipeID]!.ingredients.contains { lib.ingredients[$0.key]!.allergens.contains("milk") }, m.recipeName) }
    }

    func testSinglePersonSingleDay() throws {
        let input = specInput(days: 1, budget: 1000, meals: 1, people: [PersonProfile(name: "Один")], kitchen: Fixtures.fullKitchen)
        let plan = try MealPlanner(library: lib).plan(input)
        XCTAssertEqual(plan.meals.count, 1)
        XCTAssertEqual(PlanVerifier.verify(plan, library: lib, kitchen: input.kitchen), [])
    }

    func testPantryReducesPurchases() throws {
        var input = specInput(days: 3, budget: 5000, meals: 3, people: [PersonProfile(name: "A", favorites: ["рис"])])
        let base = try MealPlanner(library: lib).plan(input)
        input.pantry = [PantryItem(ingredientKey: "rice", amount: 5000), PantryItem(ingredientKey: "buckwheat", amount: 5000), PantryItem(ingredientKey: "pasta", amount: 5000), PantryItem(ingredientKey: "potato", amount: 5000), PantryItem(ingredientKey: "sunflower_oil", amount: 900), PantryItem(ingredientKey: "salt", amount: 900)]
        let withPantry = try MealPlanner(library: lib).plan(input)
        XCTAssertLessThan(withPantry.basketTotal, base.basketTotal)
        XCTAssertFalse(withPantry.purchases.contains { $0.ingredientKey == "salt" })
        XCTAssertEqual(PlanVerifier.verify(withPantry, library: lib, kitchen: input.kitchen), [])
    }

    func testPerishablesAreNotBoughtForMonthWithoutFreezer() throws {
        var kitchen = Fixtures.fullKitchen
        kitchen.equipment.remove("freezer")
        var input = specInput(days: 14, budget: 60_000, meals: 3, people: [PersonProfile(name: "A")], kitchen: kitchen)
        input.settings.stageDays = 7
        let plan = try MealPlanner(library: lib).plan(input)
        // свежее мясо (годность 2 сут.) покупается не раньше, чем за пару дней до использования
        var firstUse: [String: Int] = [:]
        for m in plan.meals { for ri in lib.recipeIndex[m.recipeID]!.ingredients where lib.ingredients[ri.key]!.shelf <= 3 { firstUse[ri.key] = min(firstUse[ri.key] ?? 99, m.day) } }
        for p in plan.purchases where lib.ingredients[p.ingredientKey]!.shelf <= 3 {
            // для каждой покупки существует использование в пределах срока годности
            let uses = plan.meals.filter { m in lib.recipeIndex[m.recipeID]!.ingredients.contains { $0.key == p.ingredientKey } }.map { $0.day }
            XCTAssertTrue(uses.contains { $0 >= p.purchaseDay && $0 - p.purchaseDay < lib.ingredients[p.ingredientKey]!.shelf }, "\(p.ingredientName) куплен в день \(p.purchaseDay), использование \(uses)")
        }
        XCTAssertEqual(PlanVerifier.verify(plan, library: lib, kitchen: input.kitchen), [])
    }

    func testSingleStoreModeUsesOneStore() throws {
        let plan = try MealPlanner(library: lib).plan(specInput(mode: .singleStore))
        XCTAssertEqual(Set(plan.purchases.map { $0.storeID }).count, 1)
    }

    func testCheapestNotMoreExpensiveThanNearest() throws {
        let cheap = try MealPlanner(library: lib).plan(specInput(budget: 100_000, mode: .cheapest))
        let near = try MealPlanner(library: lib).plan(specInput(budget: 100_000, mode: .nearest))
        XCTAssertLessThanOrEqual(cheap.basketTotal.kopecks, near.basketTotal.kopecks + 100)
        XCTAssertLessThanOrEqual(near.visits.count, cheap.visits.count + 1)
    }

    func testNoKitchenMeansNoRecipes() {
        let input = specInput(kitchen: Kitchen(equipment: [], cookware: []))
        XCTAssertThrowsError(try MealPlanner(library: lib).plan(input)) { err in
            guard case PlanError.noRecipes = err else { return XCTFail("\(err)") }
        }
    }

    func testLockedSlotIsHonored() throws {
        var input = specInput(days: 3)
        input.locked[SlotKey(day: 1, slot: 2)] = LockedChoice(recipeID: "chicken_rice_pan")
        let plan = try MealPlanner(library: lib).plan(input)
        XCTAssertEqual(plan.meals.first { $0.day == 1 && $0.slot == 2 }?.recipeID, "chicken_rice_pan")
        XCTAssertEqual(PlanVerifier.verify(plan, library: lib, kitchen: input.kitchen), [])
    }

    func testAllergenCannotBeBypassedByLock() throws {
        var input = specInput(days: 2)
        input.locked[SlotKey(day: 0, slot: 0)] = LockedChoice(recipeID: "oat_peanut_banana")
        let plan = try MealPlanner(library: lib).plan(input)
        XCTAssertNotEqual(plan.meals.first { $0.day == 0 && $0.slot == 0 }?.recipeID, "oat_peanut_banana")
    }

    func testDeterministic() throws {
        let a = try MealPlanner(library: lib).plan(specInput())
        let b = try MealPlanner(library: lib).plan(specInput())
        XCTAssertEqual(a.meals.map { $0.recipeID }, b.meals.map { $0.recipeID })
        XCTAssertEqual(a.basketTotal, b.basketTotal)
    }

    func testMoneyConsistencyAcrossRandomScenarios() throws {
        var rng = SplitMix64(s: 99)
        for i in 0..<6 {
            let people = (0..<(1 + rng.int(4))).map { PersonProfile(name: "P\($0)") }
            let input = specInput(days: 1 + rng.int(10), budget: 2000 + rng.int(20000), meals: 1 + rng.int(5), people: people, kitchen: Fixtures.fullKitchen)
            let plan = try MealPlanner(library: lib).plan(input)
            XCTAssertEqual(PlanVerifier.verify(plan, library: lib, kitchen: input.kitchen), [], "scenario \(i)")
        }
    }
}
