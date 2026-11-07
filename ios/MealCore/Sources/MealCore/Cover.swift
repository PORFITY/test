import Foundation

/// Покупка целых упаковок. Решает задачу «минимальная стоимость, чтобы набрать не меньше N единиц».
/// Для небольших N — точный DP (неограниченный рюкзак), для больших — лучшая по цене за единицу упаковка + точный DP на остаток.
public struct PackCover: Sendable {
    public struct Pack: Hashable, Sendable {
        public let offerID: String
        public let storeID: String
        public let size: Int
        public let price: Int      // копейки
    }
    public struct Selection: Sendable {
        public var packs: [(pack: Pack, count: Int)]
        public var totalCost: Int
        public var totalSize: Int
    }

    public static let infinity = Int.max / 8

    public let packs: [Pack]
    private let limit: Int
    private var table: [Int]       // table[x] = min cost to cover >= x
    private var choice: [Int]      // индекс пачки (в packs) для x
    private let best: Pack?        // лучшая по цене за единицу

    public init(offers: [Offer]) {
        // убираем доминируемые: упаковка не меньше размером и не дороже
        var cand = offers.filter { $0.packBase > 0 && $0.price.kopecks > 0 }
            .map { Pack(offerID: $0.id, storeID: $0.storeID, size: $0.packBase, price: $0.price.kopecks) }
        cand.sort { ($0.size, $0.price) < ($1.size, $1.price) }
        var kept: [Pack] = []
        for p in cand.reversed() {   // от больших к малым
            if kept.contains(where: { $0.size >= p.size && $0.price <= p.price && ($0.size > p.size || $0.price < p.price || $0.offerID != p.offerID) }) { continue }
            kept.append(p)
        }
        packs = kept.sorted { $0.size < $1.size }
        let maxSize = packs.map { $0.size }.max() ?? 0
        limit = min(max(maxSize * 3, 1), 250_000)
        best = packs.min { Double($0.price) / Double($0.size) < Double($1.price) / Double($1.size) }
        var t = [Int](repeating: 0, count: limit + 1)
        var ch = [Int](repeating: -1, count: limit + 1)
        if !packs.isEmpty {
            if limit >= 1 {
                for x in 1...limit {
                    var bestCost = PackCover.infinity
                    var bi = -1
                    for (i, p) in packs.enumerated() {
                        let c = p.price + t[max(0, x - p.size)]
                        if c < bestCost { bestCost = c; bi = i }
                    }
                    t[x] = bestCost; ch[x] = bi
                }
            }
        } else {
            for x in 1...max(1, limit) where x <= limit { t[x] = PackCover.infinity }
        }
        table = t; choice = ch
    }

    public var isEmpty: Bool { packs.isEmpty }

    /// Минимальная стоимость покрытия need единиц, копейки (infinity — если нет предложений).
    public func cost(need: Int) -> Int {
        if need <= 0 { return 0 }
        guard let b = best else { return PackCover.infinity }
        if need <= limit { return table[need] }
        let k = (need - limit + b.size - 1) / b.size
        let rest = need - k * b.size
        return k * b.price + (rest > 0 ? table[min(rest, limit)] : 0)
    }

    public func select(need: Int) -> Selection? {
        if need <= 0 { return Selection(packs: [], totalCost: 0, totalSize: 0) }
        guard let b = best else { return nil }
        var counts: [Pack: Int] = [:]
        var remaining = need
        if need > limit {
            let k = (need - limit + b.size - 1) / b.size
            counts[b, default: 0] += k
            remaining = need - k * b.size
        }
        while remaining > 0 {
            let i = choice[min(remaining, limit)]
            if i < 0 { return nil }
            let p = packs[i]
            counts[p, default: 0] += 1
            remaining -= p.size
        }
        let list = counts.map { (pack: $0.key, count: $0.value) }.sorted { $0.pack.size > $1.pack.size }
        let totalCost = list.reduce(0) { $0 + $1.pack.price * $1.count }
        let totalSize = list.reduce(0) { $0 + $1.pack.size * $1.count }
        return Selection(packs: list, totalCost: totalCost, totalSize: totalSize)
    }
}
