import Foundation
import SwiftData

@Model
final class BodyWeightEntry {
    var date: Date = Date()
    var weightKg: Double = 0
    var sourceRaw: String = EntrySource.manual.rawValue

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(date: Date = .now, weightKg: Double, source: EntrySource = .manual) {
        self.date = date
        self.weightKg = weightKg
        self.sourceRaw = source.rawValue
    }
}

@Model
final class BodyFatEntry {
    var date: Date = Date()
    var bodyFatPercentage: Double = 0
    var sourceRaw: String = EntrySource.manual.rawValue

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(date: Date = .now, bodyFatPercentage: Double, source: EntrySource = .manual) {
        self.date = date
        self.bodyFatPercentage = bodyFatPercentage
        self.sourceRaw = source.rawValue
    }
}

@Model
final class MeasurementEntry {
    var date: Date = Date()
    var waist: Double?
    var chest: Double?
    var arms: Double?
    var thighs: Double?
    var shoulders: Double?
    var neck: Double?
    var hips: Double?
    var customMeasurements: [String: Double] = [:]
    var notes: String = ""

    init(date: Date = .now,
         waist: Double? = nil,
         chest: Double? = nil,
         arms: Double? = nil,
         thighs: Double? = nil,
         shoulders: Double? = nil,
         neck: Double? = nil,
         hips: Double? = nil,
         customMeasurements: [String: Double] = [:],
         notes: String = "") {
        self.date = date
        self.waist = waist
        self.chest = chest
        self.arms = arms
        self.thighs = thighs
        self.shoulders = shoulders
        self.neck = neck
        self.hips = hips
        self.customMeasurements = customMeasurements
        self.notes = notes
    }

    static let standardFields: [(key: String, label: String, keyPath: WritableKeyPath<MeasurementEntry, Double?>)] = [
        ("waist", "Waist", \.waist),
        ("chest", "Chest", \.chest),
        ("arms", "Arms", \.arms),
        ("thighs", "Thighs", \.thighs),
        ("shoulders", "Shoulders", \.shoulders),
        ("neck", "Neck", \.neck),
        ("hips", "Hips", \.hips)
    ]
}

@Model
final class ProgressPhoto {
    var date: Date = Date()
    var frontPhotoPath: String?
    var sidePhotoPath: String?
    var backPhotoPath: String?
    var notes: String = ""

    init(date: Date = .now,
         frontPhotoPath: String? = nil,
         sidePhotoPath: String? = nil,
         backPhotoPath: String? = nil,
         notes: String = "") {
        self.date = date
        self.frontPhotoPath = frontPhotoPath
        self.sidePhotoPath = sidePhotoPath
        self.backPhotoPath = backPhotoPath
        self.notes = notes
    }
}

@Model
final class StepEntry {
    var date: Date = Date()
    var steps: Int = 0
    var sourceRaw: String = EntrySource.manual.rawValue

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(date: Date = .now, steps: Int, source: EntrySource = .manual) {
        self.date = date
        self.steps = steps
        self.sourceRaw = source.rawValue
    }
}
