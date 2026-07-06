import Foundation
import SwiftUI
import UIKit

@Observable
final class HealthScanAnalysisViewModel {
    enum Phase: Equatable {
        case pickingPhoto
        case ready
        case analyzing
        case reviewing
        case failed(String)
    }

    var phase: Phase = .pickingPhoto
    var image: UIImage?
    var productDescription = ""
    var estimate: HealthScanEstimate?
    var providerUsed = ""

    func analyze(settings: UserSettings?, forceMock: Bool = false) async {
        let text = productDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard image != nil || !text.isEmpty else { return }
        phase = .analyzing
        let service: HealthScanAIService = forceMock ? MockHealthScanAIService() : AIServiceFactory.makeHealthScan(settings: settings)
        providerUsed = service.providerName
        do {
            if let image {
                estimate = try await service.analyzeProduct(image: image)
            } else {
                estimate = try await service.analyzeProduct(description: text)
            }
            phase = .reviewing
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Builds the draft HealthScan (with saved photo) for review/editing. Not inserted here.
    func makeDraft() -> HealthScan? {
        guard let estimate else { return nil }
        let path = image.flatMap { ImageStore.save($0, prefix: "healthscan") }
        return estimate.makeDraft(photoPath: path)
    }
}
