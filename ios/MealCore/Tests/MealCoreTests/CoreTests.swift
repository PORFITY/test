import XCTest
@testable import MealCore

final class MoneyAndParsingTests: XCTestCase {
    func testMoneyArithmeticIsExact() {
        // 0.1 + 0.2 в копейках без ошибок Double
        XCTAssertEqual((Money.rub(0.10) + Money.rub(0.20)).kopecks, 30)
        let items = (0..<1000).map { _ in Money.rub(19.99) }
        XCTAssertEqual(Money.sum(items).kopecks, 1_999_000)
        XCTAssertEqual(Money.rub(130).divided(by: 3).kopecks, 4333)
        XCTAssertEqual(Money.rub(7000).formatted(), "7\u{00A0}000\u{00A0}₽")
        XCTAssertEqual(Money(kopecks: 123450).formatted(), "1\u{00A0}234,50\u{00A0}₽")
        XCTAssertEqual(Money.rub(1.005).kopecks, 101)  // математическое округление
    }

    func testPackageSizeParser() {
        XCTAssertEqual(PackageSizeParser.parse("Рис 900 г"), .init(value: 900, unit: .g))
        XCTAssertEqual(PackageSizeParser.parse("Гречка 0,8 кг"), .init(value: 800, unit: .g))
        XCTAssertEqual(PackageSizeParser.parse("Молоко 3,2% 1.5 л"), .init(value: 1500, unit: .ml))
        XCTAssertEqual(PackageSizeParser.parse("Яйцо С1 10 шт."), .init(value: 10, unit: .pcs))
        XCTAssertEqual(PackageSizeParser.parse("Йогурт 4x125 г"), .init(value: 500, unit: .g))
        XCTAssertEqual(PackageSizeParser.parse("Масло 900мл"), .init(value: 900, unit: .ml))
        XCTAssertNil(PackageSizeParser.parse("Рис без указания веса"))
        // «Молоко 3,2% 930 мл» — берём размер, а не процент жирности
        XCTAssertEqual(PackageSizeParser.parse("Молоко 3,2% 930 мл"), .init(value: 930, unit: .ml))
    }

    func testPackConversion() {
        let lib = Fixtures.lib
        XCTAssertEqual(PackageSizeParser.toBase(.init(value: 1000, unit: .ml), for: lib.ingredients["sunflower_oil"]!), 1000)
        // яйца, указанные в граммах: 550 г ≈ 10 шт при 55 г/шт
        XCTAssertEqual(PackageSizeParser.toBase(.init(value: 550, unit: .g), for: lib.ingredients["egg"]!), 10)
        // мёд в мл → граммы не определены без плотности: используется 1.0
        XCTAssertNotNil(PackageSizeParser.toBase(.init(value: 250, unit: .ml), for: lib.ingredients["honey"]!))
    }
}

final class MatcherTests: XCTestCase {
    let m = ProductMatcher(library: Fixtures.lib)
    func testMatches() {
        XCTAssertEqual(m.match(name: "Рис Увелка круглозерный 900 г"), "rice")
        XCTAssertNil(m.match(name: "Мука рисовая 500 г"))
        XCTAssertNil(m.match(name: "Хлопья рисовые 375 г"))
        XCTAssertEqual(m.match(name: "Молоко пастеризованное 3,2% 930 мл"), "milk")
        XCTAssertNil(m.match(name: "Молоко сгущённое 380 г"))
        XCTAssertEqual(m.match(name: "Сыр Российский 50% 200 г"), "cheese")
        XCTAssertNil(m.match(name: "Сырок глазированный 40 г"))
        XCTAssertEqual(m.match(name: "Масло сливочное Традиционное 82,5% 180 г"), "butter")
        XCTAssertEqual(m.match(name: "Масло подсолнечное рафинированное 1 л"), "sunflower_oil")
        XCTAssertNil(m.match(name: "Масло оливковое 500 мл"))
        XCTAssertEqual(m.match(name: "Филе куриное грудки охлаждённое 1 кг"), "chicken_breast")
        XCTAssertEqual(m.match(name: "Фарш говяжий 500 г"), "ground_beef")
        XCTAssertEqual(m.match(name: "Яйцо куриное С1 10 шт"), "egg")
        XCTAssertNil(m.match(name: "Печенье овсяное 300 г"))
        XCTAssertEqual(m.match(name: "Паста арахисовая 340 г"), "peanut_butter")
        XCTAssertEqual(m.match(name: "Макароны Спагетти 450 г"), "pasta")
        XCTAssertNil(m.match(name: "Корм для кошек с курицей"))
        XCTAssertEqual(m.match(name: "Мёд цветочный 250 г"), "honey")
        XCTAssertNil(m.match(name: "Нечто неизвестное"))
    }
}

