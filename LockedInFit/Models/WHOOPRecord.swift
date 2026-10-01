import Foundation
import CoreFoundation
import SwiftData

/// Additive model: raw API payload preserves every field without renaming any
/// existing user data. Imported records never become duplicate calorie credits.
@Model
final class WHOOPRecord {
    var key: String = ""
    var kind: String = ""
    var date: Date = Date()
    var json: Data = Data()
    var syncedAt: Date = Date()

    init(key: String, kind: String, date: Date, json: Data) {
        self.key = key; self.kind = kind; self.date = date; self.json = json
    }

    var payload: [String: Any] {
        (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
    }
    var isScored: Bool { payload["score_state"] as? String == "SCORED" }
    var isNap: Bool { payload["nap"] as? Bool == true }

    func number(_ path: String) -> Double? { WHOOPData.number(path, in: payload) }
    var recovery: Double? { isScored ? number("score.recovery_score") : nil }
    var strain: Double? { isScored ? number("score.strain") : nil }
    var sleepHours: Double? {
        guard isScored else { return nil }
        let paths = ["total_light_sleep_time_milli", "total_slow_wave_sleep_time_milli", "total_rem_sleep_time_milli"]
        let stages = paths.compactMap { number("score.stage_summary.\($0)") }
        guard stages.count == paths.count else { return nil }
        return stages.reduce(0, +) / 3_600_000
    }
}

enum WHOOPData {
    static func number(_ path: String, in payload: [String: Any]) -> Double? {
        var value: Any = payload
        for part in path.split(separator: ".") {
            guard let next = (value as? [String: Any])?[String(part)] else { return nil }
            value = next
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    static func identifier(kind: String, payload: [String: Any]) -> String? {
        if kind == "body" { return "body:current" }
        let id = payload[kind == "recovery" ? "cycle_id" : "id"]
        if let value = id as? String, !value.isEmpty { return "\(kind):\(value)" }
        if let value = id as? NSNumber { return "\(kind):\(value.stringValue)" }
        return nil
    }

    /// Each physiological cycle owns its recovery. It is NOT a midnight-to-
    /// midnight calendar day; sleep is displayed on its wake date instead.
    static func recordDate(kind: String, payload: [String: Any], cycles: [String: Date]) -> Date? {
        if kind == "body" { return .now }
        if kind == "recovery", let id = payload["cycle_id"] as? NSNumber {
            return cycles[id.stringValue]
        }
        return date(payload[kind == "sleep" ? "end" : "start"])
    }

    static func kcal(kilojoules: Double) -> Double { kilojoules / 4.184 }
}
