import Foundation

/// Builds the AI providers, all routed through AIGatewayClient (OpenRouter
/// first, falling back to BazaarLink). There is no mode toggle and no mock
/// fallback anymore: analysis always goes out with whichever gateway key
/// actually works, and having neither key surfaces as a clear error at the
/// call site instead of silently producing fabricated numbers.
///
/// History: providers used to be gated on a persisted `aiModeRaw` setting
/// that defaulted to "mock", so every time the app's container was replaced
/// (the recurring signing-churn data wipes), the mode silently reset to mock
/// even though the API key survived in the Keychain, and every analysis in
/// the app quietly returned fake data. Deleting the mode (and the mocks)
/// removes that entire failure class. `aiModeRaw` remains on UserSettings as
/// an unused legacy field per the additive-only migration policy.
enum AIServiceFactory {
    /// The single user-facing model override from AI Settings, or nil if
    /// left blank. Deliberately NOT resolved to a concrete model ID here:
    /// AIGatewayClient resolves per-provider (OpenRouter's "openrouter/free"
    /// vs BazaarLink's "auto:free") so ordinary AI analysis costs nothing by
    /// default no matter which gateway ends up serving the request. An
    /// explicit override, if set, is tried on whichever provider succeeds;
    /// free-tier models aren't guaranteed to be vision-capable, so photo
    /// features (meal photos, health scans, appearance check-ins) may need a
    /// vision-capable override (e.g. "gpt-4o-mini") to work reliably.
    static func modelName(settings: UserSettings?) -> String? {
        let model = settings?.aiModelName.trimmingCharacters(in: .whitespaces) ?? ""
        return model.isEmpty ? nil : model
    }

    static func make(settings: UserSettings?) -> FoodAIService {
        BazaarLinkFoodAIService(modelOverride: modelName(settings: settings))
    }

    static func makeHealthScan(settings: UserSettings?) -> HealthScanAIService {
        BazaarLinkHealthScanAIService(modelOverride: modelName(settings: settings))
    }

    static func makeMealNutritionAnalysis(settings: UserSettings?) -> MealNutritionAIService {
        BazaarLinkMealNutritionAIService(modelOverride: modelName(settings: settings))
    }
}
