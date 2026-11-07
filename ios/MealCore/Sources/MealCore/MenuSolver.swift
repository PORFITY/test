import Foundation

/// Локальный поиск по меню: назначает рецепт и масштаб порции на каждый слот, минимизируя
/// λ·стоимость_закупки(упаковки) + штрафы (повторы, калорийность, белок, предпочтения).
final class MenuSolver {
    unowned let ctx: MealPlanner.Context
    let stores: Set<String>
    let lambda: Double
    let pool: [Candidate]
    let slotPool: [[Int]]
    let fixed: [Bool]
    let covers: [PackCover?]
    let M: Int, N: Int, days: Int
    let R = Energy.referenceKcal
    let V1: Double, V2: Double, V3: Double
    let proteinTarget: Double
    let proteinWeight: Double
    let slotShare: [Double]
    let lockedScale: [Int]

    struct State {
        var c: [Int]
        var s: [Int]
        var demand: [Int]
        var ingCost: [Double]
        var counts: [Int]
        var dayKcal: [Double]
        var dayProt: [Double]
    }

    init(ctx: MealPlanner.Context, stores: Set<String>, lambda: Double) {
        self.ctx = ctx; self.stores = stores; self.lambda = lambda
        M = ctx.M; N = ctx.N; days = ctx.settings.days
        let variety = ctx.settings.variety
        V1 = 500 + 2500 * variety
        V2 = 1200 * variety + 100
        V3 = 7000 * variety + 500
        switch ctx.settings.goal {
        case .highProtein: proteinTarget = 0.25 * 2000 / 4; proteinWeight = 25
        case .muscleGain: proteinTarget = 0.22 * 2000 / 4; proteinWeight = 25
        default: proteinTarget = 0.14 * 2000 / 4; proteinWeight = 6
        }
        covers = ctx.ingKeys.map { ctx.cover($0, stores: stores) }
        // пул
        var p: [Candidate] = []
        var idxByRecipe: [String: Int] = [:]
        for c in ctx.candidates where ctx.recipeAvailable(c, stores: stores) || c.locked {
            idxByRecipe[c.recipe.id] = p.count
            p.append(c)
        }
        pool = p
        var sp: [[Int]] = []
        var fx: [Bool] = []
        var ls: [Int] = []
        for i in 0..<ctx.N {
            let slotIdx = i % ctx.M
            let day = i / ctx.M
            let type = ctx.slots[slotIdx].type
            if let lock = ctx.input.locked[SlotKey(day: day, slot: slotIdx)], let pi = idxByRecipe[lock.recipeID] {
                sp.append([pi]); fx.append(true)
                var best = 0, bd = Double.infinity
                for (k, s) in MealPlanner.scales.enumerated() where abs(s - lock.scale) < bd && p[pi].batchesByScale[k] > 0 { bd = abs(s - lock.scale); best = k }
                ls.append(best)
                continue
            }
            var list = p.indices.filter { ctx.slotAccepts(type, p[$0]) && !p[$0].locked }
            if list.isEmpty {
                list = ctx.candidates.indices.compactMap { ci -> Int? in
                    let c = ctx.candidates[ci]
                    return (ctx.slotAccepts(type, c) && !c.locked) ? idxByRecipe[c.recipe.id] : nil
                }
            }
            sp.append(list); fx.append(false); ls.append(0)
        }
        slotPool = sp; fixed = fx; lockedScale = ls
        slotShare = (0..<ctx.N).map { ctx.slots[$0 % ctx.M].share }
    }

    // MARK: Компоненты

    @inline(__always) func costK(_ k: Int, _ d: Int) -> Double {
        let need = d - ctx.pantryUsable[k]
        if need <= 0 { return 0 }
        guard let c = covers[k] else { return MealPlanner.unavailablePenalty }
        let v = c.cost(need: need)
        return v >= PackCover.infinity ? MealPlanner.unavailablePenalty : Double(v)
    }

