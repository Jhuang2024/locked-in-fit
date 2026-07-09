import Foundation
import SwiftUI
import UIKit

@Observable
final class MealAnalysisViewModel {
    enum Phase: Equatable {
        case pickingPhoto
        case ready
        case analyzing
        case reviewing
        case failed(String)
    }

    var phase: Phase = .pickingPhoto
    /// One meal can be logged from several photos (multiple dishes, or the
    /// same spread from different angles); they're all analyzed together
    /// into a single combined estimate.
    var images: [UIImage] = []
    var mealType: MealType = .guess()
    var userDescription = ""
    var isHomeCooked = true
    var estimate: MealEstimate?
    var providerUsed = ""

    func analyze(settings: UserSettings?) async {
        guard !images.isEmpty else { return }
        phase = .analyzing
        let service: FoodAIService = AIServiceFactory.make(settings: settings)
        providerUsed = service.providerName
        do {
            let context = MealAnalysisContext(mealType: mealType,
                                              userDescription: userDescription,
                                              isLikelyHomeCooked: isHomeCooked)
            estimate = try await service.analyzeMeal(images: images, context: context)
            phase = .reviewing
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Builds the draft MealLog (with all photos saved) for review/editing.
    /// Not inserted here. First photo becomes the primary/thumbnail photo;
    /// the rest go to extraPhotoPaths. `presets` lets any estimated item
    /// matching a saved preset by name default to the preset's own numbers
    /// (see MealEstimate.makeDraft).
    func makeDraft(presets: [FoodPreset] = []) -> MealLog? {
        guard let estimate else { return nil }
        let paths = images.compactMap { ImageStore.save($0, prefix: "meal") }
        let draft = estimate.makeDraft(photoPath: paths.first, presets: presets)
        draft.extraPhotoPaths = Array(paths.dropFirst())
        draft.mealType = mealType
        return draft
    }
}
