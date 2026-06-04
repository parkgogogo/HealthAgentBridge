import Foundation

enum DataTrackerWidgetKind {
    static let healthSummary = "DataTrackerHealthSummaryWidget"
}

struct WidgetHealthMetrics: Codable, Hashable {
    var activeEnergyKilocalories: Double
    var dietaryEnergyKilocalories: Double
    var updatedAt: Date?

    static let empty = WidgetHealthMetrics(
        activeEnergyKilocalories: 0,
        dietaryEnergyKilocalories: 0,
        updatedAt: nil
    )
}

enum WidgetMetricsStore {
    private static let metricsKey = "DataTrackerWidget.healthMetrics"
    private static let appGroupInfoKey = "HealthReporterAppGroup"

    static func saveDailySummaries(_ summaries: [DailyHealthSummary]) {
        let today = DateFormatter.healthBridgeDay.string(from: Date())
        guard let summary = summaries.first(where: { $0.date == today }) else {
            save(.empty)
            return
        }

        save(
            WidgetHealthMetrics(
                activeEnergyKilocalories: summary.activeEnergyKilocalories ?? 0,
                dietaryEnergyKilocalories: summary.dietaryEnergyKilocalories ?? 0,
                updatedAt: Date()
            )
        )
    }

    static func load() -> WidgetHealthMetrics {
        guard let data = defaults?.data(forKey: metricsKey),
              let metrics = try? JSONDecoder().decode(WidgetHealthMetrics.self, from: data) else {
            return .empty
        }
        return metrics
    }

    private static func save(_ metrics: WidgetHealthMetrics) {
        guard let data = try? JSONEncoder().encode(metrics) else {
            return
        }
        defaults?.set(data, forKey: metricsKey)
    }

    private static var defaults: UserDefaults? {
        if let appGroupIdentifier {
            return UserDefaults(suiteName: appGroupIdentifier)
        }
        return UserDefaults.standard
    }

    private static var appGroupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return nil
        }
        return trimmed
    }
}
