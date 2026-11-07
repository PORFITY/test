import SwiftUI
import MealCore
import CoreLocation

struct WizardView: View {
    @EnvironmentObject var store: AppStore
    @Binding var isPresented: Bool
    @State private var step = 0
    private let titles = ["Магазины", "Бюджет и период", "Аллергены", "Вкусы", "Цель и покупки", "Кухня", "Готово"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(titles.count)).tint(Theme.accent).padding(.horizontal, 20).padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(titles[step]).font(Theme.display(30)).foregroundStyle(Theme.ink)
                        stepContent
                    }.padding(20)
                }
                footer
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { isPresented = false } } }
            .overlay { if store.isGenerating { GeneratingOverlay() } }
            .alert("Нет достоверных цен", isPresented: $store.needsEstimateConsent) {
                Button("Рассчитать по ориентирам") { Task { await generate(estimates: true) } }
                Button("Отмена", role: .cancel) {}
            } message: { Text("По выбранным магазинам нет реальных цен. Можно посчитать по ориентировочным ценам — результат будет явно помечен как приблизительный и не заменит реальный ценник. Либо загрузите каталог (CSV/JSON) или введите цены вручную в Настройках.") }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0:
            StoresView(embedded: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Нет магазинов или не нужны?").font(.system(.headline, design: .rounded))
                Text("Можно продолжить без магазинов: цены будут ориентировочными и явно помечены в результате.").font(Theme.caption).foregroundStyle(Theme.muted)
                SecondaryButton(title: "Продолжить без магазинов (ориентиры)", systemImage: "arrow.right") {
                    store.state.draft.pricePolicy = .allowEstimates
                    withAnimation { step = 1 }
                }
            }.card()
        case 1: BudgetStep()
        case 2: AllergenStep()
        case 3: TastesStep()
        case 4: GoalStep()
        case 5: KitchenStep()
        default: SummaryStep()
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return !store.state.selectedStoreIDs.isEmpty || store.state.draft.pricePolicy == .allowEstimates || !store.state.userPrices.isEmpty
        case 1: return store.state.draft.budgetRub > 0 && store.state.draft.days >= 1 && store.state.draft.peopleCount >= 1 && store.state.draft.slots.count >= 1
        case 2: return store.state.allergensAsked
        case 5: return store.state.kitchenConfirmed
        default: return true
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if step == titles.count - 1 {
                if let e = store.errorMessage { Text(e).font(Theme.caption).foregroundStyle(Theme.tomato) }
                PrimaryButton(title: "Создать рацион", systemImage: "wand.and.stars", isLoading: store.isGenerating) { Task { await generate(estimates: false) } }
                    .disabled(!store.readiness.isEmpty)
            } else {
                PrimaryButton(title: "Далее") { withAnimation { step += 1 } }.disabled(!canAdvance).opacity(canAdvance ? 1 : 0.4)
            }
            if step > 0 { Button("Назад") { withAnimation { step -= 1 } }.font(Theme.caption).foregroundStyle(Theme.muted) }
        }
        .padding(20).background(Theme.paper)
    }

    private func generate(estimates: Bool) async {
        await store.generatePlan(allowEstimates: estimates)
        if store.state.currentPlan != nil && store.errorMessage == nil { isPresented = false }
    }
}

struct GeneratingOverlay: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.4)
                Text(store.phase).font(.system(.subheadline, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(Theme.ink)
            }.padding(28).background(Theme.card, in: RoundedRectangle(cornerRadius: 24)).padding(40)
        }
    }
}

struct BudgetStep: View {
    @EnvironmentObject var store: AppStore
    @State private var customDays = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            group("Бюджет, ₽") {
                TextField("Например, 7000", value: $store.state.draft.budgetRub, format: .number.grouping(.never))
                    .keyboardType(.numberPad).font(Theme.number(32)).textFieldStyle(.roundedBorder)
                Text("Любая положительная сумма. Это бюджет на закупку продуктов целиком, а не «сумма ÷ дни»: приложение учитывает упаковки и остатки.").font(Theme.caption).foregroundStyle(Theme.muted)
            }
            group("Период") {
                FlowLayout { ForEach([1, 3, 7, 14, 30, 60], id: \.self) { d in
                    Button { store.state.draft.days = d } label: { Chip(text: "\(d) дн.", selected: store.state.draft.days == d) }.buttonStyle(.plain) } }
                Stepper(value: $store.state.draft.days, in: 1...365) { Text("Дней: \(store.state.draft.days)").font(Theme.number(17)) }
                if store.state.draft.days > 14 { Text("Для длинных периодов закупки разбиваются на этапы, скоропортящееся не покупается впрок.").font(Theme.caption).foregroundStyle(Theme.muted) }
            }
            group("Сколько человек") {
                Stepper(value: $store.state.draft.peopleCount, in: 1...100) { Text("Человек: \(store.state.draft.peopleCount)").font(Theme.number(17)) }
            }
            group("Приёмов пищи в день") {
                Stepper(value: Binding(get: { store.state.draft.mealCount }, set: { n in
                    store.state.draft.mealCount = n; store.state.draft.slots = MealSlotConfig.defaults(count: n)
                }), in: 1...12) { Text("Приёмов: \(store.state.draft.mealCount)").font(Theme.number(17)) }
                ForEach($store.state.draft.slots) { $slot in
                    HStack {
                        TextField("Название", text: $slot.name).textFieldStyle(.roundedBorder)
                        Picker("", selection: $slot.type) { ForEach(MealType.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden()
                    }
                }
                Text("Название можно менять; «тип» определяет, какие блюда подходят (завтрак, обед, ужин, перекус).").font(Theme.caption).foregroundStyle(Theme.muted)
            }
        }
    }
    private func group<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(t).font(.system(.headline, design: .rounded)); c() }.card()
    }
}

