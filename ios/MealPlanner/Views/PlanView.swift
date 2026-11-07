import SwiftUI
import MealCore

struct PlanView: View {
    @EnvironmentObject var store: AppStore
    @Binding var showWizard: Bool
    @State private var selectedDay = 0
    @State private var replacing: PlannedMeal?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.state.currentPlan { planBody(plan) }
                else { ScrollView { EmptyState(icon: "calendar", title: "Рациона пока нет", text: "Создайте рацион — здесь появится меню на каждый день.") ; PrimaryButton(title: "Создать рацион") { showWizard = true }.padding(20) } }
            }
            .screenBackground()
            .navigationTitle("Календарь питания")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { HistoryView() } label: { Image(systemName: "clock.arrow.circlepath") } } }
            .onAppear { if let p = store.state.currentPlan { selectedDay = min(p.todayIndex, p.settings.days - 1) } }
        }
    }

    private func planBody(_ plan: MealPlan) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<plan.settings.days, id: \.self) { d in
                        Button { selectedDay = d } label: {
                            VStack(spacing: 2) {
                                Text(plan.date(forDay: d).weekdayShort()).font(.caption2)
                                Text("\(Calendar.current.component(.day, from: plan.date(forDay: d)))").font(Theme.number(18))
                            }
                            .frame(width: 48, height: 58)
                            .foregroundStyle(selectedDay == d ? Color.white : Theme.ink)
                            .background(selectedDay == d ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 10)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if plan.status == .overBudget { warningCard(plan) }
                    ForEach(plan.warnings.filter { $0.kind != .overBudget }) { w in
                        Label(w.message, systemImage: "info.circle").font(Theme.caption).foregroundStyle(Theme.muted).card(padding: 12)
                    }
                    let d = min(selectedDay, plan.settings.days - 1)
                    if let st = plan.dayStats.first(where: { $0.day == d }) {
                        HStack {
                            Text("\(plan.date(forDay: d).dayString())").font(Theme.display(22))
                            Spacer()
                            Text("\(Int(st.kcalReference)) ккал · Б \(Int(st.protein)) Ж \(Int(st.fat)) У \(Int(st.carbs))").font(Theme.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    ForEach(plan.meals.filter { $0.day == d }) { m in
                        NavigationLink { RecipeDetailView(recipeID: m.recipeID, meal: m) } label: { MealRow(meal: m) }.buttonStyle(.plain)
                            .contextMenu { Button { replacing = m } label: { Label("Заменить блюдо", systemImage: "arrow.triangle.2.circlepath") } }
                        Button { replacing = m } label: { Text("Заменить").font(Theme.caption) }.padding(.leading, 8)
                    }
                    if let t = toast { Text(t).font(Theme.caption).foregroundStyle(Theme.accent) }
                    PrimaryButton(title: "Пересчитать рацион", systemImage: "arrow.clockwise", isLoading: store.isGenerating) { Task { await store.generatePlan() } }
                }.padding(20)
            }
        }
        .sheet(item: $replacing) { m in ReplaceSheet(meal: m) { msg in toast = msg } }
    }

    private func warningCard(_ plan: MealPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Бюджет не хватает", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.tomato).font(.system(.headline, design: .rounded))
            ForEach(plan.warnings.filter { $0.kind == .overBudget }) { Text($0.message).font(Theme.caption) }
            ForEach(plan.tips) { Text("• " + $0.text).font(Theme.caption) }
        }.card()
    }
}

struct ReplaceSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let meal: PlannedMeal
    var done: (String) -> Void
    @State private var suggestions: [ReplacementSuggestion] = []
    @State private var loading = true
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView() }
                else if suggestions.isEmpty { Text("Подходящих вариантов нет: всё отфильтровано по аллергенам, технике, нежелательным продуктам или ценам.").foregroundStyle(Theme.muted) }
                ForEach(suggestions) { s in
                    Button {
                        working = true
                        Task { let msg = await store.replaceMeal(day: meal.day, slot: meal.slot, with: s.recipe.id); working = false; done(msg); dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.recipe.name).font(.system(.body, design: .serif).weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("≈ \(s.estimatedCost.formatted()) по минимальным ценам · \(Int(s.kcal)) ккал/порция").font(Theme.caption).foregroundStyle(Theme.muted)
                        }
                    }.disabled(working)
                }
            }
            .navigationTitle("Заменить: \(meal.slotName)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task {
                guard let plan = store.state.currentPlan, let input = store.currentInput() else { loading = false; return }
                let engine = store.engine
                let m = meal
                suggestions = await Task.detached { engine.suggestions(input: input, plan: plan, day: m.day, slot: m.slot, include: [], avoid: [], limit: 12) }.value
                loading = false
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        List {
            ForEach(store.state.plans) { p in
                Button {
                    store.state.currentPlanID = p.id; store.state.checkedLines = []
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title).font(.system(.body, design: .serif).weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("\(p.createdAt.dayString()) · \(p.people.count) чел. · \(p.basketTotal.formatted()) из \(p.budget.formatted())").font(Theme.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if p.id == store.state.currentPlan?.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                    }
                }
            }
            .onDelete { idx in
                let ids = idx.map { store.state.plans[$0].id }
                store.state.plans.removeAll { ids.contains($0.id) }
            }
        }
        .navigationTitle("История рационов")
        .overlay { if store.state.plans.isEmpty { EmptyState(icon: "clock", title: "Пусто", text: "Здесь будут сохранённые рационы. Нажмите на рацион, чтобы использовать его снова.") } }
    }
}
