import Foundation
import UIKit

/// Offline mock analyzer. Produces a realistic, varied set of product profiles
/// so the review/save flow can be tested without an API key.
struct MockHealthScanAIService: HealthScanAIService {
    let providerName = "Mock (offline)"

    private static let templates: [HealthScanEstimate] = [
        HealthScanEstimate(
            productName: "Chocolate Chip Granola Bar", servingSize: "1 bar (35g)",
            healthScore: 38, satietyScore: 25, processedLevel: "ultra_processed",
            calories: 150, protein: 2, carbs: 22, fat: 6, fiber: 1, sugar: 12, sodium: 95,
            confidence: 0.6,
            concerningIngredients: ["high-fructose corn syrup", "partially hydrogenated oil", "artificial flavor"],
            notes: "Marketed as healthy but closer to a candy bar nutritionally: high sugar, low protein and fiber won't keep you full."),
        HealthScanEstimate(
            productName: "Greek Yogurt (Plain, Whole Milk)", servingSize: "1 cup (245g)",
            healthScore: 84, satietyScore: 78, processedLevel: "minimally_processed",
            calories: 190, protein: 20, carbs: 9, fat: 9, fiber: 0, sugar: 9, sodium: 85,
            confidence: 0.7,
            concerningIngredients: [],
            notes: "High protein per calorie and minimally processed. The sugar here is naturally occurring lactose, not added."),
        HealthScanEstimate(
            productName: "Diet Cola", servingSize: "12 fl oz (355 ml)",
            healthScore: 30, satietyScore: 5, processedLevel: "ultra_processed",
            calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, sugar: 0, sodium: 40,
            confidence: 0.65,
            concerningIngredients: ["aspartame", "phosphoric acid", "caramel color"],
            notes: "Zero calories but no nutrition, and contains artificial sweeteners. Fine occasionally, not a health food."),
        HealthScanEstimate(
            productName: "Roasted Almonds (Unsalted)", servingSize: "1 oz (28g)",
            healthScore: 88, satietyScore: 82, processedLevel: "minimally_processed",
            calories: 170, protein: 6, carbs: 6, fat: 15, fiber: 3.5, sugar: 1, sodium: 0,
            confidence: 0.7,
            concerningIngredients: [],
            notes: "Whole-food fat and protein source. Calorie-dense, so watch portion size, but very filling per calorie for a snack."),
        HealthScanEstimate(
            productName: "Frozen Chicken Nuggets", servingSize: "6 pieces (100g)",
            healthScore: 45, satietyScore: 40, processedLevel: "processed",
            calories: 260, protein: 13, carbs: 17, fat: 16, fiber: 1, sugar: 1, sodium: 480,
            confidence: 0.55,
            concerningIngredients: ["sodium phosphate", "modified food starch"],
            notes: "Decent protein but heavily breaded and fried; sodium adds up fast if you eat a full serving.")
    ]

    func analyzeProduct(image: UIImage) async throws -> HealthScanEstimate {
        // Simulate a short analysis delay so the UI flow matches the real provider.
        try await Task.sleep(for: .seconds(1.2))
        return mockEstimate(source: "photo")
    }

    func analyzeProduct(description: String) async throws -> HealthScanEstimate {
        // Simulate a short analysis delay so the UI flow matches the real provider.
        try await Task.sleep(for: .seconds(0.8))
        return mockEstimate(source: "description")
    }

    private func mockEstimate(source: String) -> HealthScanEstimate {
        var estimate = Self.templates.randomElement()!
        estimate.notes = "[Mock estimate from \(source)] " + estimate.notes
        return estimate
    }

    func testConnection() async throws -> String {
        "Mock mode is always available. No network needed."
    }
}
