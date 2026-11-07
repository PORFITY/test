import XCTest
@testable import MealCore

/// Проверка, что JSON backend читается моделями приложения (Codable) без потерь.
final class BackendContractTests: XCTestCase {
    var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    struct StoresResponse: Codable { var stores: [StoreInfo] }
    struct OffersResponse: Codable { var products: [CatalogProduct]; var notes: [String]? }

    func testStores() throws {
        let r = try decoder.decode(StoresResponse.self, from: Data(BackendFixtures.stores.utf8))
        XCTAssertEqual(r.stores.count, 3)
        XCTAssertEqual(r.stores.first { $0.chain == "Магнит" }?.openingHours, "08:00-23:00")
        XCTAssertNil(r.stores.first { $0.name.contains("лавка") }?.chain)
    }

    func testOffersBecomePlannerOffers() throws {
        let r = try decoder.decode(OffersResponse.self, from: Data(BackendFixtures.offers.utf8))
        XCTAssertFalse(r.products.isEmpty)
        XCTAssertTrue(r.products.allSatisfy { $0.quality == .crowdsourced && $0.priceDate != nil })
        let rice = try XCTUnwrap(r.products.first { $0.name.lowercased().contains("рис") })
        XCTAssertEqual(rice.price, .rub(149.90)); XCTAssertEqual(rice.promoPrice, .rub(129.50))
        XCTAssertEqual(rice.traceTags, ["en:peanuts"])
        XCTAssertEqual(rice.nutritionPer100?.kcal, 344)
        // следы арахиса у аллергика блокируют товар, без аллергии — товар доступен
        let lib = Library.shared
        XCTAssertTrue(OfferBuilder(library: lib, allergens: [.peanuts]).build(from: [rice]).offers.isEmpty)
        let ok = OfferBuilder(library: lib).build(from: [rice]).offers
        XCTAssertEqual(ok.first?.ingredientKey, "rice"); XCTAssertEqual(ok.first?.packBase, 900)
        XCTAssertEqual(ok.first?.price, .rub(129.50))   // акция учитывается как эффективная цена
    }

    func testIntent() throws {
        let i = try decoder.decode(AssistantIntent.self, from: Data(BackendFixtures.intent.utf8))
        XCTAssertEqual(i.action, .replaceMeal); XCTAssertEqual(i.day, 2); XCTAssertEqual(i.include, ["chicken_breast"])
    }
}
