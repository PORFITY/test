import Foundation

public struct SavedAddress: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var city: String?
    public var lat: Double
    public var lon: Double
    public init(id: UUID = UUID(), title: String, city: String? = nil, lat: Double, lon: Double) { self.id = id; self.title = title; self.city = city; self.lat = lat; self.lon = lon }
}

public struct PurchaseRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var storeName: String
    public var amount: Money
    public var planID: UUID?
    public var note: String?
    public init(id: UUID = UUID(), date: Date = Date(), storeName: String, amount: Money, planID: UUID? = nil, note: String? = nil) {
        self.id = id; self.date = date; self.storeName = storeName; self.amount = amount; self.planID = planID; self.note = note
    }
}

public struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var fromUser: Bool
    public var text: String
    public var date: Date
    public init(id: UUID = UUID(), fromUser: Bool, text: String, date: Date = Date()) { self.id = id; self.fromUser = fromUser; self.text = text; self.date = date }
}

public struct Reminders: Codable, Hashable, Sendable {
    public var cookingEnabled: Bool = false
    public var cookingHour: Int = 17
    public var expiryEnabled: Bool = true
    public var priceChangeEnabled: Bool = false
    public init() {}
}

/// Параметры мастера создания рациона (черновик).
public struct WizardDraft: Codable, Hashable, Sendable {
    public var days: Int = 7
    public var budgetRub: Int = 7000
    public var peopleCount: Int = 2
    public var mealCount: Int = 3
    public var slots: [MealSlotConfig] = MealSlotConfig.defaults(count: 3)
    public var goal: DietGoal = .balanced
    public var mode: ShoppingMode = .balanced
    public var pricePolicy: PricePolicy = .verifiedOnly
    public var unknownComposition: UnknownCompositionPolicy = .allowWithWarning
    public var stageDays: Int? = nil
    public var variety: Double = 0.6
    public init() {}
}

/// Всё состояние приложения. Хранится локально (офлайн), может быть полностью удалено.
public struct AppState: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var onboardingDone: Bool = false
    public var allergensAsked: Bool = false
    public var people: [PersonProfile] = [PersonProfile(name: "Я")]
    public var kitchen: Kitchen = .starter
    public var kitchenConfirmed: Bool = false
    public var draft: WizardDraft = WizardDraft()
    public var addresses: [SavedAddress] = []
    public var activeAddressID: UUID?
    public var searchRadiusM: Double = 3000
    public var knownStores: [StoreInfo] = []
    public var selectedStoreIDs: Set<String> = []
    public var pantry: [PantryItem] = []
    public var userPrices: [UserPrice] = []
    public var importedProducts: [CatalogProduct] = []
    public var plans: [MealPlan] = []
    public var currentPlanID: UUID?
    public var favoriteRecipeIDs: Set<String> = []
    public var customRecipes: [Recipe] = []
    public var purchaseRecords: [PurchaseRecord] = []
    public var checkedLines: Set<String> = []
    public var cookingProgress: [String: CookingProgress] = [:]
    public var doneMeals: Set<String> = []
    public var chat: [ChatMessage] = []
    public var reminders: Reminders = Reminders()
    public var lockedChoices: [String: LockedChoice] = [:]     // "d-s" → закрепление (замены пользователя)

    public init() {}

    public var currentPlan: MealPlan? { plans.first { $0.id == currentPlanID } ?? plans.first }
    public var activeAddress: SavedAddress? { addresses.first { $0.id == activeAddressID } ?? addresses.first }
    public var selectedStores: [StoreInfo] { knownStores.filter { selectedStoreIDs.contains($0.id) } }
}

public final class StateStore {
    public let url: URL
    public init(directory: URL, fileName: String = "state.json") {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(fileName)
    }

    static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    public enum LoadResult { case fresh, loaded(AppState), recoveredFromCorruption(URL) }

    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .fresh }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try Self.decoder().decode(AppState.self, from: data))
        } catch {
            // не теряем данные пользователя молча: повреждённый файл сохраняем рядом
            let backup = url.deletingLastPathComponent().appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return .recoveredFromCorruption(backup)
        }
    }

    public func save(_ state: AppState) throws {
        let data = try Self.encoder().encode(state)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    /// Полное удаление сохранённых данных пользователя.
    public func wipe() throws {
        let dir = url.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for i in items where i.lastPathComponent.hasPrefix("state") { try FileManager.default.removeItem(at: i) }
    }
}
