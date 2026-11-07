import SwiftUI
import MealCore
import UserNotifications

struct RecipesView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    @State private var onlyFavorites = false
    @State private var type: MealType?
    @State private var showEditor = false

    private var list: [Recipe] {
        store.allRecipes.filter { r in
            (query.isEmpty || TextNorm.normalize(r.name).contains(TextNorm.normalize(query))) &&
            (!onlyFavorites || store.state.favoriteRecipeIDs.contains(r.id)) && (type == nil || r.meals.contains(type!))
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Button { onlyFavorites.toggle() } label: { Chip(text: "Избранное", selected: onlyFavorites, systemImage: "heart") }.buttonStyle(.plain)
                        ForEach(MealType.allCases, id: \.self) { t in Button { type = (type == t ? nil : t) } label: { Chip(text: t.title, selected: type == t) }.buttonStyle(.plain) }
                    }
                }.listRowBackground(Color.clear)
            }
            ForEach(list) { r in
                NavigationLink { RecipeDetailView(recipeID: r.id, meal: nil) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(r.name).font(.system(.body, design: .serif).weight(.semibold)); if store.state.favoriteRecipeIDs.contains(r.id) { Image(systemName: "heart.fill").foregroundStyle(Theme.tomato).font(.caption) } }
                        Text("\(r.totalMinutes) мин · \(Int(store.library.nutritionPerServing(r).kcal)) ккал/порция\(r.isUserCreated ? " · мой рецепт" : "")").font(Theme.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Найти рецепт")
        .navigationTitle("Рецепты")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showEditor = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showEditor) { CustomRecipeEditor() }
    }
}

struct RecipeDetailView: View {
    @EnvironmentObject var store: AppStore
    let recipeID: String
    var meal: PlannedMeal?
    @State private var servings: Double = 2
    @State private var methodID: String?
    @State private var cooking = false

    var body: some View {
        if let r = store.recipe(recipeID) { content(r) } else { Text("Рецепт не найден") }
    }

    private func methods(_ r: Recipe) -> [CookingMethod] {
        r.methods.filter { store.state.kitchen.batches(for: $0, servings: servings) != nil }
    }

