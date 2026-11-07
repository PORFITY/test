import Foundation

/// Аллерген. Стандартные идентификаторы + произвольные («custom:кешью»).
public struct Allergen: Hashable, Codable, Sendable, RawRepresentable, Identifiable {
    public let rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ raw: String) { self.rawValue = raw }

    public static let milk = Allergen("milk")
    public static let eggs = Allergen("eggs")
    public static let peanuts = Allergen("peanuts")
    public static let treeNuts = Allergen("tree_nuts")
    public static let fish = Allergen("fish")
    public static let shellfish = Allergen("shellfish")
    public static let soy = Allergen("soy")
    public static let wheat = Allergen("wheat")
    public static let gluten = Allergen("gluten")
    public static let sesame = Allergen("sesame")

    public static let standard: [Allergen] = [.milk, .eggs, .peanuts, .treeNuts, .fish, .shellfish, .soy, .wheat, .gluten, .sesame]

    public static func custom(_ text: String) -> Allergen {
        Allergen("custom:" + TextNorm.normalize(text))
    }
    public var isCustom: Bool { rawValue.hasPrefix("custom:") }

    public var title: String {
        switch rawValue {
        case "milk": return "Молоко и молочные продукты"
        case "eggs": return "Яйца"
        case "peanuts": return "Арахис"
        case "tree_nuts": return "Орехи (древесные)"
        case "fish": return "Рыба"
        case "shellfish": return "Морепродукты"
        case "soy": return "Соя"
        case "wheat": return "Пшеница"
        case "gluten": return "Глютен (пшеница, рожь, ячмень, овёс)"
        case "sesame": return "Кунжут"
        default: return isCustom ? String(rawValue.dropFirst(7)) : rawValue
        }
    }

    /// Ключевые основы слов (нормализованные, ё→е) для поиска в составе и названиях продуктов.
    public var keywords: [String] {
        switch rawValue {
        case "milk": return ["молок", "молоч", "сливк", "сливоч", "сыр", "сметан", "кефир", "творог", "йогурт", "ряженк", "простокваш", "лактоз", "сыворот", "казеин", "milk", "cream", "cheese", "butter", "whey", "casein", "lactose", "yogurt", "dairy"]
        case "eggs": return ["яйц", "яичн", "меланж", "альбумин", "egg", "albumin", "lysozyme", "меринг", "майонез"]
        case "peanuts": return ["арахис", "земляной орех", "peanut", "groundnut"]
        case "tree_nuts": return ["орех", "фундук", "миндал", "грецк", "кешью", "фисташк", "пекан", "макадам", "бразильск", "кедров", "almond", "hazelnut", "walnut", "cashew", "pistachio", "pecan", "macadamia", "пралин", "нуга"]
        case "fish": return ["рыб", "лосос", "семг", "форел", "тунец", "сельд", "треск", "минта", "хек", "скумбри", "анчоус", "шпрот", "горбуш", "сайр", "fish", "salmon", "tuna", "cod", "anchov", "herring", "mackerel", "pollock", "икра"]
        case "shellfish": return ["креветк", "краб", "мидии", "мидий", "кальмар", "осьминог", "омар", "лангуст", "устриц", "гребешок", "моллюск", "ракообраз", "морепродукт", "shrimp", "crab", "lobster", "mollus", "crustacean", "oyster", "squid", "shellfish", "seafood"]
        case "soy": return ["соя", "соев", "соевый", "тофу", "edamame", "эдамаме", "soy", "tofu"]
        case "wheat": return ["пшениц", "мука пшен", "манн", "семолин", "булгур", "кускус", "хлеб", "батон", "макарон", "спагетти", "wheat", "semolina", "bulgur", "couscous", "spelt", "durum"]
        case "gluten": return ["глютен", "клейковин", "пшениц", "рожь", "ржан", "ячмен", "овес", "овся", "манн", "булгур", "кускус", "солод", "gluten", "wheat", "rye", "barley", "oat", "malt", "semolina", "spelt"]
        case "sesame": return ["кунжут", "тахин", "sesame", "tahini"]
        default:
            return isCustom ? [String(rawValue.dropFirst(7))] : [rawValue]
        }
    }

    /// Соответствие тегам Open Food Facts (en:milk, en:peanuts, ...).
    public var offTags: [String] {
        switch rawValue {
        case "milk": return ["en:milk"]
        case "eggs": return ["en:eggs"]
        case "peanuts": return ["en:peanuts"]
        case "tree_nuts": return ["en:nuts"]
        case "fish": return ["en:fish"]
        case "shellfish": return ["en:crustaceans", "en:molluscs"]
        case "soy": return ["en:soybeans"]
        case "wheat": return ["en:gluten"]   // OFF не различает пшеницу и глютен — безопасная сторона
        case "gluten": return ["en:gluten"]
        case "sesame": return ["en:sesame-seeds"]
        default: return []
        }
    }
}

