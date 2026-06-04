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

    private let columns = 28
    private let dotSize: CGFloat = 2.1
    private let dotHorizontalSpacing: CGFloat = 3.15
    private let dotVerticalSpacing: CGFloat = 3.65

    var body: some View {
        VStack(spacing: 15) {
            dotGrid

            VStack(spacing: 3) {
                Text("\(year)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(labelColor)
                    .monospacedDigit()
                Text("剩余 \(daysLeft) 天 · 训练 \(workoutDaysThisYear) 天")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 13)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 1.00, blue: 0.995),
                    Color(red: 0.985, green: 0.982, blue: 0.975)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var dotGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(dotSize), spacing: dotHorizontalSpacing), count: columns),
            alignment: .center,
            spacing: dotVerticalSpacing
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

    private var labelColor: Color {
        accent.opacity(0.68)
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
