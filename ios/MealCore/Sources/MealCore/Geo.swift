import Foundation

public enum Geo {
    /// Расстояние по большому кругу, метры.
    public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

public enum SearchRadius {
    /// Предустановленные радиусы поиска, метры.
    public static let presets: [Double] = [500, 1000, 3000, 5000, 10_000, 20_000, 50_000]
    public static func title(_ m: Double) -> String { m < 1000 ? "\(Int(m)) м" : "\(Fmt.number(m / 1000)) км" }

    /// Автоматическое расширение: следующий радиус из лестницы, пока найдено меньше `minStores` магазинов.
    public static func next(after current: Double, found: Int, minStores: Int = 3, max maxRadius: Double = 50_000) -> Double? {
        guard found < minStores else { return nil }
        if let n = presets.first(where: { $0 > current + 1 && $0 <= maxRadius }) { return n }
        return nil
    }
}

/// Нормализация и объединение магазинов из разных источников (MapKit, OSM, ручной ввод). Список сетей НЕ ограничивает поиск —
/// он нужен только для единообразных названий и фильтра по сети.
public enum StoreDirectory {
    static let chainAliases: [(canonical: String, stems: [String])] = [
        ("Пятёрочка", ["пятерочк", "pyaterochka", "5ka"]), ("Магнит", ["магнит", "magnit"]), ("Лента", ["лента", "lenta"]),
        ("Перекрёсток", ["перекресток", "perekrestok"]), ("Ашан", ["ашан", "auchan"]), ("Дикси", ["дикси", "dixy"]),
        ("ВкусВилл", ["вкусвилл", "vkusvill"]), ("О’КЕЙ", ["окей", "okey", "o key"]), ("METRO", ["metro", "метро кэш", "метро c&c"]),
        ("Spar", ["spar", "спар"]), ("Верный", ["верный"]), ("Азбука вкуса", ["азбука вкуса"]), ("Fix Price", ["fix price", "фикс прайс"]),
        ("Светофор", ["светофор"]), ("Монетка", ["монетка"]), ("Бристоль", ["бристоль"]), ("Красное&Белое", ["красное белое", "красное и белое"]),
    ]

    /// Название сети по названию магазина (если известна); иначе nil. Неизвестные магазины остаются полноправными.
    public static func chain(forName name: String) -> String? {
        let n = TextNorm.normalize(name)
        for c in chainAliases where c.stems.contains(where: { n.contains($0) }) { return c.canonical }
        return nil
    }

    public static func shopType(forName name: String, hint: String? = nil) -> String {
        let n = TextNorm.normalize(name + " " + (hint ?? ""))
        if ["рынок", "market", "базар"].contains(where: { n.contains($0) }) { return "marketplace" }
        if ["овощ", "фрукт", "greengrocer"].contains(where: { n.contains($0) }) { return "greengrocer" }
        if ["мясн", "butcher", "колбас"].contains(where: { n.contains($0) }) { return "butcher" }
        if ["пекарн", "хлеб", "булочн", "bakery"].contains(where: { n.contains($0) }) { return "bakery" }
        if ["гипермаркет", "супермаркет", "supermarket", "hypermarket"].contains(where: { n.contains($0) }) { return "supermarket" }
        if ["магазин", "продукт", "минимаркет", "convenience", "mini"].contains(where: { n.contains($0) }) { return "convenience" }
        return "supermarket"
    }

    /// Объединение источников: одинаковые магазины (похожее название и ≤ 80 м) склеиваются, берутся более полные данные.
    public static func merge(_ lists: [[StoreInfo]], origin: (lat: Double, lon: Double)) -> [StoreInfo] {
        var out: [StoreInfo] = []
        for list in lists {
            for var s in list {
                s.distanceM = Geo.distance(lat1: origin.lat, lon1: origin.lon, lat2: s.lat, lon2: s.lon)
                if s.chain == nil { s.chain = chain(forName: s.name) }
                if let i = out.firstIndex(where: { similar($0, s) }) {
                    out[i] = richer(out[i], s)
                } else { out.append(s) }
            }
        }
        return out.sorted { $0.distanceM < $1.distanceM }
    }

    static func similar(_ a: StoreInfo, _ b: StoreInfo) -> Bool {
        let d = Geo.distance(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
        if d > 80 { return false }
        let na = TextNorm.normalize(a.name), nb = TextNorm.normalize(b.name)
        if na == nb || na.contains(nb) || nb.contains(na) { return true }
        if let ca = a.chain ?? chain(forName: a.name), let cb = b.chain ?? chain(forName: b.name), ca == cb { return true }
        return false
    }

    static func richer(_ a: StoreInfo, _ b: StoreInfo) -> StoreInfo {
        var r = a
        if (r.address ?? "").isEmpty { r.address = b.address }
        if r.openingHours == nil { r.openingHours = b.openingHours }
        if r.delivery == nil { r.delivery = b.delivery }
        if r.chain == nil { r.chain = b.chain }
        if r.catalog == .unknown || r.catalog == .unavailable { r.catalog = b.catalog }
        if b.source == "osm" && a.source != "osm" { r.id = a.id }   // стабильный id — от первого источника
        return r
    }

    public struct Filter: Sendable {
        public var maxDistanceM: Double?
        public var chains: Set<String>
        public var types: Set<String>
        public var onlyWithCatalog: Bool
        public var onlyWithFreshPrices: Bool
        public var onlyDelivery: Bool
        public init(maxDistanceM: Double? = nil, chains: Set<String> = [], types: Set<String> = [], onlyWithCatalog: Bool = false, onlyWithFreshPrices: Bool = false, onlyDelivery: Bool = false) {
            self.maxDistanceM = maxDistanceM; self.chains = chains; self.types = types; self.onlyWithCatalog = onlyWithCatalog; self.onlyWithFreshPrices = onlyWithFreshPrices; self.onlyDelivery = onlyDelivery
        }
    }

    public static func apply(_ f: Filter, to stores: [StoreInfo], now: Date = Date()) -> [StoreInfo] {
        stores.filter { s in
            if let m = f.maxDistanceM, s.distanceM > m { return false }
            if !f.chains.isEmpty, !f.chains.contains(s.chain ?? s.name) { return false }
            if !f.types.isEmpty, !f.types.contains(s.shopType) { return false }
            if f.onlyWithCatalog, s.catalog == .unknown || s.catalog == .unavailable { return false }
            if f.onlyWithFreshPrices { guard let d = s.priceUpdatedAt, now.timeIntervalSince(d) < 30 * 86400 else { return false } }
            if f.onlyDelivery, s.delivery != true { return false }
            return true
        }
    }
}