    @ViewBuilder private func content(_ r: Recipe) -> some View {
        let avail = methods(r)
        let method = avail.first { $0.id == methodID } ?? (meal.flatMap { m in avail.first { $0.id == m.methodID } }) ?? avail.first
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(r.name).font(Theme.display(30)).foregroundStyle(Theme.ink)
                HStack(spacing: 14) {
                    Label("Подготовка \(r.prep) мин", systemImage: "scissors"); Label("Готовка \(r.cook) мин", systemImage: "flame")
                }.font(Theme.caption).foregroundStyle(Theme.muted)
                HStack {
                    Stepper(value: $servings, in: 0.5...100, step: 0.5) { Text("Порций: \(Fmt.number(servings))").font(Theme.number(17)) }
                }.card(padding: 12)
                if let m = meal { Text("В рационе: \(m.slotName), день \(m.day + 1). Стоимость блюда ≈ \(m.cost.formatted()) (по использованным граммам; упаковки покупаются целиком).").font(Theme.caption).foregroundStyle(Theme.muted) }
                if let method = method {
                    let rr = RecipeRenderer.render(recipe: r, method: method, servings: servings, library: store.library)
                    nutrition(rr)
                    if avail.count > 1 {
                        Picker("Способ", selection: Binding(get: { method.id }, set: { methodID = $0 })) { ForEach(avail) { Text($0.label).tag($0.id) } }.pickerStyle(.segmented)
                    }
                    if let b = store.state.kitchen.batches(for: method, servings: servings), b > 1 {
                        Label("Посуда мала для всей порции: готовьте в \(b) подхода(ов).", systemImage: "exclamationmark.triangle").font(Theme.caption).foregroundStyle(Theme.tomato)
                    }
                    SectionTitle(text: "Ингредиенты")
                    VStack(spacing: 0) {
                        ForEach(rr.ingredients) { i in
                            HStack(alignment: .top) {
                                Text(i.name).foregroundStyle(Theme.ink)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(i.display).font(Theme.number(16)).foregroundStyle(Theme.ink)
                                    if let s = i.secondary { Text(s).font(.caption2).foregroundStyle(Theme.muted) }
                                }
                            }.padding(.vertical, 8)
                            Divider()
                        }
                    }.card(padding: 12)
                    SectionTitle(text: "Приготовление")
                    ForEach(rr.steps) { s in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(s.index + 1)").font(Theme.number(15)).foregroundStyle(Color.white).frame(width: 28, height: 28).background(Theme.accent, in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                Text(s.text).font(Theme.body).foregroundStyle(Theme.ink)
                                if s.timerMin > 0 { Label("\(s.timerMin) мин", systemImage: "timer").font(Theme.caption).foregroundStyle(Theme.saffron) }
                            }
                        }
                    }
                    if let n = r.note { Label(n, systemImage: "info.circle").font(Theme.caption).foregroundStyle(Theme.muted) }
                    Label("Мясо, птицу и рыбу готовьте до полной готовности, руки и доски мойте после сырых продуктов.", systemImage: "hand.raised").font(Theme.caption).foregroundStyle(Theme.muted)
                    PrimaryButton(title: "Готовить пошагово", systemImage: "play.fill") { cooking = true }
                    if let m = meal, !store.state.doneMeals.contains(m.id) {
                        SecondaryButton(title: "Я приготовил(а) — списать из запасов", systemImage: "checkmark") { store.confirmCooked(m) }
                    }
                    .fullScreenCover(isPresented: $cooking) { CookModeView(rendered: rr) }
                } else {
                    Label("Это блюдо нельзя приготовить на вашей технике и посуде. Добавьте нужную технику в настройках.", systemImage: "xmark.octagon").foregroundStyle(Theme.tomato).card()
                }
            }.padding(20)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { store.toggleFavorite(r.id) } label: { Image(systemName: store.state.favoriteRecipeIDs.contains(r.id) ? "heart.fill" : "heart") }
        } }
        .onAppear { if let m = meal { servings = m.portions } else { servings = Double(r.servings) } }
    }

    private func nutrition(_ rr: RenderedRecipe) -> some View {
        let n = rr.nutritionPerServing
        return HStack {
            nutri("ккал", Int(n.kcal)); nutri("белки", Int(n.protein)); nutri("жиры", Int(n.fat)); nutri("углеводы", Int(n.carbs))
        }.card(padding: 12)
    }
    private func nutri(_ t: String, _ v: Int) -> some View {
        VStack { Text("\(v)").font(Theme.number(20)).foregroundStyle(Theme.ink); Text(t + " / порция").font(.caption2).foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity)
    }
}

