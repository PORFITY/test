import Foundation

public enum ShoppingExport {
    public static func groupedByStore(_ plan: MealPlan) -> [(store: String, day: Int, lines: [PurchaseLine])] {
        let names = Dictionary(plan.stores.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let groups = Dictionary(grouping: plan.purchases, by: { "\($0.purchaseDay)|\($0.storeID)" })
        return groups.map { (k, v) in
            let sid = v[0].storeID
            let title = sid == ReferencePrices.storeID ? "Ориентировочные цены (магазин не определён)" : sid == "user" ? "Мои цены" : (names[sid] ?? sid)
            return (title, v[0].purchaseDay, v.sorted { $0.ingredientName < $1.ingredientName })
        }.sorted { ($0.day, $0.store) < ($1.day, $1.store) }
    }

    public static func text(_ plan: MealPlan, startDate: Date? = nil) -> String {
        var out = "Список покупок — \(plan.title)\n"
        out += "Итого: \(plan.basketTotal) (бюджет \(plan.budget), остаток \(plan.remaining))\n"
        for g in groupedByStore(plan) {
            let sub = Money.sum(g.lines.map { $0.total })
            out += "\n● \(g.store) — день \(g.day + 1) — \(sub)\n"
            for l in g.lines {
                let mark = l.purchased ? "[x]" : "[ ]"
                out += "\(mark) \(l.ingredientName): \(l.productName) × \(l.packs) (\(Fmt.amount(Double(l.packBase), unit: l.unit))) — \(l.total)"
                if l.quality == .estimate { out += " (ориентир)" }
                out += "\n"
            }
        }
        return out
    }

    public static func csv(_ plan: MealPlan) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var out = "магазин;день;ингредиент;товар;упаковок;размер упаковки;цена за упаковку;сумма;источник цены\n"
        for g in groupedByStore(plan) {
            for l in g.lines {
                out += [q(g.store), "\(g.day + 1)", q(l.ingredientName), q(l.productName), "\(l.packs)", q(Fmt.amount(Double(l.packBase), unit: l.unit)),
                        String(format: "%.2f", l.unitPrice.rubles).replacingOccurrences(of: ".", with: ","), String(format: "%.2f", l.total.rubles).replacingOccurrences(of: ".", with: ","), q(l.quality.title)].joined(separator: ";") + "\n"
            }
        }
        return out
    }
}

public struct PlanStatistics: Sendable {
    public var totalCost: Money
    public var avgKcalPerDay: Double
    public var avgProtein: Double, avgFat: Double, avgCarbs: Double
    public var costByCategory: [(category: String, cost: Money)]
    public var costByStore: [(storeID: String, cost: Money)]
    public var savingsVsPriciest: Money
    public var cheapestDay: Int?, priciestDay: Int?

    public init(plan: MealPlan, library: Library, offers: [Offer]) {
        totalCost = plan.basketTotal
        let n = Double(max(1, plan.dayStats.count))
        avgKcalPerDay = plan.dayStats.map { $0.kcalReference }.reduce(0, +) / n
        avgProtein = plan.dayStats.map { $0.protein }.reduce(0, +) / n
        avgFat = plan.dayStats.map { $0.fat }.reduce(0, +) / n
        avgCarbs = plan.dayStats.map { $0.carbs }.reduce(0, +) / n
        var cat: [String: Int] = [:], st: [String: Int] = [:]
        var baseline = 0.0
        for p in plan.purchases {
            cat[library.ingredients[p.ingredientKey]?.cat ?? "other", default: 0] += p.total.kopecks
            st[p.storeID, default: 0] += p.total.kopecks
            let alt = offers.filter { $0.ingredientKey == p.ingredientKey && $0.quality != .estimate }.map { $0.unitPrice }.max() ?? 0
            baseline += max(alt * Double(p.packs * p.packBase), Double(p.total.kopecks))
        }
        costByCategory = cat.map { ($0.key, Money(kopecks: $0.value)) }.sorted { $0.cost > $1.cost }
        costByStore = st.map { ($0.key, Money(kopecks: $0.value)) }.sorted { $0.cost > $1.cost }
        savingsVsPriciest = Money(kopecks: max(0, Int(baseline.rounded()) - plan.basketTotal.kopecks))
        cheapestDay = plan.dayStats.min { $0.cost < $1.cost }?.day
        priciestDay = plan.dayStats.max { $0.cost < $1.cost }?.day
    }

    public static func categoryTitle(_ c: String) -> String {
        ["grain": "Крупы и макароны", "veg": "Овощи", "fruit": "Фрукты", "meat": "Мясо и птица", "fish": "Рыба и морепродукты", "dairy": "Молочные продукты", "egg": "Яйца",
         "bakery": "Хлеб", "canned": "Консервы", "oil": "Масло", "spice": "Специи и соль", "sweet": "Сладкое", "nuts": "Орехи", "sauce": "Соусы"][c] ?? "Другое"
    }
}

public struct SpendingSummary: Sendable {
    public var total: Money
    public var byMonth: [(month: String, amount: Money)]
    public var versusPlan: Money?
    public init(records: [PurchaseRecord], plan: MealPlan? = nil) {
        total = Money.sum(records.map { $0.amount })
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"
        var m: [String: Int] = [:]
        for r in records { m[f.string(from: r.date), default: 0] += r.amount.kopecks }
        byMonth = m.map { ($0.key, Money(kopecks: $0.value)) }.sorted { $0.month < $1.month }
        if let p = plan { let spent = Money.sum(records.filter { $0.planID == p.id }.map { $0.amount }); versusPlan = spent - p.basketTotal } else { versusPlan = nil }
    }
}
