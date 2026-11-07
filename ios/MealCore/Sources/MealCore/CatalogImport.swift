import Foundation

/// Импорт каталога магазина из CSV/JSON (разрешённый пользователем источник).
/// Колонки (любой регистр, ru/en): name|название, price|цена, quantity|вес|объём|размер, brand|бренд, category|категория, url|ссылка, image|фото,
/// promo_price|акция|цена по акции, in_stock|наличие, ingredients|состав, allergens|аллергены, date|дата, sku|артикул.
public enum CatalogImport {
    public struct Result: Sendable {
        public var products: [CatalogProduct] = []
        public var errors: [String] = []
    }

    static let aliases: [String: [String]] = [
        "name": ["name", "название", "наименование", "товар", "title"],
        "price": ["price", "цена", "стоимость"],
        "qty": ["quantity", "qty", "вес", "объем", "размер", "фасовка", "weight", "size"],
        "brand": ["brand", "бренд", "производитель"],
        "category": ["category", "категория"],
        "url": ["url", "ссылка", "link"],
        "image": ["image", "image_url", "фото", "картинка"],
        "promo": ["promo_price", "promo", "акция", "цена по акции", "sale_price"],
        "stock": ["in_stock", "stock", "наличие", "available"],
        "ingredients": ["ingredients", "состав"],
        "allergens": ["allergens", "аллергены"],
        "date": ["date", "дата", "updated", "обновлено"],
        "sku": ["sku", "артикул", "id", "код"],
    ]

