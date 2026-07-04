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
    var image: UIImage?
    var mealType: MealType = .guess()
    var userDescription = ""
    var isChineseFood = true
    var estimate: MealEstimate?
    var providerUsed = ""

    func analyze(settings: UserSettings?, forceMock: Bool = false) async {
        guard let image else { return }
        phase = .analyzing
        let service: FoodAIService = forceMock ? MockFoodAIService() : AIServiceFactory.make(settings: settings)
        providerUsed = service.providerName
        do {
            let context = MealAnalysisContext(mealType: mealType,
                                              userDescription: userDescription,
                                              isLikelyChineseHomeCooked: isChineseFood)
            estimate = try await service.analyzeMeal(image: image, context: context)
            phase = .reviewing
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Builds the draft MealLog (with saved photo) for review/editing. Not inserted here.
    func makeDraft() -> MealLog? {
        guard let estimate else { return nil }
        let path = image.flatMap { ImageStore.save($0, prefix: "meal") }
        let draft = estimate.makeDraft(photoPath: path)
        draft.mealType = mealType
        return draft
    }
}
