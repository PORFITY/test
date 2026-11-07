import Foundation

/// Откуда взята цена. От этого зависит доверие и отображение в интерфейсе.
public enum PriceQuality: String, Codable, Sendable, CaseIterable {
    case official       // официальный API/прайс магазина
    case imported       // загруженный пользователем/партнёром каталог (CSV/JSON)
    case userEntered    // введено пользователем вручную
    case crowdsourced   // краудсорсинг (Open Prices) — реальный ценник, но может устареть
    case estimate       // ориентир приложения, НЕ данные магазина

    public var isReal: Bool { self != .estimate }
    public var title: String {
        switch self {
        case .official: return "Цена магазина"
        case .imported: return "Из загруженного каталога"
        case .userEntered: return "Введено вручную"
        case .crowdsourced: return "Цена с чека (Open Prices)"
        case .estimate: return "Ориентир, не данные магазина"
        }
    }
}

public enum CatalogAvailability: String, Codable, Sendable {
    case unknown, unavailable, crowdsourced, imported, official
    public var title: String {
        switch self {
        case .unknown: return "Каталог не проверен"
        case .unavailable: return "Нет каталога"
        case .crowdsourced: return "Есть цены с чеков"
        case .imported: return "Загруженный каталог"
        case .official: return "Официальный каталог"
        }
    }
}

public struct StoreInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var chain: String?
    public var address: String?
    public var lat: Double
    public var lon: Double
    public var distanceM: Double
    public var shopType: String          // supermarket, convenience, greengrocer, butcher, bakery, marketplace, other
    public var openingHours: String?
    public var delivery: Bool?
    public var catalog: CatalogAvailability
    public var priceUpdatedAt: Date?
    public var source: String            // mapkit | osm | manual
    public init(id: String, name: String, chain: String? = nil, address: String? = nil, lat: Double, lon: Double, distanceM: Double = 0, shopType: String = "supermarket", openingHours: String? = nil, delivery: Bool? = nil, catalog: CatalogAvailability = .unknown, priceUpdatedAt: Date? = nil, source: String = "manual") {
        self.id = id; self.name = name; self.chain = chain; self.address = address; self.lat = lat; self.lon = lon; self.distanceM = distanceM
        self.shopType = shopType; self.openingHours = openingHours; self.delivery = delivery; self.catalog = catalog; self.priceUpdatedAt = priceUpdatedAt; self.source = source
    }
    public var distanceText: String {
        distanceM < 1000 ? "\(Int(distanceM.rounded())) м" : String(format: "%.1f км", distanceM / 1000).replacingOccurrences(of: ".", with: ",")
    }
}

/// Товар магазина в едином формате (адаптеры приводят к нему данные любых источников).
public struct CatalogProduct: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var storeID: String
    public var name: String
    public var brand: String?
    public var category: String?
    public var imageURL: String?
    public var url: String?
    public var quantityText: String?
    public var packSize: Double?
    public var packUnit: BaseUnit?
    public var price: Money
    public var promoPrice: Money?
    public var discountText: String?
    public var inStock: Bool?
    public var ingredientsText: String?
    public var allergenTags: [String]
    public var traceTags: [String]
    public var nutritionPer100: Nutrition?
    public var priceDate: Date?
    public var quality: PriceQuality
    public var source: String
    public var outletNote: String?
    public var ingredientHint: String?

    public init(id: String, storeID: String, name: String, brand: String? = nil, category: String? = nil, imageURL: String? = nil, url: String? = nil, quantityText: String? = nil, packSize: Double? = nil, packUnit: BaseUnit? = nil, price: Money, promoPrice: Money? = nil, discountText: String? = nil, inStock: Bool? = nil, ingredientsText: String? = nil, allergenTags: [String] = [], traceTags: [String] = [], nutritionPer100: Nutrition? = nil, priceDate: Date? = nil, quality: PriceQuality, source: String, outletNote: String? = nil, ingredientHint: String? = nil) {
        self.id = id; self.storeID = storeID; self.name = name; self.brand = brand; self.category = category; self.imageURL = imageURL; self.url = url
        self.quantityText = quantityText; self.packSize = packSize; self.packUnit = packUnit; self.price = price; self.promoPrice = promoPrice
        self.discountText = discountText; self.inStock = inStock; self.ingredientsText = ingredientsText; self.allergenTags = allergenTags
        self.traceTags = traceTags; self.nutritionPer100 = nutritionPer100; self.priceDate = priceDate; self.quality = quality; self.source = source
        self.outletNote = outletNote; self.ingredientHint = ingredientHint
    }

    public var effectivePrice: Money {
        if let p = promoPrice, p.kopecks > 0, p < price { return p }
        return price
    }
    public var isPromo: Bool { effectivePrice < price }
}

// MARK: - Разбор размера упаковки

public enum PackageSizeParser {
    public struct Size: Equatable, Sendable { public let value: Double; public let unit: BaseUnit }