final class PackCoverTests: XCTestCase {
    func offer(_ id: String, _ size: Int, _ price: Int, store: String = "A") -> Offer {
        Offer(id: id, storeID: store, ingredientKey: "rice", packBase: size, price: .rub(price), regularPrice: .rub(price), name: id, brand: nil, imageURL: nil, url: nil, quality: .imported, priceDate: nil, source: "t", promoText: nil, outletNote: nil, compositionConfirmed: true, warning: nil)
    }

    func testSpecExample_riceWholePackIsPaid() {
        // 150 г риса при упаковке 900 г за 130 ₽ → платим за всю упаковку
        let c = PackCover(offers: [offer("p900", 900, 130)])
        XCTAssertEqual(c.cost(need: 150), 13000)
        XCTAssertEqual(c.select(need: 150)?.totalSize, 900)   // 750 г остаются в запасе
        XCTAssertEqual(c.cost(need: 900), 13000)
        XCTAssertEqual(c.cost(need: 901), 26000)
    }

    func testMatchesBruteForce() {
        var rng = SplitMix64(s: 42)
        for _ in 0..<60 {
            let n = 1 + rng.int(3)
            let offs = (0..<n).map { offer("o\($0)", 100 + rng.int(900), 50 + rng.int(400)) }
            let c = PackCover(offers: offs)
            let need = 1 + rng.int(2500)
            // перебор: до 8 упаковок каждого вида
            var best = Int.max
            func rec(_ i: Int, _ size: Int, _ cost: Int) {
                if size >= need { best = min(best, cost); return }
                if i == offs.count { return }
                let maxK = (need + offs[i].packBase - 1) / offs[i].packBase + 1
                for k in 0...maxK { rec(i + 1, size + k * offs[i].packBase, cost + k * offs[i].price.kopecks) }
            }
            rec(0, 0, 0)
            XCTAssertEqual(c.cost(need: need), best, "need=\(need) offers=\(offs.map { ($0.packBase, $0.price.kopecks) })")
            if let sel = c.select(need: need) { XCTAssertGreaterThanOrEqual(sel.totalSize, need); XCTAssertEqual(sel.totalCost, best) }
        }
    }

    func testLargeNeedUsesBestRatio() {
        let c = PackCover(offers: [offer("s", 500, 90), offer("b", 5000, 700)])
        // 100 кг: лучшая упаковка 5 кг по 700 ₽ → 20 шт = 14000 ₽
        XCTAssertEqual(c.cost(need: 100_000), 1_400_000)
        let sel = c.select(need: 100_000)!
        XCTAssertGreaterThanOrEqual(sel.totalSize, 100_000)
        XCTAssertEqual(sel.totalCost, 1_400_000)
    }

    func testCrossStoreCheapestPack() {
        let c = PackCover(offers: [offer("a", 900, 130, store: "A"), offer("b", 900, 115, store: "B"), offer("c", 900, 145, store: "C")])
        XCTAssertEqual(c.cost(need: 1000), 23000)
        XCTAssertEqual(c.select(need: 1000)?.packs.first?.pack.storeID, "B")
    }

    func testNoOffers() {
        let c = PackCover(offers: [])
        XCTAssertGreaterThanOrEqual(c.cost(need: 10), PackCover.infinity)
        XCTAssertEqual(c.cost(need: 0), 0)
        XCTAssertNil(c.select(need: 10))
    }
}

