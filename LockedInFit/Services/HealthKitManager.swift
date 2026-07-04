import Foundation
import HealthKit
import SwiftData

/// Reads steps, body mass, body fat %, and active energy from Apple Health.
/// Renpho data arrives here via Apple Health — no direct Renpho integration.
/// The app works fully without HealthKit permission; sync is opt-in.
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var lastSync: Date?
    var lastSyncSummary: String = ""
    var syncing = false

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        for id: HKQuantityTypeIdentifier in [.stepCount, .bodyMass, .bodyFatPercentage, .activeEnergyBurned] {
            if let type = HKObjectType.quantityType(forIdentifier: id) { types.insert(type) }
        }
        return types
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        let writeTypes: Set<HKSampleType> = HKObjectType.quantityType(forIdentifier: .bodyMass).map { [$0] } ?? []
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    /// Pull the last `days` of data into SwiftData, deduplicating by day+source.
    @MainActor
    func sync(days: Int = 60, context: ModelContext) async {
        guard isAvailable else { return }
        syncing = true
        defer { syncing = false }
        do {
            try await requestAuthorization()
            let steps = try await dailySteps(days: days)
            let weights = try await samples(.bodyMass, unit: .gramUnit(with: .kilo), days: days)
            let bodyFats = try await samples(.bodyFatPercentage, unit: .percent(), days: days)

            var imported = 0
            let hk = EntrySource.healthKit.rawValue

            let existingSteps = (try? context.fetch(FetchDescriptor<StepEntry>(
                predicate: #Predicate { $0.sourceRaw == hk }))) ?? []
            let stepDays = Set(existingSteps.map { $0.date.startOfDay })
            for (day, count) in steps where count > 0 {
                if let existing = existingSteps.first(where: { $0.date.startOfDay == day }) {
                    if existing.steps != count { existing.steps = count; imported += 1 }
                } else if !stepDays.contains(day) {
                    context.insert(StepEntry(date: day, steps: count, source: .healthKit))
                    imported += 1
                }
            }

            let existingWeights = (try? context.fetch(FetchDescriptor<BodyWeightEntry>(
                predicate: #Predicate { $0.sourceRaw == hk }))) ?? []
            let weightDates = Set(existingWeights.map(\.date))
            for sample in weights where !weightDates.contains(sample.date) {
                context.insert(BodyWeightEntry(date: sample.date, weightKg: sample.value, source: .healthKit))
                imported += 1
            }

            let existingFat = (try? context.fetch(FetchDescriptor<BodyFatEntry>(
                predicate: #Predicate { $0.sourceRaw == hk }))) ?? []
            let fatDates = Set(existingFat.map(\.date))
            for sample in bodyFats where !fatDates.contains(sample.date) {
                context.insert(BodyFatEntry(date: sample.date, bodyFatPercentage: sample.value * 100, source: .healthKit))
                imported += 1
            }

            lastSync = .now
            lastSyncSummary = imported > 0 ? "Imported \(imported) new entries." : "Already up to date."
        } catch {
            lastSyncSummary = "Sync failed: \(error.localizedDescription)"
        }
    }

    func writeWeight(_ kg: Double, date: Date) async {
        guard isAvailable, let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return }
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        try? await store.save(sample)
    }

    // MARK: - Queries

    private struct DatedValue { let date: Date; let value: Double }

    private func dailySteps(days: Int) async throws -> [(Date, Int)] {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return [] }
        let start = Date().daysAgo(days).startOfDay
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                var output: [(Date, Int)] = []
                results?.enumerateStatistics(from: start, to: .now) { stats, _ in
                    let count = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    output.append((stats.startDate.startOfDay, count))
                }
                continuation.resume(returning: output)
            }
            store.execute(query)
        }
    }

    private func samples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async throws -> [DatedValue] {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: Date().daysAgo(days), end: .now)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 500,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let values = (samples as? [HKQuantitySample])?.map {
                    DatedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                } ?? []
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
}
