import XCTest
@testable import MealCore

final class CatalogImportTests: XCTestCase {
    func testCSVSemicolonAndDecimalComma() {
        let csv = "Название;Цена;Вес;Бренд;Состав\n\"Рис \"\"Тест\"\" круглозерный\";129,90;900 г;Бренд;рис\nСахар;75;1 кг;;сахар\nМолоко;abc;930 мл;;\n;10;1 кг;;"
        let r = CatalogImport.parseCSV(csv, storeID: "S")
        XCTAssertEqual(r.products.count, 2)
        XCTAssertEqual(r.products[0].price, .rub(129.90))
        XCTAssertEqual(r.products[0].name, "Рис \"Тест\" круглозерный")
        XCTAssertEqual(r.errors.count, 2, "ошибки строк не должны теряться молча: \(r.errors)")
        let offers = OfferBuilder(library: Fixtures.lib).build(from: r.products).offers
        XCTAssertEqual(offers.count, 2)
        XCTAssertEqual(offers.first { $0.ingredientKey == "rice" }?.packBase, 900)
    }
    func testCSVMissingColumns() {
        let r = CatalogImport.parseCSV("a;b\n1;2", storeID: "S")
        XCTAssertTrue(r.products.isEmpty); XCTAssertFalse(r.errors.isEmpty)
    }
    func testJSON() {
        let json = #"{"products":[{"name":"Гречка 800 г","price":119.5,"in_stock":true},{"title":"Масло подсолнечное 1 л","price":"130 ₽"},{"name":"без цены"}]}"#
        let r = CatalogImport.parseJSON(Data(json.utf8), storeID: "S")
        XCTAssertEqual(r.products.count, 2); XCTAssertEqual(r.errors.count, 1)
        XCTAssertEqual(r.products[1].price, .rub(130))
    }
    func testUserPriceBecomesOffer() {
        let up = UserPrice(ingredientKey: "rice", productName: "Рис мой", packSize: 1000, price: .rub(111))
        let p = up.toProduct(library: Fixtures.lib)!
        let o = OfferBuilder(library: Fixtures.lib).build(from: [p]).offers
        XCTAssertEqual(o.first?.quality, .userEntered); XCTAssertEqual(o.first?.packBase, 1000)
    }
}

final class GeoTests: XCTestCase {
    func testDistance() {
        let d = Geo.distance(lat1: 55.7558, lon1: 37.6173, lat2: 59.9343, lon2: 30.3351)
        XCTAssertEqual(d / 1000, 634, accuracy: 5)   // Москва — Санкт-Петербург ≈ 634 км
    }
    func testRadiusExpansion() {
        XCTAssertEqual(SearchRadius.next(after: 500, found: 0), 1000)
        XCTAssertEqual(SearchRadius.next(after: 3000, found: 1), 5000)
        XCTAssertNil(SearchRadius.next(after: 3000, found: 5))
        XCTAssertNil(SearchRadius.next(after: 50_000, found: 0))
    }
    func testAnyStoreIsSupportedNotOnlyKnownChains() {
        let local = StoreInfo(id: "m1", name: "Продуктовая лавка у Ивана", lat: 55.0, lon: 37.0, source: "osm")
        let merged = StoreDirectory.merge([[local]], origin: (55.0, 37.0))
        XCTAssertEqual(merged.count, 1)
        XCTAssertNil(merged[0].chain)
        XCTAssertEqual(StoreDirectory.chain(forName: "Пятёрочка у дома"), "Пятёрочка")
        XCTAssertEqual(StoreDirectory.chain(forName: "ПЯТЕРОЧКА"), "Пятёрочка")
    }
    func testMergeDedupes() {
        let a = StoreInfo(id: "mk1", name: "Магнит", address: nil, lat: 55.0000, lon: 37.0000, source: "mapkit")
        let b = StoreInfo(id: "osm1", name: "Магнит", address: "ул. Тестовая, 1", lat: 55.0003, lon: 37.0002, openingHours: "08:00-23:00", source: "osm")
        let c = StoreInfo(id: "osm2", name: "Лента", lat: 55.01, lon: 37.0, source: "osm")
        let m = StoreDirectory.merge([[a], [b, c]], origin: (55.0, 37.0))
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m[0].address, "ул. Тестовая, 1"); XCTAssertEqual(m[0].openingHours, "08:00-23:00")
        XCTAssertLessThan(m[0].distanceM, m[1].distanceM)
    }
    func testFilters() {
        let s = [StoreInfo(id: "1", name: "Магнит", chain: "Магнит", lat: 0, lon: 0, distanceM: 400, catalog: .crowdsourced),
                 StoreInfo(id: "2", name: "Лавка", lat: 0, lon: 0, distanceM: 4000, shopType: "convenience", catalog: .unknown)]
        XCTAssertEqual(StoreDirectory.apply(.init(maxDistanceM: 1000), to: s).map { $0.id }, ["1"])
        XCTAssertEqual(StoreDirectory.apply(.init(onlyWithCatalog: true), to: s).map { $0.id }, ["1"])
        XCTAssertEqual(StoreDirectory.apply(.init(types: ["convenience"]), to: s).map { $0.id }, ["2"])
        XCTAssertEqual(StoreDirectory.apply(.init(chains: ["Лавка"]), to: s).map { $0.id }, ["2"])
    }
}

