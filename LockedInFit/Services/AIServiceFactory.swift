import Foundation

/// Builds the BazaarLink-backed AI providers. There is no mode toggle and no
/// mock fallback anymore: analysis always goes to BazaarLink with the user's
/// key, and a missing key surfaces as a clear error at the call site instead
/// of silently producing fabricated numbers.
///
/// History: providers used to be gated on a persisted `aiModeRaw` setting
/// that defaulted to "mock" — so every time the app's container was replaced
/// (the recurring signing-churn data wipes), the mode silently reset to mock
/// even though the BazaarLink key survived in the Keychain, and every
/// analysis in the app quietly returned fake data. Deleting the mode (and
/// the mocks) removes that entire failure class. `aiModeRaw` remains on
/// UserSettings as an unused legacy field per the additive-only migration
/// policy.
enum AIServiceFactory {
    /// BazaarLink uses plain model IDs ("gpt-4o-mini"), not OpenRouter's
    /// provider-prefixed form ("openai/gpt-4o-mini"). The default must be a
    /// vision-capable model: meal photos, health scans, and appearance
    /// check-ins all send images. (BazaarLink's special "auto:free" routes
    /// to free models, but those aren't guaranteed to handle images — fine
    /// to set manually in AI Settings for text-only use, wrong as the
    /// app-wide default.)
    static let defaultModelName = "gpt-4o-mini"

    static func modelName(settings: UserSettings?) -> String {
        let model = settings?.aiModelName.trimmingCharacters(in: .whitespaces) ?? ""
        return model.isEmpty ? defaultModelName : model
    }

    static func make(settings: UserSettings?) -> FoodAIService {
        BazaarLinkFoodAIService(modelName: modelName(settings: settings))
    }

    static func makeHealthScan(settings: UserSettings?) -> HealthScanAIService {
        BazaarLinkHealthScanAIService(modelName: modelName(settings: settings))
    }

    static func makeMealNutritionAnalysis(settings: UserSettings?) -> MealNutritionAIService {
        BazaarLinkMealNutritionAIService(modelName: modelName(settings: settings))
    }
}
