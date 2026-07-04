import Foundation

enum AIMode: String, CaseIterable, Identifiable {
    case mock
    case openRouter = "open_router"

    var id: String { rawValue }
    var label: String { self == .mock ? "Mock (offline)" : "OpenRouter" }
}

/// Picks the meal-analysis provider. Falls back to mock when no valid key exists.
enum AIServiceFactory {
    static func make(settings: UserSettings?) -> FoodAIService {
        let mode = AIMode(rawValue: settings?.aiModeRaw ?? "mock") ?? .mock
        switch mode {
        case .mock:
            return MockFoodAIService()
        case .openRouter:
            guard KeychainService.openRouterAPIKey != nil else {
                return MockFoodAIService() // no valid key → automatic mock fallback
            }
            let model = settings?.aiModelName.trimmingCharacters(in: .whitespaces) ?? ""
            return OpenRouterFoodAIService(modelName: model.isEmpty ? "openai/gpt-4o-mini" : model)
        }
    }
}
