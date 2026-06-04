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
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DataTrackerWidgetEntry) -> Void) {
        completion(DataTrackerWidgetEntry(date: Date(), metrics: WidgetMetricsStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DataTrackerWidgetEntry>) -> Void) {
        let entry = DataTrackerWidgetEntry(date: Date(), metrics: WidgetMetricsStore.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1_200)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct DataTrackerWidgetView: View {
    let entry: DataTrackerWidgetEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.04),
                    Color(red: 0.08, green: 0.09, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 16) {
                header

                HStack(spacing: 12) {
                    metricPanel(
                        title: "活动消耗",
                        value: formattedKilocalories(entry.metrics.activeEnergyKilocalories),
                        subtitle: "今日累计",
                        systemImage: "bolt.heart.fill",
                        accent: Color(red: 1.00, green: 0.35, blue: 0.12)
                    )

                    metricPanel(
                        title: "饮食摄入",
                        value: formattedKilocalories(entry.metrics.dietaryEnergyKilocalories),
                        subtitle: "今日记录",
                        systemImage: "fork.knife",
                        accent: Color(red: 0.30, green: 0.84, blue: 0.42)
                    )
                }

                footer
            }
            .padding(18)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("今日概览")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Data Tracker")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
            }

            Spacer()

            Image(systemName: "flame.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(red: 1.00, green: 0.35, blue: 0.12))
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.08), in: Circle())
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(entry.metrics.updatedAt == nil ? .gray : Color(red: 0.30, green: 0.84, blue: 0.42))
                .frame(width: 7, height: 7)
            Text(updatedText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
            Spacer()
        }
    }

    private func metricPanel(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(accent.opacity(0.16), in: Circle())
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.58)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var updatedText: String {
        guard let updatedAt = entry.metrics.updatedAt else {
            return "等待 App 刷新数据"
        }

        let elapsed = max(0, Date().timeIntervalSince(updatedAt))
        if elapsed < 60 {
            return "刚刚更新"
        }
        if elapsed < 3_600 {
            return "\(Int(elapsed / 60)) 分钟前更新"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3_600)) 小时前更新"
        }
        return DateFormatter.healthBridgeDay.string(from: updatedAt)
    }

    private func formattedKilocalories(_ value: Double) -> String {
        if value < 1 {
            return "0 kcal"
        }
        return "\(Int(value.rounded())) kcal"
    }
}

struct DataTrackerHealthSummaryWidget: Widget {
    let kind = DataTrackerWidgetKind.healthSummary

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DataTrackerWidgetProvider()) { entry in
            DataTrackerWidgetView(entry: entry)
        }
        .configurationDisplayName("Data Tracker")
        .description("展示今天的活动消耗和饮食摄入。")
        .supportedFamilies([.systemLarge])
    }
}

@main
struct DataTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        DataTrackerHealthSummaryWidget()
    }
}
