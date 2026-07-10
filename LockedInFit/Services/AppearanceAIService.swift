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

extension AIServiceFactory {
    /// Appearance analysis is opt-in and only offered by the check-in views
    /// when an OpenRouter or BazaarLink key exists; no mock, no fabricated
    /// observations.
    static func makeAppearance(settings: UserSettings?) -> AppearanceAIService {
        BazaarLinkAppearanceAIService(modelOverride: modelName(settings: settings))
    }
}