final class AllergenTests: XCTestCase {
    let lib = Fixtures.lib
    func product(_ name: String, text: String? = nil, tags: [String] = [], traces: [String] = []) -> CatalogProduct {
        CatalogProduct(id: "x", storeID: "s", name: name, price: .rub(100), ingredientsText: text, allergenTags: tags, traceTags: traces, quality: .imported, source: "t")
    }
    func testPeanutInComposition() {
        let p = product("Печенье овсяное", text: "Мука пшеничная, сахар, арахис, масло")
        XCTAssertEqual(AllergenChecker.evaluate(product: p, ingredient: nil, allergens: [.peanuts]), .contains([.peanuts]))
    }
    func testTracesAreBlocked() {
        let p = product("Рис 900 г", text: "рис. Может содержать следы арахиса.")
        if case .mayContain = AllergenChecker.evaluate(product: p, ingredient: lib.ingredients["rice"], allergens: [.peanuts]) {} else { XCTFail("следы должны блокироваться") }
        let p2 = product("Рис 900 г", text: "рис", traces: ["en:peanuts"])
        if case .mayContain = AllergenChecker.evaluate(product: p2, ingredient: lib.ingredients["rice"], allergens: [.peanuts]) {} else { XCTFail() }
        // без избегания следов — допускается
        XCTAssertEqual(AllergenChecker.evaluate(product: p2, ingredient: lib.ingredients["rice"], allergens: [.peanuts], avoidTraces: false), .safe)
    }
    func testUnknownCompositionForProcessedFood() {
        let p = product("Кукуруза консервированная 340 г")
        XCTAssertEqual(AllergenChecker.evaluate(product: p, ingredient: lib.ingredients["canned_corn"], allergens: [.peanuts]), .unknown)
        // сырые овощи без состава — допустимо
        XCTAssertEqual(AllergenChecker.evaluate(product: product("Морковь 1 кг"), ingredient: lib.ingredients["carrot"], allergens: [.peanuts]), .safe)
    }
    func testWheatVsGluten() {
        let oats = lib.ingredients["oats"]!, pasta = lib.ingredients["pasta"]!
        XCTAssertTrue(AllergenChecker.ingredientContains(oats, [.wheat]).isEmpty)
        XCTAssertFalse(AllergenChecker.ingredientContains(oats, [.gluten]).isEmpty)
        XCTAssertFalse(AllergenChecker.ingredientContains(pasta, [.wheat]).isEmpty)
        XCTAssertFalse(AllergenChecker.ingredientContains(pasta, [.gluten]).isEmpty)
    }
    func testCustomAllergen() {
        let kiwi = Allergen.custom("Киви")
        let p = product("Йогурт", text: "молоко, киви, сахар")
        XCTAssertEqual(AllergenChecker.evaluate(product: p, ingredient: nil, allergens: [kiwi]), .contains([kiwi]))
    }
    func testOFFTags() {
        let p = product("Что-то", text: "ингредиенты", tags: ["en:milk"])
        XCTAssertEqual(AllergenChecker.evaluate(product: p, ingredient: nil, allergens: [.milk]), .contains([.milk]))
    }
    func testOfferBuilderRejectsAllergenProducts() {
        let nuts = CatalogProduct(id: "1", storeID: "s", name: "Арахисовая паста 340 г", quantityText: "340 г", price: .rub(250), ingredientsText: "арахис 100%", quality: .imported, source: "t")
        let r = OfferBuilder(library: lib, allergens: [.peanuts]).build(from: [nuts])
        XCTAssertTrue(r.offers.isEmpty)
        XCTAssertEqual(r.rejected.count, 1)
    }
    func testOfferBuilderUnknownPolicy() {
        let corn = CatalogProduct(id: "1", storeID: "s", name: "Кукуруза консервированная 340 г", price: .rub(110), quality: .imported, source: "t")
        XCTAssertEqual(OfferBuilder(library: lib, allergens: [.peanuts], policy: .allowWithWarning).build(from: [corn]).offers.first?.warning != nil, true)
        XCTAssertTrue(OfferBuilder(library: lib, allergens: [.peanuts], policy: .exclude).build(from: [corn]).offers.isEmpty)
    }
    func testOfferBuilderMissingPriceStockSize() {
        let a = CatalogProduct(id: "a", storeID: "s", name: "Рис 900 г", price: .zero, quality: .imported, source: "t")
        let b = CatalogProduct(id: "b", storeID: "s", name: "Рис 900 г", price: .rub(100), inStock: false, quality: .imported, source: "t")
        let c = CatalogProduct(id: "c", storeID: "s", name: "Рис", price: .rub(100), quality: .imported, source: "t")
        let r = OfferBuilder(library: lib).build(from: [a, b, c])
        XCTAssertTrue(r.offers.isEmpty)
        XCTAssertEqual(r.rejected.count, 3)
    }
    func testPromoPriceIsEffective() {
        let p = CatalogProduct(id: "p", storeID: "s", name: "Рис 900 г", price: .rub(130), promoPrice: .rub(99), quality: .official, source: "t")
        let o = OfferBuilder(library: lib).build(from: [p]).offers.first!
        XCTAssertEqual(o.price, .rub(99)); XCTAssertEqual(o.regularPrice, .rub(130)); XCTAssertTrue(o.isPromo)
    }
    func testStaleCrowdPricesRejected() {
        let old = Date().addingTimeInterval(-400 * 86400)
        let p = CatalogProduct(id: "p", storeID: "s", name: "Рис 900 г", price: .rub(130), priceDate: old, quality: .crowdsourced, source: "t")
        XCTAssertTrue(OfferBuilder(library: lib, maxPriceAgeDays: 180).build(from: [p]).offers.isEmpty)
    }
}