struct AllergenStep: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Есть ли у вас или у тех, для кого вы готовите, пищевая аллергия? Отмеченное исключается строго — в блюдах и в составе товаров магазинов (включая «может содержать следы»).")
                .font(Theme.body).foregroundStyle(Theme.muted)
            AllergenPicker(allergens: $store.state.shared.allergens).card()
            Button {
                store.state.allergensAsked = true
            } label: {
                Label(store.state.shared.allergens.isEmpty ? "У нас нет аллергий — продолжить" : "Подтверждаю список аллергенов", systemImage: store.state.allergensAsked ? "checkmark.circle.fill" : "circle")
                    .font(.system(.headline, design: .rounded)).foregroundStyle(store.state.allergensAsked ? Theme.accent : Theme.ink)
            }.buttonStyle(.plain).card()
            Text("Если состав товара неизвестен, приложение пометит это и не будет гарантировать безопасность. Это не медицинская рекомендация.").font(Theme.caption).foregroundStyle(Theme.muted)
        }
    }
}

struct TastesStep: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileEditor(profile: $store.state.shared, isShared: true).card()
            VStack(alignment: .leading, spacing: 10) {
                Text("Индивидуальные профили").font(.system(.headline, design: .rounded))
                Text("Если у разных людей разные ограничения (один не ест грибы, у другого аллергия на орехи) — добавьте профили. Меню будет общим и учтёт ограничения каждого.").font(Theme.caption).foregroundStyle(Theme.muted)
                ForEach($store.state.people) { $p in
                    DisclosureGroup(p.name) { ProfileEditor(profile: $p).padding(.top, 8) }
                }
                SecondaryButton(title: "Добавить человека", systemImage: "person.badge.plus") {
                    store.state.people.append(PersonProfile(name: "Человек \(store.state.people.count + 1)"))
                    if store.state.draft.peopleCount < store.state.people.count { store.state.draft.peopleCount = store.state.people.count }
                }
            }.card()
        }
    }
}

struct GoalStep: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Цель питания").font(.system(.headline, design: .rounded))
            ForEach(DietGoal.allCases) { g in
                Button { store.state.draft.goal = g } label: {
                    HStack { Text(g.title).foregroundStyle(Theme.ink); Spacer(); if store.state.draft.goal == g { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) } }
                }.buttonStyle(.plain).card(padding: 14)
            }
            Text("Режим покупок").font(.system(.headline, design: .rounded)).padding(.top, 8)
            ForEach(ShoppingMode.allCases) { m in
                Button { store.state.draft.mode = m } label: {
                    HStack { Text(m.title).foregroundStyle(Theme.ink); Spacer(); if store.state.draft.mode == m { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) } }
                }.buttonStyle(.plain).card(padding: 14)
            }
            Toggle("Если реальных цен нет — считать по ориентирам (с пометкой)", isOn: Binding(get: { store.state.draft.pricePolicy == .allowEstimates }, set: { store.state.draft.pricePolicy = $0 ? .allowEstimates : .verifiedOnly })).card()
            Toggle("Исключать товары с неизвестным составом", isOn: Binding(get: { store.state.draft.unknownComposition == .exclude }, set: { store.state.draft.unknownComposition = $0 ? .exclude : .allowWithWarning })).card()
            VStack(alignment: .leading) {
                Text("Разнообразие меню").font(.system(.headline, design: .rounded))
                Slider(value: $store.state.draft.variety, in: 0...1)
            }.card()
        }
    }
}

struct KitchenStep: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            KitchenEditor(kitchen: $store.state.kitchen).card()
            Button { store.state.kitchenConfirmed.toggle() } label: {
                Label("Это моя кухня — всё верно", systemImage: store.state.kitchenConfirmed ? "checkmark.circle.fill" : "circle")
                    .font(.system(.headline, design: .rounded)).foregroundStyle(store.state.kitchenConfirmed ? Theme.accent : Theme.ink)
            }.buttonStyle(.plain).card()
        }
    }
}

struct SummaryStep: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        let d = store.state.draft
        VStack(alignment: .leading, spacing: 12) {
            row("Магазины", "\(store.state.selectedStoreIDs.count) выбрано")
            row("Бюджет", Money.rub(d.budgetRub).formatted())
            row("Период", "\(d.days) дн. · \(d.peopleCount) чел. · \(d.mealCount) приёмов")
            row("Цель", d.goal.title)
            row("Режим покупок", d.mode.title)
            row("Аллергены", store.state.shared.allergens.isEmpty ? "нет" : store.state.shared.allergens.map { $0.title }.joined(separator: ", "))
            row("Не люблю", store.state.shared.dislikes.isEmpty ? "—" : store.state.shared.dislikes.joined(separator: ", "))
            row("Люблю", store.state.shared.favorites.isEmpty ? "—" : store.state.shared.favorites.joined(separator: ", "))
            if !store.readiness.isEmpty {
                VStack(alignment: .leading, spacing: 6) { ForEach(store.readiness, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(Theme.tomato).font(Theme.caption) } }.card()
            }
        }
    }
    private func row(_ t: String, _ v: String) -> some View {
        HStack(alignment: .top) { Text(t).foregroundStyle(Theme.muted); Spacer(); Text(v).multilineTextAlignment(.trailing).foregroundStyle(Theme.ink) }.font(Theme.body).card(padding: 12)
    }
}
