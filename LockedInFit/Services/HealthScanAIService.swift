import Foundation
import UIKit

/// Modular product-label analysis provider. Swap implementations via AIServiceFactory.
protocol HealthScanAIService {
    var providerName: String { get }
    func analyzeProduct(image: UIImage) async throws -> HealthScanEstimate
    func analyzeProduct(description: String) async throws -> HealthScanEstimate
    func testConnection() async throws -> String
}
