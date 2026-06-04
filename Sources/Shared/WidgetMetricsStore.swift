import Foundation

enum DataTrackerWidgetKind {
    static let healthSummary = "DataTrackerHealthSummaryWidget"
}

struct WidgetHealthMetrics: Codable, Hashable {
    var activeEnergyKilocalories: Double
    var dietaryEnergyKilocalories: Double
    var workoutDayIDs: [String]
    var updatedAt: Date?

    static let empty = WidgetHealthMetrics(
        activeEnergyKilocalories: 0,
        dietaryEnergyKilocalories: 0,
        workoutDayIDs: [],
        updatedAt: nil
    )
}

enum WidgetMetricsStore {
    private static let metricsKey = "DataTrackerWidget.healthMetrics"
    private static let appGroupInfoKey = "HealthReporterAppGroup"

    static func saveDailySummaries(_ summaries: [DailyHealthSummary], workouts: [HealthWorkout]? = nil) {
        let today = DateFormatter.healthBridgeDay.string(from: Date())
        let existing = load()
        let workoutDayIDs = workouts.map(workoutDayIDs) ?? existing.workoutDayIDs
        guard let summary = summaries.first(where: { $0.date == today }) else {
            save(
                WidgetHealthMetrics(
                    activeEnergyKilocalories: 0,
                    dietaryEnergyKilocalories: 0,
                    workoutDayIDs: workoutDayIDs,
                    updatedAt: Date()
                )
            )
            return
        }

        save(
            WidgetHealthMetrics(
                activeEnergyKilocalories: summary.activeEnergyKilocalories ?? 0,
                dietaryEnergyKilocalories: summary.dietaryEnergyKilocalories ?? 0,
                workoutDayIDs: workoutDayIDs,
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

    private static func workoutDayIDs(from workouts: [HealthWorkout]) -> [String] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let dayIDs = Set(
            workouts.compactMap { workout -> String? in
                guard calendar.component(.year, from: workout.startDate) == currentYear else {
                    return nil
                }
                return DateFormatter.healthBridgeDay.string(from: workout.startDate)
            }
        )

        return dayIDs.sorted()
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