    func local(_ i: Int, _ c: Int, _ s: Int) -> Double {
        let cand = pool[c]
        let scale = MealPlanner.scales[s]
        var v = cand.pref
        let b = cand.batchesByScale[s]
        if b <= 0 { return 1e9 }
        v += Double(b - 1) * 300
        v += 250 * abs(scale - 1) + (scale > 1.5 ? 1500 : 0)
        let kcal = cand.nutrition.kcal * scale
        let target = max(100, slotShare[i] * R)
        let dev = abs(kcal - target) / target
        if dev > 0.4 { v += 1.5 * (dev - 0.4) * target }
        return v
    }

    func dayPenalty(kcal: Double, prot: Double) -> Double {
        var v = 0.0
        let dev = abs(kcal - R) / R
        if dev > 0.08 { v += 6 * (dev - 0.08) * R }
        let pt = proteinTarget * 0.9
        if prot < pt { v += proteinWeight * (pt - prot) }
        return v
    }

    func pairPenalty(_ a: Int, _ b: Int) -> Double {
        if a == b { return V3 }
        if !pool[a].mainTags.isDisjoint(with: pool[b].mainTags) { return V2 }
        return 0
    }

    func neighbors(_ i: Int) -> [Int] {
        var out: [Int] = []
        if i > 0 { out.append(i - 1) }
        if i + 1 < N { out.append(i + 1) }
        if i - M >= 0 { out.append(i - M) }
        if i + M < N { out.append(i + M) }
        return out
    }

    func fullScore(_ st: State) -> Double {
        var t = 0.0
        for k in 0..<st.demand.count { t += lambda * costK(k, st.demand[k]) }
        for i in 0..<N { t += local(i, st.c[i], st.s[i]) }
        for n in st.counts where n > 1 { t += V1 * Double(n * (n - 1) / 2) }
        for i in 0..<N {
            if i + 1 < N { t += pairPenalty(st.c[i], st.c[i + 1]) }
            if i + M < N { t += pairPenalty(st.c[i], st.c[i + M]) }
        }
        for d in 0..<days { t += dayPenalty(kcal: st.dayKcal[d], prot: st.dayProt[d]) }
        return t
    }

    func initialState(seed: UInt64) -> State {
        var rng = SplitMix64(s: seed)
        var c = [Int](repeating: 0, count: N), s = [Int](repeating: 0, count: N)
        for i in 0..<N {
            let list = slotPool[i]
            c[i] = list[rng.int(list.count)]
            s[i] = fixed[i] ? lockedScale[i] : 0
        }
        return rebuild(c: c, s: s)
    }

    func rebuild(c: [Int], s: [Int]) -> State {
        var demand = [Int](repeating: 0, count: ctx.ingKeys.count)
        var counts = [Int](repeating: 0, count: pool.count)
        var dk = [Double](repeating: 0, count: days), dp = [Double](repeating: 0, count: days)
        for i in 0..<N {
            let cand = pool[c[i]]
            for e in cand.demand[s[i]] { demand[e.idx] += e.amt }
            counts[c[i]] += 1
            let sc = MealPlanner.scales[s[i]]
            dk[i / M] += cand.nutrition.kcal * sc
            dp[i / M] += cand.nutrition.protein * sc
        }
        let ic = (0..<demand.count).map { costK($0, demand[$0]) }
        return State(c: c, s: s, demand: demand, ingCost: ic, counts: counts, dayKcal: dk, dayProt: dp)
    }

