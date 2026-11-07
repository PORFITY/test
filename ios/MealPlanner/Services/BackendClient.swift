import Foundation
import MealCore

/// Клиент backend (каталоги, расширенный поиск магазинов, AI). Секретных ключей в приложении нет:
/// ключи AI и каталогов хранятся только на сервере. Токен доступа (если задан) лежит в Keychain.
struct BackendClient {
    let baseURL: URL
    var token: String?

    enum BackendError: LocalizedError {
        case http(Int, String)
        var errorDescription: String? { if case .http(let c, let m) = self { return "Сервер вернул \(c): \(m)" }; return nil }
    }

    static func fromBundle() -> BackendClient? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
              !s.trimmingCharacters(in: .whitespaces).isEmpty, let url = URL(string: s), url.scheme == "https" else { return nil }
        return BackendClient(baseURL: url, token: Keychain.read("backend-token"))
    }

    private var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    private var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }

    private func request(_ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, timeoutInterval: 30)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpMethod = "POST"; req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BackendError.http(http.statusCode, String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        return data
    }

    func nearbyStores(lat: Double, lon: Double, radiusM: Double) async throws -> [StoreInfo] {
        let data = try await request("v1/stores/nearby", query: [
            URLQueryItem(name: "lat", value: String(lat)), URLQueryItem(name: "lon", value: String(lon)), URLQueryItem(name: "radius", value: String(Int(radiusM)))])
        return try decoder.decode(StoresResponse.self, from: data).stores
    }

    func offers(stores: [StoreInfo]) async throws -> OffersResponse {
        let body = try encoder.encode(OffersRequest(stores: stores, country: Locale.current.region?.identifier.lowercased() ?? "ru"))
        return try decoder.decode(OffersResponse.self, from: try await request("v1/catalog/offers", body: body))
    }

    func aiIntent(message: String, context: AIContext) async throws -> AssistantIntent {
        let body = try encoder.encode(AIRequest(message: message, context: context))
        return try decoder.decode(AssistantIntent.self, from: try await request("v1/ai/intent", body: body))
    }

    struct StoresResponse: Codable { var stores: [StoreInfo] }
    struct OffersRequest: Codable { var stores: [StoreInfo]; var country: String }
    struct OffersResponse: Codable { var products: [CatalogProduct]; var notes: [String]? }
    struct AIContext: Codable { var days: Int; var slots: [String]; var startDate: Date; var allergens: [String]; var meals: [AIMeal] }
    struct AIMeal: Codable { var day: Int; var slot: Int; var recipeID: String; var name: String }
    struct AIRequest: Codable { var message: String; var context: AIContext }
}
