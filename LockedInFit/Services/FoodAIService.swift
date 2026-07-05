import Foundation
import UIKit

enum FoodAIError: LocalizedError {
    case noAPIKey
    case invalidResponse(String)
    case network(String)
    case parsing(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenRouter API key saved. Add one in Settings → AI Meal Analysis, or use the mock estimate."
        case .invalidResponse(let detail):
            return "The AI returned an unexpected response. \(detail)"
        case .network(let detail):
            return "Network request failed. \(detail)"
        case .parsing(let detail):
            return "Couldn't parse the AI's estimate. \(detail)"
        }
    }
}

/// Context passed along with the photo to improve estimates.
struct MealAnalysisContext {
    var mealType: MealType
    var userDescription: String
    var isLikelyHomeCooked: Bool

    init(mealType: MealType = .guess(), userDescription: String = "", isLikelyHomeCooked: Bool = true) {
        self.mealType = mealType
        self.userDescription = userDescription
        self.isLikelyHomeCooked = isLikelyHomeCooked
    }
}

/// Modular meal-analysis provider. Swap implementations via AIServiceFactory.
protocol FoodAIService {
    var providerName: String { get }
    func analyzeMeal(image: UIImage, context: MealAnalysisContext) async throws -> MealEstimate
    func analyzeMeal(description: String, context: MealAnalysisContext) async throws -> MealEstimate
    func testConnection() async throws -> String
}
