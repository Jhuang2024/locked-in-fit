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
    var autoSyncEnabled = false

    private var container: ModelContainer?
    private var observerQueries: [HKObserverQuery] = []
    private var foregroundTimer: Timer?

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

    // MARK: - Auto sync

    /// Wires the manager to the app's SwiftData store, then starts both the
    /// event-driven background path and the always-on foreground refresh loop.
    @MainActor
    func configureAutoSync(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        startForegroundAutoSync()
        Task {
            try? await requestAuthorization()
            startBackgroundObservers()
        }
    }

    /// Apple Health has no concept of continuous per-second polling — HKObserverQuery
    /// only fires when new data actually lands, and background delivery is scheduled
    /// by iOS rather than on a fixed clock. While the app is in the foreground we
    /// still honor a literal 1-second refresh here; in the background the observer
    /// queries below take over so battery isn't spent polling for nothing.
    private func startForegroundAutoSync() {
        guard foregroundTimer == nil else { return }
        autoSyncEnabled = true
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let container = self.container, !self.syncing else { return }
            Task { @MainActor in await self.syncRecent(context: container.mainContext) }
        }
        RunLoop.main.add(timer, forMode: .common)
        foregroundTimer = timer
    }

    /// Registers an HKObserverQuery per read type with immediate background delivery,
    /// so a new Renpho weigh-in or step count synced into Health is pulled in as soon
    /// as iOS wakes the app for it — no manual "Sync Now" tap required.
    private func startBackgroundObservers() {
        guard isAvailable else { return }
        for case let sampleType as HKSampleType in readTypes {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                defer { completionHandler() }
                guard let self, error == nil, let container = self.container else { return }
                Task { @MainActor in await self.syncRecent(context: container.mainContext) }
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { _, _ in }
            observerQueries.append(query)
        }
    }

    /// Cheap sync used by the auto-sync loop and background observers: only the
    /// last couple of days, instead of the full historical range.
    @MainActor
    func syncRecent(context: ModelContext) async {
        await sync(days: 2, context: context)
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
            let activeEnergy = try await dailyActiveEnergy(days: days)
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

            let existingEnergy = (try? context.fetch(FetchDescriptor<ActiveEnergyEntry>(
                predicate: #Predicate { $0.sourceRaw == hk }))) ?? []
            let energyDays = Set(existingEnergy.map { $0.date.startOfDay })
            for (day, calories) in activeEnergy where calories > 0 {
                if let existing = existingEnergy.first(where: { $0.date.startOfDay == day }) {
                    if abs(existing.calories - calories) >= 1 { existing.calories = calories; imported += 1 }
                } else if !energyDays.contains(day) {
                    context.insert(ActiveEnergyEntry(date: day, calories: calories, source: .healthKit))
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

    private func dailyActiveEnergy(days: Int) async throws -> [(Date, Double)] {
        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return [] }
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
                var output: [(Date, Double)] = []
                results?.enumerateStatistics(from: start, to: .now) { stats, _ in
                    let calories = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    output.append((stats.startDate.startOfDay, calories))
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