public enum UnknownCompositionPolicy: String, Codable, Sendable {
    /// Допустить товар, но пометить «состав не подтверждён».
    case allowWithWarning
    /// Исключить товары, по которым нет данных о составе (для переработанных продуктов).
    case exclude
}

public enum AllergenVerdict: Equatable, Sendable {
    case safe                       // состав известен, аллергенов нет
    case contains([Allergen])       // содержит
    case mayContain([Allergen])     // возможны следы
    case unknown                    // нет данных о составе — безопасность не гарантируется

    public var isBlocked: Bool {
        switch self { case .contains, .mayContain: return true; default: return false }
    }
}

public enum AllergenChecker {
    /// Аллергены, присутствующие в ингредиенте справочника (по базовому составу).
    public static func ingredientContains(_ info: IngredientInfo, _ allergens: Set<Allergen>) -> [Allergen] {
        var out: [Allergen] = []
        for a in allergens {
            if info.allergens.contains(a.rawValue) { out.append(a); continue }
            if a.isCustom {
                let norm = TextNorm.normalize(info.name + " " + info.key)
                if a.keywords.contains(where: { !$0.isEmpty && norm.contains($0) }) { out.append(a) }
            }
            // пшеница ⊂ глютен: если у пользователя глютен, то ингредиенты с пометкой wheat тоже содержат глютен
            if a == .gluten && info.allergens.contains("wheat") { out.append(a) }
        }
        return out
    }

    /// Проверка конкретного товара из каталога.
    public static func evaluate(product: CatalogProduct, ingredient: IngredientInfo?, allergens: Set<Allergen>, avoidTraces: Bool = true, policy: UnknownCompositionPolicy = .allowWithWarning) -> AllergenVerdict {
        guard !allergens.isEmpty else { return .safe }
        var contains: [Allergen] = []
        var traces: [Allergen] = []
        let fullText = TextNorm.normalize(product.ingredientsText ?? "")
        // состав делится на основную часть и «может содержать / следы»
        var text = fullText
        var traceText = ""
        let markers = ["может содержать", "may contain", "следы", "traces", "produced in a facility", "на производстве"]
        var cut: String.Index?
        for mk in markers { if let r = fullText.range(of: mk), cut == nil || r.lowerBound < cut! { cut = r.lowerBound } }
        if let c = cut { text = String(fullText[..<c]); traceText = String(fullText[c...]) }
        let tags = Set(product.allergenTags.map { $0.lowercased() })
        let traceTags = Set(product.traceTags.map { $0.lowercased() })
        let nameNorm = TextNorm.normalize(product.name)
        let hasText = !fullText.isEmpty
        let hasTags = !tags.isEmpty || !traceTags.isEmpty

        for a in allergens {
            var hit = false
            if a.offTags.contains(where: { tags.contains($0) }) { hit = true }
            if hasText, a.keywords.contains(where: { !$0.isEmpty && text.contains($0) }) { hit = true }
            // название товара тоже учитываем (например «Сыр», «Арахисовая паста»), кроме собственных слов ингредиента-родителя
            if a.keywords.contains(where: { !$0.isEmpty && nameNorm.contains($0) }) && !(ingredient.map { !AllergenChecker.ingredientContains($0, [a]).isEmpty } ?? false) {
                hit = true
            }
            if hit { contains.append(a); continue }
            if avoidTraces {
                if a.offTags.contains(where: { traceTags.contains($0) }) { traces.append(a) }
                else if !traceText.isEmpty, a.keywords.contains(where: { !$0.isEmpty && traceText.contains($0) }) { traces.append(a) }
            }
        }
        // Базовые аллергены ингредиента справочника (например, макароны содержат пшеницу)
        if let ing = ingredient {
            for a in ingredientContains(ing, allergens) where !contains.contains(a) { contains.append(a) }
        }
        if !contains.isEmpty { return .contains(contains) }
        if !traces.isEmpty { return .mayContain(traces) }

        // состав неизвестен?
        let compositionKnown = hasText
        _ = hasTags
        if !compositionKnown {
            if let ing = ingredient, !ing.isProcessed { return .safe }  // сырые продукты (овощи, мясо, яйца): без состава допустимо
            return .unknown
        }
        return .safe
    }
}
