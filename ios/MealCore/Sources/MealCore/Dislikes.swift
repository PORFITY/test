import Foundation

/// Сопоставляет свободный текст («грибы», «печень», «рыба») с ингредиентами справочника.
public struct DislikeResolver: Sendable {
    public let library: Library
    public init(library: Library) { self.library = library }

    static func stem(_ t: String) -> String {
        let n = t.count
        if n <= 3 { return t }
        return String(t.prefix(max(3, n - 2)))
    }

    /// Дополнительные слова-группы для ингредиента (мясо, птица, рыба, морепродукты…).
    static func groupWords(_ info: IngredientInfo) -> [String] {
        var w: [String] = []
        switch info.cat {
        case "meat": w += ["мясо", "мясн", "мясные"]
        case "fish": w += ["рыб"]
        case "dairy": w += ["молочн", "молочка"]
        default: break
        }
        if info.key.hasPrefix("chicken") { w += ["птиц", "курин", "курица", "курицу"] }
        if info.key == "sausage" { w += ["колбас", "сосиск", "колбасные"] }
        if info.key == "shrimp" { w += ["морепродукт", "креветк"]; w.removeAll { $0 == "рыб" } }
        if info.key == "pork" || info.key == "mixed_mince" { w += ["свинин", "свиной"] }
        if info.key == "mushrooms" { w += ["гриб"] }
        if info.key == "chicken_liver" { w += ["печен", "субпродукт"] }
        if info.key == "canned_tuna" || info.key == "pollock" || info.key == "pink_salmon" { w += ["рыб"] }
        if info.key == "egg" { w += ["яйц", "яиц"] }
        return w
    }

    /// Ключи ингредиентов, подходящих под текст.
    public func ingredientKeys(for text: String) -> Set<String> {
        let tokens = TextNorm.tokens(text)
        guard !tokens.isEmpty else { return [] }
        var result = Set<String>()
        for info in library.ingredientList {
            var words = TextNorm.tokens(info.name)
            for k in info.kw { words += TextNorm.tokens(k.replacingOccurrences(of: "=", with: "")) }
            words += Self.groupWords(info)
            for tok in tokens where tok.count >= 3 {
                let s = Self.stem(tok)
                if words.contains(where: { $0.hasPrefix(s) }) { result.insert(info.key); break }
            }
        }
        return result
    }

    /// Совпадает ли название рецепта с текстом (например «суп», «борщ»).
    public func matchesRecipeName(_ recipe: Recipe, text: String) -> Bool {
        let nameWords = TextNorm.tokens(recipe.name)
        for tok in TextNorm.tokens(text) where tok.count >= 3 {
            let s = Self.stem(tok)
            if nameWords.contains(where: { $0.hasPrefix(s) }) { return true }
        }
        return false
    }
}
