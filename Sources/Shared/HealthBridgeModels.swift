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

struct HealthReportEnvelope: Codable, Hashable {
    var schemaVersion: Int
    var deviceName: String
    var generatedAt: Date
    var reason: String
    var dailySummaries: [DailyHealthSummary]
    var samples: [HealthSample]
}

struct StoredHealthReport: Codable, Hashable {
    var receivedAt: Date
    var remoteAddress: String?
    var report: HealthReportEnvelope
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
