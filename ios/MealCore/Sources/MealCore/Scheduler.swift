import Foundation

struct ScheduledLine {
    var key: String
    var offerID: String
    var storeID: String
    var packs: Int
    var packSize: Int
    var price: Int
    var day: Int
    var firstUseDay: Int
    var needsFreezing: Bool
}

struct Schedule {
    var lines: [ScheduledLine] = []
    var totalCost = 0
    var usedPantry: [String: Int] = [:]
    var purchasedBase: [String: Int] = [:]
    var costByKey: [String: Int] = [:]
    var leftoverBase: [String: Int] = [:]
    var missing: [String: Int] = [:]
}

/// Превращает меню в график закупок: учитывает остатки, сроки годности, заморозку и этапы закупок.
struct ShoppingScheduler {
    unowned let ctx: MealPlanner.Context
    let stores: Set<String>

    private struct Lot { var amount: Int; var expiry: Int; var purchased: Bool }

    func build(choiceC: [Int], choiceS: [Int], pool: [Candidate]) -> Schedule {
        let M = ctx.M
        var events: [Int: [(day: Int, amt: Int)]] = [:]
        for i in 0..<choiceC.count {
            let day = i / M
            for e in pool[choiceC[i]].demand[choiceS[i]] { events[e.idx, default: []].append((day, e.amt)) }
        }
        let stage: Int? = ctx.settings.stageDays ?? (ctx.settings.days > 14 ? 7 : nil)
        var sch = Schedule()
        var merged: [String: ScheduledLine] = [:]

        for (k, evs) in events {
            let key = ctx.ingKeys[k]
            guard let info = ctx.lib.ingredients[key] else { continue }
            let freezer = ctx.input.kitchen.hasFreezer
            let shelfEff = max(info.shelf, freezer ? info.frozen : 0, 1)
            var lots: [Lot] = (ctx.pantryLots[key] ?? []).map { Lot(amount: $0.amount, expiry: $0.expiryDay, purchased: false) }
            let sorted = evs.sorted { $0.day < $1.day }
            // слить события одного дня
            var byDay: [(day: Int, amt: Int)] = []
            for e in sorted { if let l = byDay.last, l.day == e.day { byDay[byDay.count - 1].amt += e.amt } else { byDay.append(e) } }
            let cover = ctx.cover(key, stores: stores)

            for (ei, ev) in byDay.enumerated() {
                var need = ev.amt
                lots.sort { $0.expiry < $1.expiry }
                for li in lots.indices where need > 0 && lots[li].expiry >= ev.day && lots[li].amount > 0 {
                    let take = min(need, lots[li].amount)
                    lots[li].amount -= take; need -= take
                    if !lots[li].purchased { sch.usedPantry[key, default: 0] += take }
                }
                if need <= 0 { continue }
                let tripDay = stage.map { (ev.day / $0) * $0 } ?? 0
                let buyDay = (ev.day - tripDay < shelfEff) ? tripDay : ev.day
                let windowEnd = min(buyDay + shelfEff - 1, buyDay + (stage ?? Int.max / 4) - 1)
                var future = 0
                if ei + 1 < byDay.count {
                    for f in byDay[(ei + 1)...] where f.day <= windowEnd { future += f.amt }
                }
                let stockForFuture = lots.filter { $0.expiry >= windowEnd }.reduce(0) { $0 + $1.amount }
                let want = need + max(0, future - stockForFuture)
                guard let cv = cover, let sel = cv.select(need: want) else {
                    sch.missing[key, default: 0] += need
                    continue
                }
                for (pack, count) in sel.packs {
                    let lk = "\(buyDay)|\(pack.offerID)"
                    if var l = merged[lk] { l.packs += count; merged[lk] = l }
                    else {
                        merged[lk] = ScheduledLine(key: key, offerID: pack.offerID, storeID: pack.storeID, packs: count, packSize: pack.size, price: pack.price,
                                                   day: buyDay, firstUseDay: ev.day, needsFreezing: false)
                    }
                    sch.totalCost += pack.price * count
                    sch.costByKey[key, default: 0] += pack.price * count
                    sch.purchasedBase[key, default: 0] += pack.size * count
                }
                var lastUse = ev.day
                if ei + 1 < byDay.count { for f in byDay[(ei + 1)...] where f.day <= windowEnd { lastUse = max(lastUse, f.day) } }
                if lastUse - buyDay >= info.shelf && shelfEff > info.shelf {
                    for (pack, _) in sel.packs { merged["\(buyDay)|\(pack.offerID)"]?.needsFreezing = true }
                }
                lots.append(Lot(amount: sel.totalSize - need, expiry: buyDay + shelfEff - 1, purchased: true))
            }
            let left = lots.filter { $0.purchased }.reduce(0) { $0 + $1.amount }
            if left > 0 { sch.leftoverBase[key] = left }
        }
        sch.lines = merged.values.sorted { ($0.day, $0.storeID, $0.key) < ($1.day, $1.storeID, $1.key) }
        return sch
    }
}