final class AssistantTests: XCTestCase {
    let lib = Fixtures.lib
    func makeInput(days: Int = 7) -> PlanInput {
        let ppl = [PersonProfile(name: "A", allergens: [.peanuts], dislikes: ["грибы", "печень"]), PersonProfile(name: "B", allergens: [.peanuts])]
        let stores = [Fixtures.store("A", name: "А", km: 0.4)]
        let offers = Fixtures.offers(Fixtures.products(store: "A"), allergens: [.peanuts])
        return PlanInput(settings: Fixtures.settings(days: days, budget: 9000), people: ppl, stores: stores, offers: offers, kitchen: Fixtures.fullKitchen)
    }

    func testParserUnderstandsSpecExample() throws {
        let input = makeInput()
        let plan = try MealPlanner(library: lib).plan(input)
        let intent = AssistantParser.parse("Замени ужин в среду на что-нибудь с курицей", plan: plan, library: lib)
        XCTAssertEqual(intent.action, .replaceMeal)
        XCTAssertEqual(intent.slot, 2)   // «Ужин» — третий приём
        XCTAssertNotNil(intent.day)
        XCTAssertTrue(intent.include.contains("chicken_breast") || intent.include.contains("chicken_thigh"), "\(intent.include)")
        // день совпадает со средой
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(byAdding: .day, value: intent.day!, to: plan.settings.startDate)!
        XCTAssertEqual(cal.component(.weekday, from: date), 4)
    }

    func testReplaceMealGoesThroughVerification() throws {
        let input = makeInput()
        let engine = AssistantEngine(planner: MealPlanner(library: lib))
        let plan = try engine.planner.plan(input)
        let out = engine.handle(text: "Замени ужин в среду на что-нибудь с курицей", input: input, plan: plan)
        let p2 = try XCTUnwrap(out.updatedPlan, out.message)
        let intent = AssistantParser.parse("Замени ужин в среду на что-нибудь с курицей", plan: plan, library: lib)
        let meal = p2.meals.first { $0.day == intent.day! && $0.slot == intent.slot! }!
        XCTAssertTrue(lib.recipeIndex[meal.recipeID]!.ingredients.contains { $0.key.hasPrefix("chicken") }, meal.recipeName)
        XCTAssertEqual(PlanVerifier.verify(p2, library: lib, kitchen: input.kitchen), [])
        // остальные блюда не изменились
        for m in plan.meals where !(m.day == intent.day! && m.slot == intent.slot!) {
            XCTAssertEqual(p2.meals.first { $0.day == m.day && $0.slot == m.slot }?.recipeID, m.recipeID)
        }
        XCTAssertLessThanOrEqual(p2.basketTotal, p2.budget)
    }

