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
    /// BazaarLink's special "auto:free" routing ID: every request is
    /// automatically routed to an available free model, so AI analysis
    /// costs nothing by default. Deliberate trade-off: free-tier models
    /// aren't guaranteed to be vision-capable, so photo features (meal
    /// photos, health scans, appearance check-ins) can fail under it — in
    /// that case set an explicit vision-capable model ID (e.g.
    /// "gpt-4o-mini") in AI Settings, which overrides this default.
    static let defaultModelName = "auto:free"

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
