import SwiftUI
import WidgetKit

struct DataTrackerWidgetEntry: TimelineEntry {
    let date: Date
    let metrics: WidgetHealthMetrics
}

struct DataTrackerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DataTrackerWidgetEntry {
        DataTrackerWidgetEntry(
            date: Date(),
            metrics: WidgetHealthMetrics(
                activeEnergyKilocalories: 420,
                dietaryEnergyKilocalories: 1_280,
                workoutDayIDs: sampleWorkoutDays(),
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DataTrackerWidgetEntry) -> Void) {
        completion(DataTrackerWidgetEntry(date: Date(), metrics: WidgetMetricsStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DataTrackerWidgetEntry>) -> Void) {
        let entry = DataTrackerWidgetEntry(date: Date(), metrics: WidgetMetricsStore.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func sampleWorkoutDays() -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yearStart = calendar.date(from: calendar.dateComponents([.year], from: today)) else {
            return []
        }

        return stride(from: 3, through: 150, by: 5).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: yearStart),
                  day <= today else {
                return nil
            }
            return DateFormatter.healthBridgeDay.string(from: day)
        }
    }
}

struct DataTrackerWidgetView: View {
    let entry: DataTrackerWidgetEntry

    private let columns = 23
    private let dotSize: CGFloat = 3.1
    private let dotSpacing: CGFloat = 2.0

    var body: some View {
        VStack(spacing: 10) {
            dotGrid

            VStack(spacing: 2) {
                Text("\(year)")
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                Text("剩余 \(daysLeft) 天 · 训练 \(workoutDaysThisYear) 天")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accent.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 11)
        .padding(.vertical, 12)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.99, blue: 0.97),
                    Color(red: 0.96, green: 0.95, blue: 0.93)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var dotGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(dotSize), spacing: dotSpacing), count: columns),
            alignment: .center,
            spacing: dotSpacing
        ) {
            ForEach(yearDays, id: \.self) { day in
                Circle()
                    .fill(color(for: day))
                    .frame(width: dotSize, height: dotSize)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var workoutDays: Set<String> {
        Set(entry.metrics.workoutDayIDs)
    }

    private var workoutDaysThisYear: Int {
        workoutDays.intersection(Set(yearDays.map { DateFormatter.healthBridgeDay.string(from: $0) })).count
    }

    private var yearDays: [Date] {
        let calendar = Calendar.current
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let nextYearStart = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return []
        }

        let totalDays = calendar.dateComponents([.day], from: yearStart, to: nextYearStart).day ?? 365
        return (0..<totalDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: yearStart)
        }
    }

    private var year: Int {
        Calendar.current.component(.year, from: entry.date)
    }

    private var daysLeft: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let nextYearStart = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return 0
        }
        return max(0, calendar.dateComponents([.day], from: tomorrow, to: nextYearStart).day ?? 0)
    }

    private var accent: Color {
        Color(red: 1.00, green: 0.47, blue: 0.10)
    }

    private func color(for day: Date) -> Color {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        let dayStart = calendar.startOfDay(for: day)

        if dayStart > today {
            return Color(red: 1.00, green: 0.66, blue: 0.32)
        }

        let id = DateFormatter.healthBridgeDay.string(from: dayStart)
        if workoutDays.contains(id) {
            return accent
        }

        return Color(red: 0.95, green: 0.85, blue: 0.75)
    }
}

struct DataTrackerHealthSummaryWidget: Widget {
    let kind = DataTrackerWidgetKind.healthSummary

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DataTrackerWidgetProvider()) { entry in
            DataTrackerWidgetView(entry: entry)
        }
        .configurationDisplayName("年度训练")
        .description("用年度点阵展示今年的训练状态和剩余天数。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
struct DataTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        DataTrackerHealthSummaryWidget()
    }
}