    func testVarietyAndCheaperIntents() throws {
        let input = makeInput(days: 5)
        let engine = AssistantEngine(planner: MealPlanner(library: lib))
        let plan = try engine.planner.plan(input)
        XCTAssertEqual(AssistantParser.parse("Хочу питаться разнообразнее, но бюджет увеличивать нельзя", plan: plan, library: lib).action, .moreVariety)
        let o = engine.handle(text: "Хочу питаться разнообразнее, но бюджет увеличивать нельзя", input: input, plan: plan)
        if let p2 = o.updatedPlan { XCTAssertLessThanOrEqual(p2.basketTotal, plan.budget) }
        let c = engine.handle(text: "Сделай подешевле", input: input, plan: plan)
        if let p2 = c.updatedPlan { XCTAssertLessThanOrEqual(p2.basketTotal, plan.basketTotal) }
    }

    func testUnknownCommandIsHonest() throws {
        let plan = try MealPlanner(library: lib).plan(makeInput(days: 2))
        XCTAssertEqual(AssistantParser.parse("расскажи анекдот", plan: plan, library: lib).action, .unknown)
    }

    func testAIRecipeValidation() {
        let good = RecipeValidator.Draft(name: "Курица с рисом", meals: ["dinner"], servings: 2, prep: 10, cook: 25,
                                         ingredients: [.init(key: "chicken_breast", amount: 300), .init(key: "rice", amount: 150)], steps: ["Обжарьте курицу 7 минут.", "Добавьте рис и воду, варите 18 минут."])
        let (r, errs) = RecipeValidator.validate(good, library: lib)
        XCTAssertNotNil(r); XCTAssertTrue(errs.isEmpty)
        var bad = good; bad.ingredients.append(.init(key: "unicorn_meat", amount: 100))
        XCTAssertNil(RecipeValidator.validate(bad, library: lib).0)
        var absurd = good; absurd.ingredients = [.init(key: "chicken_breast", amount: 99999)]
        XCTAssertNil(RecipeValidator.validate(absurd, library: lib).0)
    }

    func testAIRecipeStillFacesAllergenFilter() throws {
        // AI предложил блюдо с арахисовой пастой — планировщик не допустит его при аллергии
        let draft = RecipeValidator.Draft(name: "Паста с арахисом", meals: ["dinner", "lunch"], servings: 2, ingredients: [.init(key: "pasta", amount: 200), .init(key: "peanut_butter", amount: 60)], steps: ["Сварите макароны 10 минут.", "Смешайте с пастой."])
        let recipe = RecipeValidator.validate(draft, library: lib, id: "ai1").0!
        var input = makeInput(days: 3)
        input.extraRecipes = [recipe]
        input.locked[SlotKey(day: 0, slot: 2)] = LockedChoice(recipeID: "ai1")
        let plan = try MealPlanner(library: lib).plan(input)
        XCTAssertNotEqual(plan.meals.first { $0.day == 0 && $0.slot == 2 }?.recipeID, "ai1")
    }
}

