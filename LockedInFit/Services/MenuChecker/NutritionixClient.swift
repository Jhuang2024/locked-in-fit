import Foundation

enum NutritionixError: LocalizedError {
    case noCredentials
    case http(Int)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "No Nutritionix App ID / App Key saved. Add them in Settings → AI Analysis."
        case .http(let code): return "Nutritionix returned HTTP \(code)."
        case .network(let d): return "Nutritionix request failed. \(d)"
        case .decoding(let d): return "Couldn't read the Nutritionix response. \(d)"
        }
    }
}

// MARK: - Response models

struct NutritionixInstantResponse: Decodable {
    struct Photo: Decodable { var thumb: String? }
    struct Common: Decodable { var food_name: String; var photo: Photo? }
    struct Branded: Decodable {
        var food_name: String
        var brand_name: String?
        var nix_item_id: String?
        var nf_calories: Double?
        var serving_qty: Double?
        var serving_unit: String?
        var photo: Photo?
    }
    var common: [Common]?
    var branded: [Branded]?
}

struct NutritionixItemResponse: Decodable { var foods: [NutritionixFood] }

struct NutritionixFood: Decodable {
    var food_name: String?
    var brand_name: String?
    var nf_calories: Double?
    var nf_protein: Double?
    var nf_total_carbohydrate: Double?
    var nf_total_fat: Double?
    var nf_dietary_fiber: Double?
    var nf_sodium: Double?
    var serving_qty: Double?
    var serving_unit: String?
    var photo: NutritionixInstantResponse.Photo?

    /// Official nutrition for one serving as published by the brand.
    var resolvedNutrition: ResolvedNutrition {
        ResolvedNutrition(
            calories: nf_calories ?? 0,
            protein: nf_protein ?? 0,
            carbs: nf_total_carbohydrate ?? 0,
            fat: nf_total_fat ?? 0,
            fiber: nf_dietary_fiber ?? 0,
            sodium: nf_sodium ?? 0)
    }
}

/// Thin client for the Nutritionix Track API. Provides official branded /
/// restaurant nutrition and a natural-language nutrition endpoint. Credentials
/// live in the Keychain (App ID + App Key), never in the database.
struct NutritionixClient {
    static let baseURL = "https://trackapi.nutritionix.com"
    let appID: String
    let appKey: String

    /// Returns nil when credentials aren't configured, so callers can cleanly
    /// fall back to AI estimation.
    init?(appID: String? = KeychainService.nutritionixAppID,
          appKey: String? = KeychainService.nutritionixAppKey) {
        guard let appID, let appKey else { return nil }
        self.appID = appID
        self.appKey = appKey
    }

    private func makeRequest(path: String, method: String, query: [String: String] = [:], body: [String: Any]? = nil) throws -> URLRequest {
        var components = URLComponents(string: NutritionixClient.baseURL + path)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw NutritionixError.network("Bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(appID, forHTTPHeaderField: "x-app-id")
        request.setValue(appKey, forHTTPHeaderField: "x-app-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func run<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NutritionixError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NutritionixError.http(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NutritionixError.decoding(error.localizedDescription)
        }
    }

    /// Instant search — returns branded (restaurant/product) and common foods.
    func instantSearch(_ query: String) async throws -> NutritionixInstantResponse {
        let request = try makeRequest(path: "/v2/search/instant", method: "GET",
                                      query: ["query": query])
        return try await run(request, as: NutritionixInstantResponse.self)
    }

    /// Full nutrition for a specific branded item.
    func item(nixItemID: String) async throws -> NutritionixFood? {
        let request = try makeRequest(path: "/v2/search/item", method: "GET",
                                      query: ["nix_item_id": nixItemID])
        return try await run(request, as: NutritionixItemResponse.self).foods.first
    }

    /// Natural-language nutrition for common (non-branded) foods, e.g. a
    /// free-text dish description. Used as a middle tier before AI estimation.
    func naturalNutrients(_ query: String) async throws -> [NutritionixFood] {
        let request = try makeRequest(path: "/v2/natural/nutrients", method: "POST",
                                      body: ["query": query])
        return try await run(request, as: NutritionixItemResponse.self).foods
    }

    /// Lightweight connectivity/credential check for the Settings screen.
    func testConnection() async throws -> String {
        let result = try await instantSearch("chicken")
        let count = (result.branded?.count ?? 0) + (result.common?.count ?? 0)
        return "Connected to Nutritionix (\(count) results for a test query)"
    }
}