    public static func parseCSV(_ text: String, storeID: String, source: String = "csv-import", now: Date = Date()) -> Result {
        var res = Result()
        let rows = splitCSV(text)
        guard let header = rows.first, rows.count > 1 else { res.errors.append("Файл пуст или не содержит строк с данными."); return res }
        var col: [String: Int] = [:]
        for (i, h) in header.enumerated() {
            let n = TextNorm.normalize(h)
            for (field, names) in aliases where names.contains(where: { TextNorm.normalize($0) == n }) { col[field] = i }
        }
        guard col["name"] != nil, col["price"] != nil else {
            res.errors.append("Не найдены обязательные колонки «название» и «цена». Найдено: \(header.joined(separator: ", "))"); return res
        }
        for (ri, row) in rows.enumerated().dropFirst() {
            func f(_ k: String) -> String? { col[k].flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil }.flatMap { $0.isEmpty ? nil : $0 } }
            guard let name = f("name") else { res.errors.append("Строка \(ri + 1): нет названия"); continue }
            guard let price = parsePrice(f("price")) else { res.errors.append("Строка \(ri + 1) («\(name)»): не удалось прочитать цену «\(f("price") ?? "")»"); continue }
            let sku = f("sku") ?? String(abs(name.hashValueStable))
            res.products.append(CatalogProduct(id: "\(storeID):\(sku)", storeID: storeID, name: name, brand: f("brand"), category: f("category"), imageURL: f("image"), url: f("url"),
                                               quantityText: f("qty"), price: price, promoPrice: parsePrice(f("promo")), inStock: parseBool(f("stock")),
                                               ingredientsText: f("ingredients"), allergenTags: (f("allergens") ?? "").split(whereSeparator: { ",;".contains($0) }).map { String($0).trimmingCharacters(in: .whitespaces) },
                                               priceDate: parseDate(f("date")) ?? now, quality: .imported, source: source))
        }
        return res
    }

    public static func parseJSON(_ data: Data, storeID: String, source: String = "json-import", now: Date = Date()) -> Result {
        var res = Result()
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { res.errors.append("Некорректный JSON."); return res }
        var items: [[String: Any]] = []
        if let a = obj as? [[String: Any]] { items = a }
        else if let d = obj as? [String: Any], let a = (d["products"] ?? d["items"]) as? [[String: Any]] { items = a }
        else { res.errors.append("Ожидается массив товаров или объект с полем products."); return res }
        for (i, it) in items.enumerated() {
            func s(_ k: String) -> String? {
                for n in aliases[k] ?? [] { if let v = it.first(where: { TextNorm.normalize($0.key) == TextNorm.normalize(n) })?.value {
                    if let str = v as? String, !str.isEmpty { return str }
                    if let num = v as? NSNumber { return num.stringValue }
                } }
                return nil
            }
            guard let name = s("name") else { res.errors.append("Элемент \(i + 1): нет названия"); continue }
            guard let price = parsePrice(s("price")) else { res.errors.append("Элемент \(i + 1) («\(name)»): нет корректной цены"); continue }
            let sku = s("sku") ?? String(abs(name.hashValueStable))
            let allergens = (s("allergens") ?? "").split(whereSeparator: { ",;".contains($0) }).map { String($0).trimmingCharacters(in: .whitespaces) }
            res.products.append(CatalogProduct(id: "\(storeID):\(sku)", storeID: storeID, name: name, brand: s("brand"), category: s("category"), imageURL: s("image"), url: s("url"),
                                               quantityText: s("qty"), price: price, promoPrice: parsePrice(s("promo")), inStock: parseBool(s("stock")),
                                               ingredientsText: s("ingredients"), allergenTags: allergens, priceDate: parseDate(s("date")) ?? now, quality: .imported, source: source))
        }
        return res
    }

    static func parsePrice(_ s: String?) -> Money? {
        guard var t = s?.lowercased() else { return nil }
        t = t.replacingOccurrences(of: "₽", with: "").replacingOccurrences(of: "руб", with: "").replacingOccurrences(of: "р.", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v > 0, v < 10_000_000 else { return nil }
        return Money.rub(v)
    }
    static func parseBool(_ s: String?) -> Bool? {
        guard let t = s?.lowercased() else { return nil }
        if ["1", "true", "да", "yes", "есть", "в наличии"].contains(t) { return true }
        if ["0", "false", "нет", "no", "нет в наличии"].contains(t) { return false }
        return nil
    }
    static func parseDate(_ s: String?) -> Date? {
        guard let t = s else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: t) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd", "dd.MM.yyyy"] { f.dateFormat = fmt; if let d = f.date(from: t) { return d } }
        return nil
    }

    /// Разбор CSV с кавычками; разделитель определяется автоматически (`;`, `,` или таб).
    static func splitCSV(_ text: String) -> [[String]] {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        var delim: Character = ","
        var bestCount = -1
        for cand in [";", ",", "\t"] as [Character] {
            let n = firstLine.filter { $0 == cand }.count
            if n > bestCount { bestCount = n; delim = cand }
        }
        var rows: [[String]] = [], row: [String] = [], field = "", inQuotes = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" { if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false } }
                else { field.append(c) }
            } else if c == "\"" { inQuotes = true }
            else if c == delim { row.append(field); field = "" }
            else if c == "\n" { row.append(field); field = ""; if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }; row = [] }
            else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        if let f = rows.first?.first, f.hasPrefix("\u{FEFF}") { rows[0][0] = String(f.dropFirst()) }
        return rows
    }
}

extension String {
    /// Стабильный (не зависящий от запуска) хэш для идентификаторов.
    var hashValueStable: Int {
        var h: UInt64 = 1469598103934665603
        for b in self.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(truncatingIfNeeded: h >> 2)
    }
}

/// Цены, введённые пользователем вручную (по товару или по ингредиенту).
public struct UserPrice: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var ingredientKey: String
    public var productName: String
    public var packSize: Double          // в базовых единицах ингредиента
    public var price: Money
    public var storeID: String           // реальный магазин или "user"
    public var date: Date
    public init(id: UUID = UUID(), ingredientKey: String, productName: String, packSize: Double, price: Money, storeID: String = "user", date: Date = Date()) {
        self.id = id; self.ingredientKey = ingredientKey; self.productName = productName; self.packSize = packSize; self.price = price; self.storeID = storeID; self.date = date
    }
    public func toProduct(library: Library) -> CatalogProduct? {
        guard let info = library.ingredients[ingredientKey] else { return nil }
        return CatalogProduct(id: "user:\(id.uuidString)", storeID: storeID, name: productName, quantityText: nil, packSize: packSize, packUnit: info.unit, price: price,
                              ingredientsText: nil, priceDate: date, quality: .userEntered, source: "manual", ingredientHint: ingredientKey)
    }
}