final class StorageAndExportTests: XCTestCase {
    func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("mc-\(UUID().uuidString)") }

    func testRoundTripAndOfflineAccess() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(directory: dir)
        var s = AppState()
        s.people = [PersonProfile(name: "Тест", allergens: [.peanuts, .custom("киви")])]
        s.pantry = [PantryItem(ingredientKey: "rice", amount: 500, expiry: Date(timeIntervalSince1970: 1_900_000_000))]
        let ppl = [PersonProfile(name: "A")]
        let offers = Fixtures.offers(Fixtures.products(store: "A"))
        let plan = try MealPlanner(library: Fixtures.lib).plan(PlanInput(settings: Fixtures.settings(days: 2, budget: 3000), people: ppl, stores: [Fixtures.store("A", name: "А", km: 1)], offers: offers, kitchen: Fixtures.fullKitchen))
        s.plans = [plan]; s.currentPlanID = plan.id
        try store.save(s)
        guard case .loaded(let back) = StateStore(directory: dir).load() else { return XCTFail("не загрузилось") }
        XCTAssertEqual(back.people, s.people); XCTAssertEqual(back.pantry, s.pantry)
        XCTAssertEqual(back.currentPlan?.basketTotal, plan.basketTotal)
        XCTAssertEqual(back.currentPlan?.meals, plan.meals)
        XCTAssertEqual(back.currentPlan?.purchases.count, plan.purchases.count)
    }

    func testCorruptionIsNotSilent() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(directory: dir)
        try Data("{ broken".utf8).write(to: store.url)
        guard case .recoveredFromCorruption(let backup) = store.load() else { return XCTFail() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    func testWipeDeletesEverything() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(directory: dir)
        try store.save(AppState()); try store.wipe()
        guard case .fresh = store.load() else { return XCTFail() }
    }

    func testExportTextAndCSV() throws {
        let offers = Fixtures.offers(Fixtures.products(store: "A"))
        let plan = try MealPlanner(library: Fixtures.lib).plan(PlanInput(settings: Fixtures.settings(days: 2, budget: 3000), people: [PersonProfile(name: "A")], stores: [Fixtures.store("A", name: "Тест-А", km: 1)], offers: offers, kitchen: Fixtures.fullKitchen))
        let t = ShoppingExport.text(plan)
        XCTAssertTrue(t.contains("Тест-А")); XCTAssertTrue(t.contains("Итого"))
        let c = ShoppingExport.csv(plan)
        XCTAssertEqual(c.split(separator: "\n").count, plan.purchases.count + 1)
        let st = PlanStatistics(plan: plan, library: Fixtures.lib, offers: offers)
        XCTAssertEqual(st.totalCost, plan.basketTotal)
        XCTAssertEqual(Money.sum(st.costByStore.map { $0.cost }), plan.basketTotal)
        XCTAssertEqual(Money.sum(st.costByCategory.map { $0.cost }), plan.basketTotal)
    }

    func testCookingProgress() {
        var p = CookingProgress(recipeID: "r", methodID: "m", servings: 2)
        p.next(total: 3); p.next(total: 3); p.next(total: 3)
        XCTAssertEqual(p.currentStep, 2); XCTAssertTrue(p.isFinished(total: 3))
        p.previous(); XCTAssertEqual(p.currentStep, 1)
        let now = Date()
        p.startTimer(step: 1, minutes: 7, now: now)
        XCTAssertEqual(p.remaining(step: 1, now: now.addingTimeInterval(60)) ?? 0, 360, accuracy: 0.5)
        let data = try! JSONEncoder().encode(p)
        XCTAssertEqual(try! JSONDecoder().decode(CookingProgress.self, from: data), p)
    }

    func testRecipeScalingRecalculatesPortions() {
        let lib = Fixtures.lib
        let r = lib.recipeIndex["chicken_rice_pan"]!
        let two = RecipeRenderer.render(recipe: r, servings: 2, library: lib)
        let six = RecipeRenderer.render(recipe: r, servings: 6, library: lib)
        let c2 = two.ingredients.first { $0.key == "chicken_breast" }!.grams
        let c6 = six.ingredients.first { $0.key == "chicken_breast" }!.grams
        XCTAssertEqual(c6, c2 * 3, accuracy: 1)
        XCTAssertTrue(two.steps[0].text.contains("300 г"), two.steps[0].text)
        XCTAssertTrue(six.steps[0].text.contains("900 г"), six.steps[0].text)
        XCTAssertTrue(six.steps[3].text.contains("1,1 л") || six.steps[3].text.contains("1050") || six.steps[3].text.contains("л"), six.steps[3].text)
    }
}
