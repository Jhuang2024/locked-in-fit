import Foundation
import UIKit

/// Optional AI enrichment for appearance check-ins. The AI adds observations,
/// suggestions, and a small bounded score nudge; it never owns the numeric
/// score, which always comes from the local AppearanceScoringService.
protocol AppearanceAIService {
    var providerName: String { get }
    /// context: compact plain-language summary of local metrics/scores (no identity data).
    func analyzeFace(image: UIImage, context: String) async throws -> AppearanceAIResult
    func analyzeBody(images: [UIImage], context: String) async throws -> AppearanceAIResult
}

/// Offline mock so the whole flow works without a key or network.
struct MockAppearanceAIService: AppearanceAIService {
    let providerName = "Mock (offline)"

    func analyzeFace(image: UIImage, context: String) async throws -> AppearanceAIResult {
        try await Task.sleep(for: .seconds(1.0))
        return AppearanceAIResult(
            scoreAdjustment: 0,
            confidence: 0.5,
            observations: [
                "[Mock] Face reads consistent with your recent check-ins.",
                "[Mock] No major changes since your last check-in."
            ],
            suggestions: [
                AppearanceAISuggestion(
                    title: "Add a 2-minute morning skincare routine",
                    category: "skin",
                    explanation: "Consistent basic skincare is the highest-evidence lever available for skin appearance.",
                    expectedImpact: "Steadier skin component over time.",
                    durationType: "short_term",
                    destination: "checklist",
                    priority: 3)
            ],
            unableToAssess: false)
    }

    func analyzeBody(images: [UIImage], context: String) async throws -> AppearanceAIResult {
        try await Task.sleep(for: .seconds(1.0))
        return AppearanceAIResult(
            scoreAdjustment: 0,
            confidence: 0.5,
            observations: ["[Mock] Composition reads consistent with your recent history."],
            suggestions: [],
            unableToAssess: false)
    }
}

extension AIServiceFactory {
    /// Picks the appearance analyzer. Same mode/key/model source as meal analysis.
    static func makeAppearance(settings: UserSettings?) -> AppearanceAIService {
        let mode = AIMode(rawValue: settings?.aiModeRaw ?? "mock") ?? .mock
        switch mode {
        case .mock:
            return MockAppearanceAIService()
        case .openRouter:
            guard KeychainService.openRouterAPIKey != nil else {
                return MockAppearanceAIService() // no valid key → automatic mock fallback
            }
            let model = settings?.aiModelName.trimmingCharacters(in: .whitespaces) ?? ""
            return OpenRouterAppearanceAIService(modelName: model.isEmpty ? "openai/gpt-4o-mini" : model)
        }
    }
}
