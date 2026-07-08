import Foundation

/// Builds the OpenRouter-backed AI providers. There is no mode toggle and no
/// mock fallback anymore: analysis always goes to OpenRouter with the user's
/// key, and a missing key surfaces as a clear error at the call site instead
/// of silently producing fabricated numbers.
///
/// History: providers used to be gated on a persisted `aiModeRaw` setting
/// that defaulted to "mock" — so every time the app's container was replaced
/// (the recurring signing-churn data wipes), the mode silently reset to mock
/// even though the OpenRouter key survived in the Keychain, and every
/// analysis in the app quietly returned fake data. Deleting the mode (and
/// the mocks) removes that entire failure class. `aiModeRaw` remains on
/// UserSettings as an unused legacy field per the additive-only migration
/// policy.
enum AIServiceFactory {
    static let defaultModelName = "openai/gpt-4o-mini"

    static func modelName(settings: UserSettings?) -> String {
        let model = settings?.aiModelName.trimmingCharacters(in: .whitespaces) ?? ""
        return model.isEmpty ? defaultModelName : model
    }

    static func make(settings: UserSettings?) -> FoodAIService {
        OpenRouterFoodAIService(modelName: modelName(settings: settings))
    }

    static func makeHealthScan(settings: UserSettings?) -> HealthScanAIService {
        OpenRouterHealthScanAIService(modelName: modelName(settings: settings))
    }

    static func makeMealNutritionAnalysis(settings: UserSettings?) -> MealNutritionAIService {
        OpenRouterMealNutritionAIService(modelName: modelName(settings: settings))
    }
}
