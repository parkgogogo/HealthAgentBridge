import Foundation

enum HealthBridgeConstants {
    static let schemaVersion = 1
    static let bonjourType = "_healthbridge._tcp"
    static let serviceName = "Health Agent Bridge"
    static let tailnetHost = configuredString("HealthBridgeTailnetHost", defaultValue: "your-mac.tailnet.ts.net")
    static let tailnetIPv4 = configuredString("HealthBridgeTailnetIPv4", defaultValue: "100.64.0.1")
    static let port: UInt16 = 8787
    static let ingestPath = "/v1/ingest"
    static let sharedToken = configuredString("HealthBridgeSharedToken", defaultValue: "replace-with-a-random-token")

    static var agentBaseURL: String {
        "http://127.0.0.1:\(port)"
    }

    static var tailnetIngestURL: String {
        "http://\(tailnetHost):\(port)\(ingestPath)"
    }

    static var tailnetIPv4IngestURL: String {
        "http://\(tailnetIPv4):\(port)\(ingestPath)"
    }

    private static func configuredString(_ key: String, defaultValue: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return defaultValue
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return defaultValue
        }
        return trimmed
    }
}

struct DailyHealthSummary: Codable, Identifiable, Hashable {
    var id: String { date }

    var date: String
    var stepCount: Double?
    var activeEnergyKilocalories: Double?
    var dietaryEnergyKilocalories: Double?
    var dietaryProteinGrams: Double?
    var dietaryCarbohydratesGrams: Double?
    var dietaryFatGrams: Double?
    var walkingRunningDistanceMeters: Double?
    var exerciseMinutes: Double?
    var heartRateAverageBPM: Double?
    var restingHeartRateAverageBPM: Double?
    var bodyMassKilograms: Double?
    var sleepAsleepMinutes: Double?
}

struct HealthSample: Codable, Identifiable, Hashable {
    var id: UUID
    var type: String
    var startDate: Date
    var endDate: Date
    var value: Double
    var unit: String
    var sourceName: String?
}

struct HealthWorkout: Codable, Identifiable, Hashable {
    var id: UUID
    var activityType: UInt
    var activityName: String
    var startDate: Date
    var endDate: Date
    var durationSeconds: Double
    var totalEnergyBurnedKilocalories: Double?
    var totalDistanceMeters: Double?
    var sourceName: String?
}

struct HealthReportEnvelope: Codable, Hashable {
    var schemaVersion: Int
    var deviceName: String
    var generatedAt: Date
    var reason: String
    var dailySummaries: [DailyHealthSummary]
    var samples: [HealthSample]
    var workouts: [HealthWorkout]

    init(
        schemaVersion: Int,
        deviceName: String,
        generatedAt: Date,
        reason: String,
        dailySummaries: [DailyHealthSummary],
        samples: [HealthSample],
        workouts: [HealthWorkout]
    ) {
        self.schemaVersion = schemaVersion
        self.deviceName = deviceName
        self.generatedAt = generatedAt
        self.reason = reason
        self.dailySummaries = dailySummaries
        self.samples = samples
        self.workouts = workouts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        reason = try container.decode(String.self, forKey: .reason)
        dailySummaries = try container.decode([DailyHealthSummary].self, forKey: .dailySummaries)
        samples = try container.decode([HealthSample].self, forKey: .samples)
        workouts = try container.decodeIfPresent([HealthWorkout].self, forKey: .workouts) ?? []
    }
}

struct StoredHealthReport: Codable, Hashable {
    var receivedAt: Date
    var remoteAddress: String?
    var report: HealthReportEnvelope
}

enum HealthPacketType: String, Codable, Hashable {
    case foodIntake = "food_intake"
    case bodyWeight = "body_weight"
}

enum HealthPacketSource: String, Codable, Hashable {
    case openClaw = "openclaw"
    case iOSManual = "ios_manual"
    case macAPI = "mac_api"
}

enum HealthPacketStatus: String, Codable, Hashable {
    case pendingIOSSync = "pending_ios_sync"
    case writtenToHealthKit = "written_to_healthkit"
    case failed = "failed"
    case cancelled = "cancelled"
}

enum HealthPacketConfidence: String, Codable, Hashable {
    case low
    case medium
    case high
}

struct FoodItemEstimate: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var amountDescription: String?
    var estimatedCaloriesKcal: Double?
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var fatGrams: Double?

    init(
        id: UUID = UUID(),
        name: String,
        amountDescription: String? = nil,
        estimatedCaloriesKcal: Double? = nil,
        proteinGrams: Double? = nil,
        carbohydrateGrams: Double? = nil,
        fatGrams: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.amountDescription = amountDescription
        self.estimatedCaloriesKcal = estimatedCaloriesKcal
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
    }
}

struct FoodIntakePayload: Codable, Hashable {
    var occurredAt: Date
    var mealType: String?
    var rawText: String
    var foodItems: [FoodItemEstimate]
    var estimatedCaloriesKcal: Double
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var fatGrams: Double?
    var confidence: HealthPacketConfidence
    var estimationNotes: String?
}

struct BodyWeightPayload: Codable, Hashable {
    var measuredAt: Date
    var weightKilograms: Double
    var rawText: String?
    var note: String?
}

struct HealthPacket: Codable, Identifiable, Hashable {
    var id: String { packetId }

    var packetId: String
    var type: HealthPacketType
    var source: HealthPacketSource
    var status: HealthPacketStatus
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var healthKitObjectIds: [String]
    var lastError: String?
    var foodIntake: FoodIntakePayload?
    var bodyWeight: BodyWeightPayload?

    func withUpdatedStatus(
        _ status: HealthPacketStatus,
        healthKitObjectIds: [String]? = nil,
        lastError: String? = nil,
        updatedAt: Date = Date()
    ) -> HealthPacket {
        var copy = self
        copy.status = status
        copy.updatedAt = updatedAt
        if let healthKitObjectIds {
            copy.healthKitObjectIds = healthKitObjectIds
        }
        copy.lastError = lastError
        return copy
    }
}

struct HealthPacketCreateRequest: Codable, Hashable {
    var type: HealthPacketType
    var source: HealthPacketSource?
    var packetId: String?
    var foodIntake: FoodIntakePayload?
    var bodyWeight: BodyWeightPayload?
}

struct HealthPacketAcknowledgeRequest: Codable, Hashable {
    var status: HealthPacketStatus
    var healthKitObjectIds: [String]?
    var errorMessage: String?
}

struct HealthPacketUpdateRequest: Codable, Hashable {
    var foodIntake: FoodIntakePayload?
    var bodyWeight: BodyWeightPayload?
}

struct HealthPacketListPayload: Codable, Hashable {
    var packets: [HealthPacket]
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension DateFormatter {
    static let healthBridgeDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let healthBridgeDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

enum HealthBridgeDisplayTime {
    static func latestSyncText(for date: Date?, relativeTo now: Date = Date()) -> String {
        guard let date else {
            return "尚未成功上报"
        }

        let absolute = DateFormatter.healthBridgeDateTime.string(from: date)
        let elapsed = max(0, now.timeIntervalSince(date))

        if elapsed < 60 {
            return "刚刚（\(absolute)）"
        }

        if elapsed < 3_600 {
            let minutes = Int(elapsed / 60)
            return "\(minutes) 分钟前（\(absolute)）"
        }

        if elapsed < 86_400 {
            let hours = Int(elapsed / 3_600)
            return "\(hours) 小时前（\(absolute)）"
        }

        return absolute
    }
}
