import SwiftUI
import Charts
import MealCore

struct StatsView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            if let plan = store.state.currentPlan {
                let s = PlanStatistics(plan: plan, library: store.library, offers: store.state.cachedOffers)
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        tile("Корзина", plan.basketTotal.formatted()); tile("Экономия*", s.savingsVsPriciest.formatted())
                    }
                    Text("* относительно самых дорогих из найденных предложений на те же упаковки.").font(.caption2).foregroundStyle(Theme.muted)
                    SectionTitle(text: "Стоимость блюд по дням, ₽")
                    Chart(plan.dayStats, id: \.day) { d in
                        BarMark(x: .value("День", d.day + 1), y: .value("₽", d.cost.rubles)).foregroundStyle(Theme.accent)
                    }.frame(height: 160).card()
                    SectionTitle(text: "Калорийность на порцию, ккал/день")
                    Chart(plan.dayStats, id: \.day) { d in
                        LineMark(x: .value("День", d.day + 1), y: .value("ккал", d.kcalReference)).foregroundStyle(Theme.saffron)
                        PointMark(x: .value("День", d.day + 1), y: .value("ккал", d.kcalReference)).foregroundStyle(Theme.saffron)
                    }.frame(height: 160).card()
                    HStack(spacing: 12) {
                        tile("Белки", "\(Int(s.avgProtein)) г"); tile("Жиры", "\(Int(s.avgFat)) г"); tile("Углеводы", "\(Int(s.avgCarbs)) г")
                    }
                    SectionTitle(text: "Траты по категориям")
                    VStack(spacing: 8) { ForEach(s.costByCategory, id: \.category) { c in
                        HStack { Text(PlanStatistics.categoryTitle(c.category)); Spacer(); Text(c.cost.formatted()).font(Theme.number(15)) }
                    } }.card()
                    SectionTitle(text: "Фактические расходы")
                    let sp = SpendingSummary(records: store.state.purchaseRecords, plan: plan)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Всего записано: \(sp.total.formatted())").font(Theme.body)
                        if let v = sp.versusPlan { Text("К плану текущего рациона: \(v.kopecks >= 0 ? "+" : "−")\(Money(kopecks: abs(v.kopecks)).formatted())").font(Theme.caption).foregroundStyle(Theme.muted) }
                        ForEach(sp.byMonth, id: \.month) { m in HStack { Text(m.month); Spacer(); Text(m.amount.formatted()) }.font(Theme.caption) }
                    }.card()
                }.padding(20)
            } else { EmptyState(icon: "chart.bar", title: "Нет данных", text: "Статистика появится после создания рациона.") }
        }
        .screenBackground().navigationTitle("Статистика")
    }
    private func tile(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(t).font(.caption).foregroundStyle(Theme.muted); Text(v).font(Theme.number(20)).minimumScaleFactor(0.7).lineLimit(1) }.card(padding: 12)
    }
}
