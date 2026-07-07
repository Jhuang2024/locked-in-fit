import Foundation
import SwiftUI
import SwiftData
import UIKit

/// Drives the face/body check-in flows: validate → score locally → optional AI
/// enrichment → review → save. Mirrors MealAnalysisViewModel/HealthScanAnalysisViewModel.
/// Nothing is persisted until the user confirms on the review screen.
@Observable
final class AppearanceAnalysisViewModel {
    enum Phase: Equatable {
        case intro
        case pickingPhoto
        case validating
        case blocked
        case analyzing
        case reviewing
        case failed(String)
    }

    var phase: Phase = .intro

    // Face flow.
    var faceImage: UIImage?
    var validation: FacePhotoValidation?
    var faceResult: AppearanceScoringService.FaceScoreResult?

    // Body flow.
    var frontImage: UIImage?
    var sideImage: UIImage?
    var backImage: UIImage?
    var bodyResult: AppearanceScoringService.BodyScoreResult?

    // Shared.
    var aiResult: AppearanceAIResult?
    var providerUsed = ""
    var notes = ""
    /// Suggestions generated for the pending check-in; inserted on save.
    var draftSuggestions: [AppearanceSuggestion] = []
    /// The unsaved check-in shown on the review screen.
    var draftCheckIn: AppearanceCheckIn?

    var bodyImages: [UIImage] { [frontImage, sideImage, backImage].compactMap { $0 } }

    // MARK: - Face

    func validateFacePhoto() async {
        guard let faceImage else { return }
        phase = .validating
        let image = faceImage
        let result = await Task.detached(priority: .userInitiated) {
            FacePhotoValidator.validate(image: image)
        }.value
        validation = result
        phase = result.isUsable ? .pickingPhoto : .blocked
    }

    /// Score locally, optionally enrich with AI, and build the draft check-in.
    func analyzeFace(history: [AppearanceCheckIn],
                     context: SuggestionGenerationService.Context,
                     useAI: Bool) async {
        guard let faceImage, let validation, validation.isUsable else { return }
        phase = .analyzing

        let scores = AppearanceScoringService.scoreFace(metrics: validation.metrics, history: history)

        let checkIn = AppearanceCheckIn(kind: .face)
        checkIn.faceWidthHeightRatio = validation.metrics.widthHeightRatio
        apply(face: scores, to: checkIn)

        var suggestions = SuggestionGenerationService.faceSuggestions(
            result: scores, metrics: validation.metrics, checkIn: checkIn,
            history: history, context: context)

        if useAI {
            let service = AIServiceFactory.makeAppearance(settings: context.settings)
            providerUsed = service.providerName
            do {
                let summary = faceContextSummary(scores: scores, validation: validation)
                let ai = try await service.analyzeFace(image: faceImage, context: summary)
                aiResult = ai
                checkIn.totalScore = max(0, min(100, checkIn.totalScore + ai.clampedAdjustment))
                let aiSuggestions = ai.suggestions.map { $0.makeSuggestion(sourceKind: "face", checkInId: checkIn.uuid) }
                suggestions = SuggestionGenerationService.merge(local: suggestions, ai: aiSuggestions)
            } catch {
                // AI is enrichment only; local scoring stands on its own.
                providerUsed += " (unavailable: \(error.localizedDescription))"
            }
        }

        faceResult = scores
        draftCheckIn = checkIn
        draftSuggestions = suggestions
        phase = .reviewing
    }

    // MARK: - Body

    func analyzeBody(inputs: AppearanceScoringService.BodyScoreInputs,
                     context: SuggestionGenerationService.Context,
                     useAI: Bool) async {
        phase = .analyzing

        let scores = AppearanceScoringService.scoreBody(inputs: inputs)
        let checkIn = AppearanceCheckIn(kind: .body)
        apply(body: scores, to: checkIn)

        var suggestions = SuggestionGenerationService.bodySuggestions(
            result: scores, checkIn: checkIn, context: context)

        if useAI && !bodyImages.isEmpty {
            let service = AIServiceFactory.makeAppearance(settings: context.settings)
            providerUsed = service.providerName
            do {
                let summary = "Body score \(Int(scores.total))/100, confidence \(Formatters.percent(scores.confidence)). " +
                    scores.explanations.joined(separator: " ")
                let ai = try await service.analyzeBody(images: bodyImages, context: summary)
                aiResult = ai
                checkIn.totalScore = max(0, min(100, checkIn.totalScore + ai.clampedAdjustment))
                let aiSuggestions = ai.suggestions.map { $0.makeSuggestion(sourceKind: "body", checkInId: checkIn.uuid) }
                suggestions = SuggestionGenerationService.merge(local: suggestions, ai: aiSuggestions)
            } catch {
                providerUsed += " (unavailable: \(error.localizedDescription))"
            }
        }

        bodyResult = scores
        draftCheckIn = checkIn
        draftSuggestions = suggestions
        phase = .reviewing
    }

    // MARK: - Save

    /// Persists photos + check-in + suggestions. Call only from the review screen.
    /// Returns the saved check-in.
    @discardableResult
    func save(into modelContext: ModelContext) -> AppearanceCheckIn? {
        guard let draftCheckIn else { return nil }
        draftCheckIn.notes = notes
        if draftCheckIn.kind == .face {
            draftCheckIn.photoPath = faceImage.flatMap { ImageStore.save($0, prefix: "face") }
        } else {
            draftCheckIn.frontPhotoPath = frontImage.flatMap { ImageStore.save($0, prefix: "body-front") }
            draftCheckIn.sidePhotoPath = sideImage.flatMap { ImageStore.save($0, prefix: "body-side") }
            draftCheckIn.backPhotoPath = backImage.flatMap { ImageStore.save($0, prefix: "body-back") }
        }
        modelContext.insert(draftCheckIn)
        for suggestion in draftSuggestions {
            modelContext.insert(suggestion)
        }
        return draftCheckIn
    }

    // MARK: - Helpers

    private func apply(face scores: AppearanceScoringService.FaceScoreResult, to checkIn: AppearanceCheckIn) {
        checkIn.totalScore = scores.total
        checkIn.qualityScore = scores.quality
        checkIn.skinScore = scores.skin
        checkIn.symmetryScore = scores.symmetry
        checkIn.groomingScore = scores.grooming
        checkIn.puffinessScore = scores.puffiness
        checkIn.trendScore = scores.trend
        checkIn.confidence = scores.confidence
    }

    private func apply(body scores: AppearanceScoringService.BodyScoreResult, to checkIn: AppearanceCheckIn) {
        checkIn.totalScore = scores.total
        checkIn.compositionScore = scores.composition
        checkIn.muscularityScore = scores.leanMass
        checkIn.postureScore = scores.photoPosture
        checkIn.trendScore = scores.trendDirection
        checkIn.qualityScore = scores.quality
        checkIn.confidence = scores.confidence
    }

    private func faceContextSummary(scores: AppearanceScoringService.FaceScoreResult,
                                    validation: FacePhotoValidation) -> String {
        var parts = ["Local score \(Int(scores.total))/100, confidence \(Formatters.percent(scores.confidence))."]
        if !validation.warnings.isEmpty {
            parts.append("Warnings: " + validation.warnings.map(\.message).joined(separator: " "))
        }
        return parts.joined(separator: " ")
    }
}
