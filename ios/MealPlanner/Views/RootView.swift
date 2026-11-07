import SwiftUI
import MealCore

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var showWizard = false

    var body: some View {
        TabView {
            HomeView(showWizard: $showWizard)
                .tabItem { Label("Главная", systemImage: "leaf") }
            PlanView(showWizard: $showWizard)
                .tabItem { Label("Рацион", systemImage: "calendar") }
            ShoppingView()
                .tabItem { Label("Покупки", systemImage: "cart") }
            AssistantView()
                .tabItem { Label("Помощник", systemImage: "sparkles") }
            MoreView(showWizard: $showWizard)
                .tabItem { Label("Ещё", systemImage: "ellipsis.circle") }
        }
        .fullScreenCover(isPresented: $showWizard) { WizardView(isPresented: $showWizard) }
        .onAppear { if !store.state.onboardingDone && store.state.plans.isEmpty { showWizard = true } }
        .alert("Данные", isPresented: Binding(get: { store.storageNote != nil }, set: { if !$0 { store.storageNote = nil } })) {
            Button("OK") { store.storageNote = nil }
        } message: { Text(store.storageNote ?? "") }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @Binding var showWizard: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let plan = store.state.currentPlan { content(plan) }
                    else {
                        EmptyState(icon: "fork.knife", title: "Составим рацион", text: "Выберите магазины рядом, бюджет и ограничения — приложение подберёт блюда, упаковки и покажет, что и где купить.")
                        PrimaryButton(title: "Создать рацион", systemImage: "wand.and.stars") { showWizard = true }
                    }
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Рацион")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private func content(_ plan: MealPlan) -> some View {
        let idx = plan.todayIndex
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.date(forDay: idx).dayString()).font(Theme.caption).foregroundStyle(Theme.muted)
            Text("Сегодня в меню").font(Theme.display(30)).foregroundStyle(Theme.ink)
        }
        HStack { Spacer(); BudgetPlate(spent: plan.basketTotal, budget: plan.budget); Spacer() }
        HStack(spacing: 12) {
            stat("На день", plan.perDay.formatted())
            stat("На человека/день", plan.perPersonPerDay.formatted())
            stat("Использовано", "\(Int(plan.usedPercent)) %")
        }
        if plan.estimateShare > 0 {
            Label("Часть цен ориентировочная — это не данные магазина.", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.caption).foregroundStyle(Theme.tomato).card()
        }
        SectionTitle(text: "Сегодня")
        ForEach(plan.meals.filter { $0.day == idx }) { m in
            NavigationLink { RecipeDetailView(recipeID: m.recipeID, meal: m) } label: { MealRow(meal: m) }.buttonStyle(.plain)
        }
        if let next = nextMeal(plan) {
            HStack { Image(systemName: "clock"); Text("Ближайший приём: \(next.slotName) — \(next.recipeName)") }
                .font(Theme.caption).foregroundStyle(Theme.muted)
        }
        HStack(spacing: 12) {
            NavigationLink { RecipesView() } label: { SecondaryButton(title: "Рецепты", systemImage: "book") {} .allowsHitTesting(false) }
            SecondaryButton(title: "Новый рацион", systemImage: "plus") { showWizard = true }
        }
    }

    private func nextMeal(_ plan: MealPlan) -> PlannedMeal? {
        plan.meals.first { $0.day >= plan.todayIndex && !store.state.doneMeals.contains($0.id) }
    }

    private func stat(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.caption).foregroundStyle(Theme.muted)
            Text(v).font(Theme.number(17)).foregroundStyle(Theme.ink).minimumScaleFactor(0.7).lineLimit(1)
        }.card(padding: 12)
    }
}

struct MealRow: View {
    @EnvironmentObject var store: AppStore
    let meal: PlannedMeal
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.sage).frame(width: 44, height: 44)
                Image(systemName: icon).foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.slotName.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                Text(meal.recipeName).font(.system(.body, design: .serif).weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                HStack(spacing: 10) {
                    Text("\(Int(meal.nutritionPerPortion.kcal)) ккал")
                    Text(meal.cost.formatted())
                    if meal.batches > 1 { Text("\(meal.batches) подхода") }
                }.font(Theme.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            if store.state.doneMeals.contains(meal.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
        }
        .card(padding: 14)
    }
    private var icon: String {
        switch meal.type { case .breakfast: return "sunrise"; case .lunch: return "sun.max"; case .dinner: return "moon.stars"; case .snack: return "carrot" }
    }
}