    /// «900 г», «0,9 кг», «1.5 л», «10 шт», «5x80 г» → (граммы/мл/штуки).
    public static func parse(_ text: String) -> Size? {
        let s = text.lowercased().replacingOccurrences(of: "ё", with: "е").replacingOccurrences(of: ",", with: ".")
        let unitPat = "(кг|kg|гр|г|g|мл|ml|л|l|шт|pcs|pc)"
        // мультипак: 5x80 г / 5 х 80 г
        let multi = try? NSRegularExpression(pattern: "(\\d+)\\s*[x×х*]\\s*(\\d+(?:\\.\\d+)?)\\s*" + unitPat + "(?![\\p{L}])", options: [])
        let single = try? NSRegularExpression(pattern: "(?<![\\d.])(\\d+(?:\\.\\d+)?)\\s*" + unitPat + "(?![\\p{L}])", options: [])
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = multi?.matches(in: s, options: [], range: full).last {
            let n = Double(ns.substring(with: m.range(at: 1))) ?? 1
            let v = Double(ns.substring(with: m.range(at: 2))) ?? 0
            let u = ns.substring(with: m.range(at: 3))
            if let sz = make(v * n, u) { return sz }
        }
        if let m = single?.matches(in: s, options: [], range: full).last {
            let v = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let u = ns.substring(with: m.range(at: 2))
            return make(v, u)
        }
        return nil
    }

    private static func make(_ v: Double, _ u: String) -> Size? {
        guard v > 0 else { return nil }
        switch u {
        case "кг", "kg": return Size(value: v * 1000, unit: .g)
        case "г", "гр", "g": return Size(value: v, unit: .g)
        case "л", "l": return Size(value: v * 1000, unit: .ml)
        case "мл", "ml": return Size(value: v, unit: .ml)
        case "шт", "pcs", "pc": return Size(value: v, unit: .pcs)
        default: return nil
        }
    }

    /// Перевод размера упаковки в базовую единицу ингредиента (г/мл/шт), с учётом плотности и массы штуки.
    public static func toBase(_ size: Size, for ing: IngredientInfo) -> Int? {
        let amount: Double?
        switch (size.unit, ing.unit) {
        case (.g, .g), (.ml, .ml), (.pcs, .pcs): amount = size.value
        case (.ml, .g): amount = size.value * (ing.dens ?? 1)
        case (.g, .ml): amount = size.value / (ing.dens ?? 1)
        case (.g, .pcs): amount = ing.pcsG.map { size.value / $0 }
        case (.pcs, .g): amount = ing.pcsG.map { size.value * $0 }
        default: amount = nil
        }
        guard let a = amount, a >= 1 else { return nil }
        return Int(a.rounded())
    }
}

// MARK: - Сопоставление товара и ингредиента

public struct ProductMatcher: Sendable {
    public let library: Library
    static let globalExclusions = ["корм для", "для животных", "для собак", "для кошек", "детское питание", "детск пюре", "стиральн", "для посуды", "освежител"]

    public init(library: Library) { self.library = library }

    public func match(name: String, hint: String? = nil) -> String? {
        let norm = " " + TextNorm.normalize(name) + " "
        for g in Self.globalExclusions where norm.contains(" " + g) { return nil }
        if let h = hint, let info = library.ingredients[h], !isExcluded(norm, info) { return h }
        var best: (key: String, score: Int)?
        for info in library.ingredientList {
            if isExcluded(norm, info) { continue }
            for raw in info.kw {
                var kw = TextNorm.normalize(raw.replacingOccurrences(of: "=", with: ""))
                if kw.isEmpty { continue }
                let exact = raw.hasSuffix("=")
                kw = kw.trimmingCharacters(in: .whitespaces)
                let ok = exact ? norm.contains(" " + kw + " ") : norm.contains(" " + kw)
                if ok {
                    let score = kw.count + (exact ? 1 : 0)
                    if best == nil || score > best!.score { best = (info.key, score) }
                }
            }
        }
        return best?.key
    }

    private func isExcluded(_ norm: String, _ info: IngredientInfo) -> Bool {
        for raw in info.ex {
            let e = TextNorm.normalize(raw)
            if !e.isEmpty && norm.contains(" " + e) { return true }
        }
        return false
    }
}

// MARK: - Предложения (оферы)

public struct Offer: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var storeID: String
    public var ingredientKey: String
    public var packBase: Int            // размер упаковки в базовых единицах ингредиента
    public var price: Money             // цена упаковки (с учётом акции)
    public var regularPrice: Money
    public var name: String
    public var brand: String?
    public var imageURL: String?
    public var url: String?
    public var quality: PriceQuality
    public var priceDate: Date?
    public var source: String
    public var promoText: String?
    public var outletNote: String?
    public var compositionConfirmed: Bool
    public var warning: String?

    public var isPromo: Bool { price < regularPrice }
    public var unitPrice: Double { Double(price.kopecks) / Double(max(1, packBase)) }
}

public struct RejectedProduct: Sendable {
    public enum Reason: Sendable { case unmatched, noPackSize, noPrice, outOfStock, stale, allergen([Allergen]), unknownComposition }
    public let product: CatalogProduct
    public let reason: Reason
}

public struct OfferBuildResult: Sendable {
    public var offers: [Offer] = []
    public var rejected: [RejectedProduct] = []
}