struct CookModeView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let rendered: RenderedRecipe
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var progress: CookingProgress {
        store.state.cookingProgress[rendered.recipe.id] ?? CookingProgress(recipeID: rendered.recipe.id, methodID: rendered.method.id, servings: rendered.servings)
    }
    private func update(_ f: (inout CookingProgress) -> Void) {
        var p = progress; f(&p); store.state.cookingProgress[rendered.recipe.id] = p
    }

    var body: some View {
        let p = progress
        let total = rendered.steps.count
        let step = rendered.steps[min(p.currentStep, total - 1)]
        VStack(spacing: 20) {
            HStack {
                Button("Закрыть") { dismiss() }
                Spacer()
                Button("Сначала") { store.state.cookingProgress[rendered.recipe.id] = nil }.font(Theme.caption)
            }
            ProgressView(value: Double(p.doneSteps.count), total: Double(total)).tint(Theme.accent)
            Text("Шаг \(step.index + 1) из \(total)").font(Theme.caption).foregroundStyle(Theme.muted)
            ScrollView { Text(step.text).font(.system(size: 24, weight: .regular, design: .serif)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading) }
            if step.timerMin > 0 { timerView(step, p) }
            Button { update { $0.toggle(step.index) } } label: {
                Label(p.doneSteps.contains(step.index) ? "Шаг выполнен" : "Отметить выполненным", systemImage: p.doneSteps.contains(step.index) ? "checkmark.circle.fill" : "circle")
                    .font(.system(.headline, design: .rounded)).foregroundStyle(Theme.accent)
            }
            HStack {
                SecondaryButton(title: "Назад", systemImage: "chevron.left") { update { $0.previous() } }
                Spacer()
                PrimaryButton(title: p.currentStep == total - 1 ? "Готово" : "Следующий шаг") {
                    if p.currentStep == total - 1 { update { $0.doneSteps.insert(step.index) }; dismiss() } else { update { $0.next(total: total) } }
                }.frame(maxWidth: 220)
            }
        }
        .padding(20).screenBackground()
        .onReceive(ticker) { now = $0 }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; if store.state.cookingProgress[rendered.recipe.id] == nil { update { _ in } } }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder private func timerView(_ step: RenderedStep, _ p: CookingProgress) -> some View {
        let remaining = p.remaining(step: step.index, now: now)
        HStack {
            Image(systemName: "timer").foregroundStyle(Theme.saffron)
            if let r = remaining, r > 0 {
                Text(String(format: "%02d:%02d", Int(r) / 60, Int(r) % 60)).font(Theme.number(34))
                Spacer()
                SecondaryButton(title: "Сбросить") { update { $0.timers[step.index] = nil }; UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timer-\(rendered.recipe.id)-\(step.index)"]) }
            } else if remaining == 0 {
                Text("Время вышло!").font(Theme.number(24)).foregroundStyle(Theme.tomato)
                Spacer()
                SecondaryButton(title: "Ещё раз") { startTimer(step) }
            } else {
                Text("\(step.timerMin) мин").font(Theme.number(24))
                Spacer()
                SecondaryButton(title: "Запустить таймер", systemImage: "play.fill") { startTimer(step) }
            }
        }.card(padding: 14)
    }

    private func startTimer(_ step: RenderedStep) {
        update { $0.startTimer(step: step.index, minutes: step.timerMin) }
        Task {
            _ = await Notifications.requestAuthorization()
            let c = UNMutableNotificationContent(); c.title = "Таймер: \(rendered.recipe.name)"; c.body = "Шаг \(step.index + 1) — время вышло"; c.sound = .default
            let t = UNTimeIntervalNotificationTrigger(timeInterval: Double(step.timerMin * 60), repeats: false)
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "timer-\(rendered.recipe.id)-\(step.index)", content: c, trigger: t))
        }
    }
}

struct CustomRecipeEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var servings = 2
    @State private var meal: MealType = .dinner
    @State private var items: [(key: String, amount: Double)] = []
    @State private var pickKey = "rice"
    @State private var pickAmount = ""
    @State private var stepsText = ""
    @State private var errors: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                Stepper("Порций: \(servings)", value: $servings, in: 1...20)
                Picker("Приём пищи", selection: $meal) { ForEach(MealType.allCases, id: \.self) { Text($0.title).tag($0) } }
                Section("Ингредиенты (из справочника)") {
                    ForEach(items.indices, id: \.self) { i in
                        let info = store.library.ingredients[items[i].key]
                        Text("\(info?.name ?? items[i].key) — \(Fmt.amount(items[i].amount, unit: info?.unit ?? .g))")
                    }.onDelete { items.remove(atOffsets: $0) }
                    Picker("Продукт", selection: $pickKey) { ForEach(store.library.ingredientList) { Text($0.name).tag($0.key) } }
                    HStack {
                        TextField("Количество (г / мл / шт)", text: $pickAmount).keyboardType(.decimalPad)
                        Button("Добавить") { if let a = Double(pickAmount.replacingOccurrences(of: ",", with: ".")), a > 0 { items.append((pickKey, a)); pickAmount = "" } }
                    }
                }
                Section("Шаги (каждый с новой строки)") { TextEditor(text: $stepsText).frame(minHeight: 120) }
                if !errors.isEmpty { Section { ForEach(errors, id: \.self) { Text($0).foregroundStyle(Theme.tomato) } } }
            }
            .navigationTitle("Свой рецепт").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Сохранить") { save() } }
            }
        }
    }

    private func save() {
        let steps = stepsText.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let draft = RecipeValidator.Draft(name: name, meals: [meal.rawValue], servings: servings, prep: 10, cook: 20,
                                          ingredients: items.map { RecipeValidator.DraftIngredient(key: $0.key, amount: $0.amount) }, steps: steps)
        let (r, errs) = RecipeValidator.validate(draft, library: store.library)
        if let r { store.addCustomRecipe(r); dismiss() } else { errors = errs }
    }
}
