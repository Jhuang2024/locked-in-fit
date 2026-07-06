import Foundation

/// Strict JSON contract returned by the AI (or mock) product-label analyzer.
struct HealthScanEstimate: Codable {
    var productName: String
    var servingSize: String
    var healthScore: Double
    var satietyScore: Double
    var processedLevel: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var sugar: Double
    var sodium: Double
    var confidence: Double
    var concerningIngredients: [String]
    var notes: String

    /// Build an unsaved HealthScan draft from the estimate. Caller reviews/edits before inserting.
    func makeDraft(date: Date = .now, photoPath: String? = nil) -> HealthScan {
        HealthScan(
            date: date,
            productName: productName,
            photoPath: photoPath,
            servingSize: servingSize,
            healthScore: healthScore,
            satietyScore: satietyScore,
            processedLevel: ProcessedLevel(rawValue: processedLevel) ?? .unknown,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            confidence: confidence,
            concerningIngredients: concerningIngredients,
            notes: notes
        )
    }
}