public struct OfferBuilder: Sendable {
    public let library: Library
    public var allergens: Set<Allergen>
    public var policy: UnknownCompositionPolicy
    public var avoidTraces: Bool
    public var maxPriceAgeDays: Int?
    public var now: Date

    public init(library: Library, allergens: Set<Allergen> = [], policy: UnknownCompositionPolicy = .allowWithWarning, avoidTraces: Bool = true, maxPriceAgeDays: Int? = 180, now: Date = Date()) {
        self.library = library; self.allergens = allergens; self.policy = policy; self.avoidTraces = avoidTraces; self.maxPriceAgeDays = maxPriceAgeDays; self.now = now
    }

    public func build(from products: [CatalogProduct]) -> OfferBuildResult {
        let matcher = ProductMatcher(library: library)
        var out = OfferBuildResult()
        for p in products {
            guard p.price.kopecks > 0 else { out.rejected.append(.init(product: p, reason: .noPrice)); continue }
            if p.inStock == false { out.rejected.append(.init(product: p, reason: .outOfStock)); continue }
            guard let key = matcher.match(name: p.name, hint: p.ingredientHint), let info = library.ingredients[key] else {
                out.rejected.append(.init(product: p, reason: .unmatched)); continue
            }
            // размер упаковки
            var size: PackageSizeParser.Size?
            if let v = p.packSize, let u = p.packUnit { size = .init(value: v, unit: u) }
            else if let q = p.quantityText, let s = PackageSizeParser.parse(q) { size = s }
            else if let s = PackageSizeParser.parse(p.name) { size = s }
            guard let sz = size, let base = PackageSizeParser.toBase(sz, for: info) else {
                out.rejected.append(.init(product: p, reason: .noPackSize)); continue
            }
            if let maxAge = maxPriceAgeDays, let d = p.priceDate, p.quality == .crowdsourced {
                let days = Int(now.timeIntervalSince(d) / 86400)
                if days > maxAge { out.rejected.append(.init(product: p, reason: .stale)); continue }
            }
            // аллергены
            let verdict = AllergenChecker.evaluate(product: p, ingredient: info, allergens: allergens, avoidTraces: avoidTraces, policy: policy)
            var warning: String?
            var confirmed = true
            switch verdict {
            case .contains(let a): out.rejected.append(.init(product: p, reason: .allergen(a))); continue
            case .mayContain(let a): out.rejected.append(.init(product: p, reason: .allergen(a))); continue
            case .unknown:
                if policy == .exclude { out.rejected.append(.init(product: p, reason: .unknownComposition)); continue }
                warning = "Состав не подтверждён — проверьте упаковку на аллергены"
                confirmed = false
            case .safe:
                if allergens.isEmpty == false, (p.ingredientsText ?? "").isEmpty { confirmed = false }
            }
            out.offers.append(Offer(id: p.id, storeID: p.storeID, ingredientKey: key, packBase: base, price: p.effectivePrice, regularPrice: p.price,
                                    name: p.name, brand: p.brand, imageURL: p.imageURL, url: p.url, quality: p.quality, priceDate: p.priceDate,
                                    source: p.source, promoText: p.discountText, outletNote: p.outletNote, compositionConfirmed: confirmed, warning: warning))
        }
        return out
    }
}

// MARK: - Ориентировочные цены (режим «нет достоверных данных»)

/// Ориентиры для режима без данных магазинов. Это НЕ цены магазинов; всегда помечаются quality=.estimate.
public enum ReferencePrices {
    struct File: Codable { let items: [Entry] }
    struct Entry: Codable { let key: String; let packs: [[Double]] }  // [[размер в базовых ед., цена ₽]]

    public static let storeID = "estimate"

    /// Таблица ориентиров: ключ ингредиента → [(размер упаковки в базовых ед., цена ₽)].
    public static func entries() -> [(key: String, packs: [(size: Double, price: Double)])] {
        guard let url = Bundle.module.url(forResource: "reference_prices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.items.map { e in (e.key, e.packs.filter { $0.count == 2 }.map { (size: $0[0], price: $0[1]) }) }
    }

    public static func offers(library: Library, allergens: Set<Allergen> = []) -> [Offer] {
        guard let url = Bundle.module.url(forResource: "reference_prices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        var out: [Offer] = []
        for e in file.items {
            guard let info = library.ingredients[e.key] else { continue }
            if !AllergenChecker.ingredientContains(info, allergens).isEmpty { continue }
            for (i, p) in e.packs.enumerated() where p.count == 2 {
                let price = Money.rub(p[1])
                out.append(Offer(id: "estimate:\(e.key):\(i)", storeID: storeID, ingredientKey: e.key, packBase: Int(p[0]), price: price, regularPrice: price,
                                 name: "\(info.name), \(Fmt.amount(p[0], unit: info.unit)) (ориентир)", brand: nil, imageURL: nil, url: nil,
                                 quality: .estimate, priceDate: nil, source: "reference", promoText: nil, outletNote: "Средняя ориентировочная цена, не данные магазина",
                                 compositionConfirmed: false, warning: info.isProcessed ? "Ориентир: состав не проверен" : nil))
            }
        }
        return out
    }
}