final class LibraryTests: XCTestCase {
    let lib = Fixtures.lib
    func testLibraryIntegrity() {
        XCTAssertGreaterThanOrEqual(lib.recipes.count, 40)
        for r in lib.recipes {
            XCTAssertFalse(r.methods.isEmpty, r.id)
            XCTAssertFalse(r.meals.isEmpty, r.id)
            for ri in r.ingredients { XCTAssertNotNil(lib.ingredients[ri.key], "\(r.id): \(ri.key)"); XCTAssertGreaterThan(ri.amount, 0) }
            for m in r.methods { XCTAssertGreaterThanOrEqual(m.steps.count, 2, "\(r.id)/\(m.id)") }
            let n = lib.nutritionPerServing(r)
            XCTAssertTrue(n.kcal > 90 && n.kcal < 1000, "\(r.id) kcal=\(n.kcal)")
        }
    }
    func testEveryMealTypeHasRecipes() {
        for t in MealType.allCases { XCTAssertGreaterThan(lib.recipes.filter { $0.meals.contains(t) }.count, 3, t.rawValue) }
    }
    func testRecipePlaceholdersResolve() throws {
        for r in lib.recipes { for m in r.methods { for s in m.steps {
            let rendered = RecipeRenderer.renderText(s.text, recipe: r, servings: 4, library: lib)
            XCTAssertFalse(rendered.contains("{{"), "\(r.id): \(s.text)")
        } } }
    }
    func testAllergenFlagsCoverKnownCases() {
        XCTAssertTrue(lib.ingredients["peanut_butter"]!.allergens.contains("peanuts"))
        XCTAssertTrue(lib.ingredients["shrimp"]!.allergens.contains("shellfish"))
        XCTAssertTrue(lib.ingredients["egg"]!.allergens.contains("eggs"))
    }
}

final class KitchenTests: XCTestCase {
    let lib = Fixtures.lib
    func testNoOvenUsesStoveAlternative() {
        let r = lib.recipeIndex["chicken_potato_oven"]!
        var k = Fixtures.fullKitchen
        XCTAssertEqual(k.bestMethod(for: r, servings: 2)?.0.id, "oven")
        k.equipment.remove("oven")
        XCTAssertEqual(k.bestMethod(for: r, servings: 2)?.0.id, "stove")
    }
    func testNoHeatSourceMeansNoRecipe() {
        let r = lib.recipeIndex["borscht"]!
        let k = Kitchen(equipment: [], cookware: [Cookware(kind: "pot"), Cookware(kind: "knife"), Cookware(kind: "cutting_board")])
        XCTAssertNil(k.bestMethod(for: r, servings: 2))
    }
    func testPotCapacityLimit() {
        let r = lib.recipeIndex["borscht"]!   // 450 мл на порцию
        let small = Kitchen(equipment: ["gas_stove"], cookware: [Cookware(kind: "pot", volumeMl: 3000), Cookware(kind: "knife"), Cookware(kind: "cutting_board")])
        // 8 порций × 450 мл = 3.6 л при полезном объёме 2.25 л → 2 подхода
        XCTAssertEqual(small.bestMethod(for: r, servings: 8)?.1, 2)
        // 40 порций = 18 л → невозможно (больше 3 подходов)
        XCTAssertNil(small.bestMethod(for: r, servings: 40))
        // «8 литров супа в кастрюле 3 литра» не предлагается одним подходом
        XCTAssertNotEqual(small.bestMethod(for: r, servings: 17.8)?.1, 1)
    }
    func testMicrowaveOnlyRecipe() {
        let r = lib.recipeIndex["oat_milk_porridge"]!
        let k = Kitchen(equipment: ["microwave"], cookware: [Cookware(kind: "bowl"), Cookware(kind: "knife"), Cookware(kind: "cutting_board")])
        XCTAssertEqual(k.bestMethod(for: r, servings: 2)?.0.id, "microwave")
    }
}

final class FormatTests: XCTestCase {
    func testHousehold() {
        let lib = Fixtures.lib
        XCTAssertEqual(Fmt.household(grams: 3, info: lib.ingredients["salt"]!), "≈ ½ ч. л.")
        XCTAssertEqual(Fmt.household(grams: 9, info: lib.ingredients["sunflower_oil"]!), "≈ 2 ч. л.")
        XCTAssertEqual(Fmt.household(grams: 28, info: lib.ingredients["tomato_paste"]!), "≈ 1 ст. л.")
        XCTAssertNil(Fmt.household(grams: 300, info: lib.ingredients["chicken_breast"]!))
    }
    func testAmountFormatting() {
        XCTAssertEqual(Fmt.amount(1500, unit: .g), "1,5 кг")
        XCTAssertEqual(Fmt.amount(800, unit: .g), "800 г")
        XCTAssertEqual(Fmt.amount(930, unit: .ml), "930 мл")
        XCTAssertEqual(Fmt.amount(10, unit: .pcs), "10 шт")
    }
}