    /// Изменение целевой функции при замене (c1,s1)→(c2,s2) в слоте i. Не меняет состояние.
    func delta(_ st: State, _ i: Int, _ c2: Int, _ s2: Int) -> Double {
        let c1 = st.c[i], s1 = st.s[i]
        if c1 == c2 && s1 == s2 { return 0 }
        let old = pool[c1], new = pool[c2]
        var d = 0.0
        // стоимость закупки
        var changes: [Int: Int] = [:]
        for e in old.demand[s1] { changes[e.idx, default: 0] -= e.amt }
        for e in new.demand[s2] { changes[e.idx, default: 0] += e.amt }
        var dc = 0.0
        for (k, ch) in changes where ch != 0 { dc += costK(k, st.demand[k] + ch) - st.ingCost[k] }
        d += lambda * dc
        // локальные
        d += local(i, c2, s2) - local(i, c1, s1)
        if c1 != c2 {
            let n1 = st.counts[c1], n2 = st.counts[c2]
            d += -V1 * Double(n1 - 1) + V1 * Double(n2)
            for j in neighbors(i) {
                let cj = st.c[j]
                d += pairPenalty(c2, cj) - pairPenalty(c1, cj)
            }
        }
        // день
        let day = i / M
        let sc1 = MealPlanner.scales[s1], sc2 = MealPlanner.scales[s2]
        let nk = st.dayKcal[day] - old.nutrition.kcal * sc1 + new.nutrition.kcal * sc2
        let np = st.dayProt[day] - old.nutrition.protein * sc1 + new.nutrition.protein * sc2
        d += dayPenalty(kcal: nk, prot: np) - dayPenalty(kcal: st.dayKcal[day], prot: st.dayProt[day])
        return d
    }

    func apply(_ st: inout State, _ i: Int, _ c2: Int, _ s2: Int) {
        let c1 = st.c[i], s1 = st.s[i]
        let old = pool[c1], new = pool[c2]
        var touched = Set<Int>()
        for e in old.demand[s1] { st.demand[e.idx] -= e.amt; touched.insert(e.idx) }
        for e in new.demand[s2] { st.demand[e.idx] += e.amt; touched.insert(e.idx) }
        for k in touched { st.ingCost[k] = costK(k, st.demand[k]) }
        st.counts[c1] -= 1; st.counts[c2] += 1
        let day = i / M
        let sc1 = MealPlanner.scales[s1], sc2 = MealPlanner.scales[s2]
        st.dayKcal[day] += -old.nutrition.kcal * sc1 + new.nutrition.kcal * sc2
        st.dayProt[day] += -old.nutrition.protein * sc1 + new.nutrition.protein * sc2
        st.c[i] = c2; st.s[i] = s2
    }

    func improve(_ st: inout State, seed: UInt64, maxPasses: Int = 14) {
        var rng = SplitMix64(s: seed)
        let free = (0..<N).filter { !fixed[$0] }
        if free.isEmpty { return }
        func descend(_ st: inout State) {
            for _ in 0..<maxPasses {
                var order = free
                for k in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(k, rng.int(k + 1)) }
                var improved = false
                for i in order {
                    var bestD = -1e-6, bc = -1, bs = -1
                    for c in slotPool[i] {
                        for s in 0..<MealPlanner.scales.count where pool[c].batchesByScale[s] > 0 {
                            let d = delta(st, i, c, s)
                            if d < bestD { bestD = d; bc = c; bs = s }
                        }
                    }
                    if bc >= 0 { apply(&st, i, bc, bs); improved = true }
                }
                if !improved { break }
            }
        }
        descend(&st)
        // «встряска»: перебросить часть слотов и снова спуститься; оставить, если лучше
        var best = st
        var bestScore = fullScore(best)
        for _ in 0..<2 {
            var trial = best
            let kicks = max(1, free.count / 8)
            for _ in 0..<kicks {
                let i = free[rng.int(free.count)]
                let list = slotPool[i]
                let c = list[rng.int(list.count)]
                if pool[c].batchesByScale[0] > 0 { apply(&trial, i, c, 0) }
            }
            descend(&trial)
            let sc = fullScore(trial)
            if sc < bestScore - 1e-6 { best = trial; bestScore = sc }
        }
        st = best
    }
}
