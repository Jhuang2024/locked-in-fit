import Foundation

// MARK: - Lenient enum decoding

/// String-backed enums LockedInFit publishes decode *and* encode leniently:
/// on the way in, an unrecognized or missing raw value falls back to the
/// enum's "unknown" case instead of throwing and failing the whole snapshot.
/// This lets LockedInFit's and Social Climber's schemas drift a little
/// (new cases added on either side) without one app's update breaking the
/// other's reads.
protocol CrossAppLenientEnum: RawRepresentable, Codable where RawValue == String {
    static var unknownCase: Self { get }
}

extension CrossAppLenientEnum {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = Self(rawValue: raw) ?? Self.unknownCase
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Same leniency as `CrossAppLenientEnum`, for read-only data (Social
/// Climber's context) that LockedInFit never needs to encode.
protocol CrossAppLenientDecodable: RawRepresentable, Decodable where RawValue == String {
    static var unknownCase: Self { get }
}

extension CrossAppLenientDecodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = Self(rawValue: raw) ?? Self.unknownCase
    }
}

// MARK: - LockedInFit's published snapshot

/// The small, non-sensitive slice of today's state LockedInFit publishes for
/// other apps in the same App Group (currently: Social Climber). This is
/// intentionally a summary, never raw data: no food logs, no photos, no
/// exact measurements, no AI explanations, no notes. See
/// `CrossAppIntegrationManager.publish` for what builds this.
struct LockedInFitPublicContext: Codable {
    static let currentSchemaVersion = 1

    var app: String = "LockedInFit"
    var schemaVersion: Int = currentSchemaVersion
    var updatedAt: Date
    var today: Today

    struct Today: Codable {
        var sleepScore: Double
        var energyLevel: EnergyLevel
        var recoveryStatus: RecoveryStatus
        var workoutPlannedToday: Bool
        var workoutCompletedToday: Bool
        var nutritionStatus: NutritionStatus
        var calorieStatus: CalorieStatus
        var dailyChecklistCompletion: Double
        var importantHealthTasksDue: [HealthTask]
        /// Whether "I'm sick today" is toggled on in LockedInFit.
        var isSick: Bool
    }

    struct HealthTask: Codable, Identifiable {
        var id: String
        var title: String
        var category: HealthTaskCategory
        var priority: HealthTaskPriority
    }

    enum EnergyLevel: String, CrossAppLenientEnum {
        case low, medium, high, unknown
        static var unknownCase: EnergyLevel { .unknown }
    }

    enum RecoveryStatus: String, CrossAppLenientEnum {
        case poor, okay, good, unknown
        static var unknownCase: RecoveryStatus { .unknown }
    }

    enum NutritionStatus: String, CrossAppLenientEnum {
        case underTarget = "under_target"
        case onTrack = "on_track"
        case approachingLimit = "approaching_limit"
        case overLimit = "over_limit"
        case unknown
        static var unknownCase: NutritionStatus { .unknown }
    }

    enum CalorieStatus: String, CrossAppLenientEnum {
        case remaining
        case nearLimit = "near_limit"
        case exceeded
        case unknown
        static var unknownCase: CalorieStatus { .unknown }
    }

    enum HealthTaskCategory: String, CrossAppLenientEnum {
        case sleep, meal, workout, appearance, general
        static var unknownCase: HealthTaskCategory { .general }
    }

    enum HealthTaskPriority: String, CrossAppLenientEnum {
        case low, medium, high
        static var unknownCase: HealthTaskPriority { .medium }
    }
}

// MARK: - Social Climber's published snapshot (read-only)

/// LockedInFit's best-effort contract for what Social Climber publishes.
/// Every field decodes defensively: missing keys, wrong types, or unknown
/// enum cases fall back to a neutral default instead of failing the whole
/// decode, since a partially-understood snapshot is still useful and a
/// failed decode must look identical to "no file at all" to the rest of the
/// app (see `CrossAppIntegrationManager.readSocialContext`).
struct SocialClimberPublicContext: Decodable {
    static let expectedSchemaVersion = 1

    var app: String
    var schemaVersion: Int
    var updatedAt: Date
    var today: Today

    struct Today: Decodable {
        var socialIntensity: SocialIntensity
        var upcomingEvents: [UpcomingEvent]
        var socialTasksDueToday: [SocialTask]

        init(socialIntensity: SocialIntensity, upcomingEvents: [UpcomingEvent], socialTasksDueToday: [SocialTask]) {
            self.socialIntensity = socialIntensity
            self.upcomingEvents = upcomingEvents
            self.socialTasksDueToday = socialTasksDueToday
        }

        private enum CodingKeys: String, CodingKey {
            case socialIntensity, upcomingEvents, socialTasksDueToday
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            socialIntensity = (try? container.decode(SocialIntensity.self, forKey: .socialIntensity)) ?? .unknown
            upcomingEvents = (try? container.decode([UpcomingEvent].self, forKey: .upcomingEvents)) ?? []
            socialTasksDueToday = (try? container.decode([SocialTask].self, forKey: .socialTasksDueToday)) ?? []
        }
    }

    struct UpcomingEvent: Decodable, Identifiable {
        var id: String
        var eventType: EventType
        var importance: Importance
        var startTime: Date
        var prepNeeded: Bool

        private enum CodingKeys: String, CodingKey {
            case id, eventType, importance, startTime, prepNeeded
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
            eventType = (try? container.decode(EventType.self, forKey: .eventType)) ?? .unknown
            importance = (try? container.decode(Importance.self, forKey: .importance)) ?? .unknown
            startTime = (try? container.decode(Date.self, forKey: .startTime)) ?? .distantPast
            prepNeeded = (try? container.decode(Bool.self, forKey: .prepNeeded)) ?? false
        }
    }

    struct SocialTask: Decodable, Identifiable {
        var id: String
        var title: String

        private enum CodingKeys: String, CodingKey { case id, title }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
            title = (try? container.decode(String.self, forKey: .title)) ?? ""
        }
    }

    enum SocialIntensity: String, CrossAppLenientDecodable {
        case low, medium, high, unknown
        static var unknownCase: SocialIntensity { .unknown }
    }

    enum EventType: String, CrossAppLenientDecodable {
        case dinner, party, networking, date, hangout, other, unknown
        static var unknownCase: EventType { .unknown }
    }

    enum Importance: String, CrossAppLenientDecodable {
        case low, medium, high, unknown
        static var unknownCase: Importance { .unknown }
    }

    private enum CodingKeys: String, CodingKey { case app, schemaVersion, updatedAt, today }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = (try? container.decode(String.self, forKey: .app)) ?? "SocialClimber"
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 0
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? .distantPast
        today = (try? container.decode(Today.self, forKey: .today)) ?? Today(socialIntensity: .unknown, upcomingEvents: [], socialTasksDueToday: [])
    }
}
