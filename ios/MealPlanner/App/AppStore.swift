import SwiftUI
import MealCore
import CoreLocation
import UserNotifications

@MainActor
final class AppStore: ObservableObject {
    @Published var state: AppState { didSet { scheduleSave() } }
    @Published var isGenerating = false
    @Published var phase = ""
    @Published var errorMessage: String?
    @Published var needsEstimateConsent = false
    @Published var searchingStores = false
    @Published var storeNote: String?
    @Published var catalogNotes: [String] = []
    @Published var storageNote: String?
    @Published var assistantBusy = false

    let library = Library.shared
    let planner = MealPlanner()
    let engine: AssistantEngine
    let backend: BackendClient?
    private let persistence: StateStore
    private var saveTask: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MealPlanner", isDirectory: true)
        persistence = StateStore(directory: base)
        engine = AssistantEngine(planner: planner)
        backend = BackendClient.fromBundle()
        switch persistence.load() {
        case .fresh: state = AppState()
        case .loaded(let s): state = s
        case .recoveredFromCorruption:
            state = AppState()
            storageNote = "Файл данных был повреждён. Копия сохранена рядом, приложение начато с чистого состояния."
        }
        for r in state.customRecipes { library.addRecipe(r) }
    }

    // MARK: Сохранение

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            do { try self.persistence.save(self.state) } catch { self.storageNote = "Не удалось сохранить данные: \(error.localizedDescription)" }
        }
    }

    func saveNow() { try? persistence.save(state) }

    func wipeAllData() {
        try? persistence.wipe()
        Keychain.delete("backend-token")
        UNUserNotificationCenterWrapper.clear()
        state = AppState()
        saveNow()
    }

    // MARK: Рецепты

    var allRecipes: [Recipe] { library.recipes }
    func recipe(_ id: String) -> Recipe? { library.recipeIndex[id] }

    func addCustomRecipe(_ r: Recipe) {
        library.addRecipe(r)
        state.customRecipes.removeAll { $0.id == r.id }
        state.customRecipes.append(r)
    }

    func toggleFavorite(_ id: String) {
        if state.favoriteRecipeIDs.contains(id) { state.favoriteRecipeIDs.remove(id) } else { state.favoriteRecipeIDs.insert(id) }
    }

    // MARK: Магазины

    func discoverStores(center: CLLocationCoordinate2D, radiusM: Double) async {
        searchingStores = true
        storeNote = nil
        defer { searchingStores = false }
        var radius = radiusM
        var merged: [StoreInfo] = []
        while true {
            async let mk = StoreSearchService.search(center: center, radiusM: radius)
            var lists: [[StoreInfo]] = [await mk]
            if let b = backend, let osm = try? await b.nearbyStores(lat: center.latitude, lon: center.longitude, radiusM: radius) { lists.append(osm) }
            merged = StoreDirectory.merge(lists, origin: (center.latitude, center.longitude))
            if let next = SearchRadius.next(after: radius, found: merged.count) {
                storeNote = "Рядом мало магазинов — расширяю радиус до \(SearchRadius.title(next))"
                radius = next
            } else { break }
        }
        state.searchRadiusM = radius
        // сохраняем выбор пользователя для уже известных магазинов
        state.knownStores = merged
        state.selectedStoreIDs = state.selectedStoreIDs.intersection(Set(merged.map { $0.id }))
        if merged.isEmpty { storeNote = "Магазины не найдены. Увеличьте радиус, укажите другой адрес или добавьте магазин вручную." }
        else if backend == nil { storeNote = (storeNote.map { $0 + ". " } ?? "") + "Источник: Apple Карты. Для полного охвата включите backend (OpenStreetMap)." }
    }

    func addManualStore(name: String, near center: CLLocationCoordinate2D) {
        let s = StoreInfo(id: "manual:\(UUID().uuidString)", name: name, chain: StoreDirectory.chain(forName: name), lat: center.latitude, lon: center.longitude, distanceM: 0,
                          shopType: "convenience", catalog: .unknown, source: "manual")
        state.knownStores.append(s)
        state.selectedStoreIDs.insert(s.id)
    }

    func toggleStore(_ id: String) {
        if state.selectedStoreIDs.contains(id) { state.selectedStoreIDs.remove(id) } else { state.selectedStoreIDs.insert(id) }
    }

    // MARK: Расчёт

    func planningStores() -> [StoreInfo] {
        var stores = state.selectedStores
        if !state.userPrices.isEmpty {
            let c = state.activeAddress
            stores.append(StoreInfo(id: "user", name: "Мои цены (введены вручную)", lat: c?.lat ?? 0, lon: c?.lon ?? 0, distanceM: 0, shopType: "other", catalog: .imported, source: "manual"))
        }
        return stores
    }

    func buildSettings(policyOverride: PricePolicy? = nil) -> PlanSettings {
        let d = state.draft
        return PlanSettings(days: d.days, budget: .rub(d.budgetRub), slots: d.slots, goal: d.goal, shoppingMode: d.mode, pricePolicy: policyOverride ?? d.pricePolicy,
                            unknownComposition: d.unknownComposition, avoidTraces: true, stageDays: d.stageDays, maxBatches: 3, variety: d.variety, startDate: Calendar.current.startOfDay(for: Date()))
    }

    func collectProducts(stores: [StoreInfo]) async -> [CatalogProduct] {
        var products = state.importedProducts
        products += state.userPrices.compactMap { $0.toProduct(library: library) }
        catalogNotes = []
        if let b = backend {
            let real = stores.filter { $0.id != "user" }
            if !real.isEmpty {
                do {
                    let r = try await b.offers(stores: real)
                    products += r.products
                    catalogNotes = r.notes ?? []
                } catch { catalogNotes = ["Не удалось загрузить каталоги с сервера: \(error.localizedDescription). Использую сохранённые данные."] }
            }
        } else {
            catalogNotes = ["Backend не подключён: цены берутся только из ваших файлов и ручного ввода."]
        }
        return products
    }

    func makeOffers(from products: [CatalogProduct], stores: [StoreInfo], people: [PersonProfile]) -> [Offer] {
        let allowed = Set(stores.map { $0.id })
        let allergens = Set(people.flatMap { $0.allergens })
        let builder = OfferBuilder(library: library, allergens: allergens, policy: state.draft.unknownComposition, avoidTraces: true, maxPriceAgeDays: 180)
        return builder.build(from: products.filter { allowed.contains($0.storeID) }).offers
    }

    func makeInput(offers: [Offer], stores: [StoreInfo], policy: PricePolicy? = nil) -> PlanInput {
        PlanInput(settings: buildSettings(policyOverride: policy), people: state.effectivePeople(count: state.draft.peopleCount), stores: stores, offers: offers,
                  pantry: state.pantry, kitchen: state.kitchen, extraRecipes: state.customRecipes)
    }

    /// Нижняя граница: что нужно сделать до расчёта.
    var readiness: [String] {
        var issues: [String] = []
        if state.selectedStoreIDs.isEmpty && state.userPrices.isEmpty && state.draft.pricePolicy == .verifiedOnly { issues.append("Выберите магазины (или разрешите ориентировочные цены).") }
        if !state.allergensAsked { issues.append("Ответьте на вопрос об аллергенах.") }
        if state.draft.budgetRub <= 0 { issues.append("Укажите бюджет больше нуля.") }
        if !state.kitchenConfirmed { issues.append("Подтвердите кухонную технику и посуду.") }
        return issues
    }

    func generatePlan(allowEstimates: Bool = false) async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        needsEstimateConsent = false
        defer { isGenerating = false; phase = "" }
        let stores = planningStores()
        let people = state.effectivePeople(count: state.draft.peopleCount)
        phase = "Загружаем каталоги и цены выбранных магазинов…"
        let products = await collectProducts(stores: stores)
        phase = "Проверяем аллергены в составе товаров…"
        let offers = makeOffers(from: products, stores: stores, people: people)
        let policy: PricePolicy = allowEstimates ? .allowEstimates : state.draft.pricePolicy
        let input = makeInput(offers: offers, stores: stores, policy: policy)
        phase = "Подбираем блюда, упаковки и магазины, проверяем бюджет…"
        let planner = self.planner
        let result: Result<MealPlan, Error> = await Task.detached(priority: .userInitiated) {
            do { return .success(try planner.plan(input)) } catch { return .failure(error) }
        }.value
        switch result {
        case .success(let plan):
            state.cachedOffers = offers
            state.cachedOffersDate = Date()
            state.plans.insert(plan, at: 0)
            if state.plans.count > 30 { state.plans.removeLast(state.plans.count - 30) }
            state.currentPlanID = plan.id
            state.checkedLines = []
            state.doneMeals = []
            state.onboardingDone = true
            await Notifications.reschedule(state: state, library: library)
        case .failure(let err):
            if case PlanError.noPriceData = err { needsEstimateConsent = true }
            errorMessage = (err as? LocalizedError)?.errorDescription ?? err.localizedDescription
        }
    }

    /// Вход для пересчётов по текущему плану (замены блюд, ассистент) — на сохранённых предложениях, работает офлайн.
    func currentInput() -> PlanInput? {
        guard let plan = state.currentPlan else { return nil }
        let stores = plan.stores.isEmpty ? planningStores() : plan.stores
        return PlanInput(settings: plan.settings, people: plan.people, stores: stores, offers: state.cachedOffers, pantry: state.pantry, kitchen: state.kitchen, extraRecipes: state.customRecipes + plan.extraRecipes)
    }

    func applyPlan(_ plan: MealPlan) {
        if let i = state.plans.firstIndex(where: { $0.id == state.currentPlanID }) { state.plans[i] = plan }
        else { state.plans.insert(plan, at: 0) }
        state.currentPlanID = plan.id
        // новый план — новый id; обновим текущий
    }

    func replaceCurrentPlan(with new: MealPlan) {
        let oldID = state.currentPlanID
        state.plans.removeAll { $0.id == oldID }
        state.plans.insert(new, at: 0)
        state.currentPlanID = new.id
        state.checkedLines = state.checkedLines
    }

    // MARK: Покупки и запасы

    func isLineChecked(_ l: PurchaseLine) -> Bool { state.checkedLines.contains(l.id) }

    /// Отметка «куплено» переносит продукты в «Мои продукты» (запасы) со сроком годности по справочнику.
    func toggleLine(_ l: PurchaseLine) {
        guard let info = library.ingredients[l.ingredientKey], let plan = state.currentPlan else { return }
        if state.checkedLines.contains(l.id) {
            state.checkedLines.remove(l.id)
            removePantry(key: l.ingredientKey, amount: Double(l.packs * l.packBase))
        } else {
            state.checkedLines.insert(l.id)
            let exp = Calendar.current.date(byAdding: .day, value: min(info.shelf, state.kitchen.hasFreezer ? max(info.shelf, info.frozen) : info.shelf), to: Date())
            state.pantry.append(PantryItem(ingredientKey: l.ingredientKey, amount: Double(l.packs * l.packBase), expiry: exp, storage: info.store))
        }
        _ = plan
    }

    func removePantry(key: String, amount: Double) {
        var left = amount
        let idx = state.pantry.indices.filter { state.pantry[$0].ingredientKey == key }.sorted { (state.pantry[$0].expiry ?? .distantFuture) < (state.pantry[$1].expiry ?? .distantFuture) }
        for i in idx where left > 0 {
            let take = min(left, state.pantry[i].amount)
            state.pantry[i].amount -= take
            left -= take
        }
        state.pantry.removeAll { $0.amount <= 0.5 }
    }

    /// Подтверждённое приготовление списывает ингредиенты из запасов.
    func confirmCooked(_ meal: PlannedMeal) {
        guard let r = recipe(meal.recipeID), let plan = state.currentPlan else { return }
        let rendered = RecipeRenderer.render(recipe: r, servings: meal.portions, library: library)
        for ing in rendered.ingredients { removePantry(key: ing.key, amount: ing.amountBase) }
        state.doneMeals.insert(meal.id)
        _ = plan
    }

    // MARK: Ассистент

    func sendToAssistant(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.chat.append(ChatMessage(fromUser: true, text: trimmed))
        guard let plan = state.currentPlan, let input = currentInput() else {
            state.chat.append(ChatMessage(fromUser: false, text: "Сначала создайте рацион — тогда я смогу его менять."))
            return
        }
        assistantBusy = true
        defer { assistantBusy = false }
        var intent = AssistantParser.parse(trimmed, plan: plan, library: library)
        if intent.action == .unknown, let b = backend {
            let ctx = BackendClient.AIContext(days: plan.settings.days, slots: plan.settings.slots.map { $0.name }, startDate: plan.settings.startDate,
                                              allergens: plan.people.flatMap { $0.allergens.map { $0.rawValue } },
                                              meals: plan.meals.map { .init(day: $0.day, slot: $0.slot, recipeID: $0.recipeID, name: $0.recipeName) })
            if let ai = try? await b.aiIntent(message: trimmed, context: ctx) { intent = ai }
        }
        let engine = self.engine
        let out: AssistantOutcome = await Task.detached(priority: .userInitiated) { engine.handle(intent: intent, input: input, plan: plan) }.value
        state.chat.append(ChatMessage(fromUser: false, text: out.message))
        if let p = out.updatedPlan { replaceCurrentPlan(with: p) }
    }

    func replaceMeal(day: Int, slot: Int, with recipeID: String) async -> String {
        guard let plan = state.currentPlan, let input = currentInput() else { return "Нет текущего рациона." }
        let key = SlotKey(day: day, slot: slot)
        var inp = engine.lockingAll(input: input, plan: plan, except: [key])
        inp.locked[key] = LockedChoice(recipeID: recipeID)
        let planner = self.planner
        let res: Result<MealPlan, Error> = await Task.detached { do { return .success(try planner.plan(inp)) } catch { return .failure(error) } }.value
        switch res {
        case .success(let p):
            let problems = PlanVerifier.verify(p, library: library, kitchen: state.kitchen)
            if !problems.isEmpty { return "Замена отклонена проверкой: \(problems.first ?? "")" }
            replaceCurrentPlan(with: p)
            return p.status == .overBudget ? "Заменено, но рацион вышел за бюджет — посмотрите советы." : "Блюдо заменено, бюджет и ограничения проверены."
        case .failure(let e): return (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
        }
    }

    // MARK: Импорт

    func importCatalog(data: Data, fileName: String, storeID: String) -> String {
        let isJSON = fileName.lowercased().hasSuffix(".json")
        let result: CatalogImport.Result
        if isJSON { result = CatalogImport.parseJSON(data, storeID: storeID) }
        else {
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) ?? ""
            result = CatalogImport.parseCSV(text, storeID: storeID)
        }
        state.importedProducts.removeAll { $0.storeID == storeID && $0.source.hasSuffix("-import") }
        state.importedProducts += result.products
        if let i = state.knownStores.firstIndex(where: { $0.id == storeID }) {
            state.knownStores[i].catalog = .imported
            state.knownStores[i].priceUpdatedAt = Date()
        }
        var msg = "Загружено товаров: \(result.products.count)."
        if !result.errors.isEmpty { msg += " Пропущено строк: \(result.errors.count). Первая ошибка: \(result.errors[0])" }
        return msg
    }
}

enum UNUserNotificationCenterWrapper {
    static func clear() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
