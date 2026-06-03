import Charts
import SwiftUI

private enum DataTrackerStyle {
    static let background = Color.black
    static let card = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let cardRaised = Color(red: 0.16, green: 0.16, blue: 0.16)
    static let cardMuted = Color(red: 0.20, green: 0.20, blue: 0.20)
    static let orange = Color(red: 1.00, green: 0.37, blue: 0.12)
    static let orangeMuted = Color(red: 0.45, green: 0.22, blue: 0.12)
    static let textMuted = Color.white.opacity(0.62)
    static let separator = Color.white.opacity(0.10)
}

struct ContentView: View {
    @StateObject private var viewModel = HealthReporterViewModel()
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            WorkoutDashboardTab(viewModel: viewModel)
                .tabItem {
                    Label("概览", systemImage: "chart.bar.fill")
                }

            StatusTab(viewModel: viewModel)
                .tabItem {
                    Label("状态", systemImage: "checkmark.circle.fill")
                }
        }
        .tint(DataTrackerStyle.orange)
        .task {
            await viewModel.load()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await viewModel.refreshDisplay()
                await viewModel.refreshWorkoutChart()
            }
        }
    }
}

private struct WorkoutDashboardTab: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DashboardHeader(syncBadgeText: viewModel.syncBadgeText)

                CaloriesHeroCard(
                    totalText: viewModel.workoutCaloriesTotalText,
                    dailyAverageText: viewModel.workoutDailyAverageText
                )

                HStack(spacing: 12) {
                    MetricTile(title: "训练次数", value: viewModel.workoutCountText, systemImage: "figure.run")
                    MetricTile(title: "活跃天数", value: viewModel.workoutActiveDaysText, systemImage: "bolt.heart.fill")
                }

                WorkoutChartCard(viewModel: viewModel)
                RecentWorkoutCard(rows: viewModel.recentWorkoutRows)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .background(DataTrackerStyle.background.ignoresSafeArea())
    }
}

private struct DashboardHeader: View {
    let syncBadgeText: String

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Data Tracker")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("HealthKit workout overview")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text(syncBadgeText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DataTrackerStyle.cardRaised, in: Capsule())
        }
    }
}

private struct CaloriesHeroCard: View {
    let totalText: String
    let dailyAverageText: String

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DataTrackerStyle.orange,
                            Color(red: 1.00, green: 0.48, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "flame.fill")
                .font(.system(size: 118, weight: .bold))
                .foregroundStyle(.white.opacity(0.16))
                .rotationEffect(.degrees(-10))
                .offset(x: -8, y: 8)

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("30 天总消耗")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.90))

                VStack(alignment: .leading, spacing: 6) {
                    Text(totalText)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.78)
                    Text("日均 \(dailyAverageText) · 来自 Apple Watch")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(height: 172)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .fill(DataTrackerStyle.orange.opacity(0.16))
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DataTrackerStyle.orange)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)
                Text(value)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct WorkoutChartCard: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calories Burnt")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(viewModel.workoutSelectedDayText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DataTrackerStyle.textMuted)
                }

                Spacer()

                Text(viewModel.workoutSelectedCaloriesText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
            }

            if viewModel.hasWorkoutCalories {
                Chart {
                    ForEach(viewModel.workoutCalories) { point in
                        BarMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("卡路里", point.kilocalories),
                            width: .fixed(8)
                        )
                        .cornerRadius(6)
                        .foregroundStyle(
                            point.id == viewModel.workoutHighlightedDayID
                                ? DataTrackerStyle.orange
                                : DataTrackerStyle.orangeMuted.opacity(0.78)
                        )
                    }

                    if viewModel.workoutChartAverageKilocalories > 0 {
                        RuleMark(y: .value("活跃日均", viewModel.workoutChartAverageKilocalories))
                            .foregroundStyle(.white.opacity(0.28))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 5]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine()
                            .foregroundStyle(.white.opacity(0.06))
                        AxisTick()
                            .foregroundStyle(.clear)
                        AxisValueLabel()
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DataTrackerStyle.textMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisGridLine()
                            .foregroundStyle(.white.opacity(0.08))
                        AxisTick()
                            .foregroundStyle(.clear)
                        AxisValueLabel()
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DataTrackerStyle.textMuted)
                    }
                }
                .frame(height: 208)
            } else {
                EmptyChartState(message: viewModel.workoutChartMessage ?? "最近 30 天没有 workout 卡路里")
                    .frame(height: 208)
            }
        }
        .padding(20)
        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct EmptyChartState: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(DataTrackerStyle.orange.opacity(0.75))
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DataTrackerStyle.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DataTrackerStyle.cardRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RecentWorkoutCard: View {
    let rows: [RecentWorkoutRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最近训练")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if rows.isEmpty {
                Text("暂无最近 workout")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(rows) { row in
                    RecentWorkoutRowView(row: row)

                    if row.id != rows.last?.id {
                        Rectangle()
                            .fill(DataTrackerStyle.separator)
                            .frame(height: 1)
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .padding(20)
        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct RecentWorkoutRowView: View {
    let row: RecentWorkoutRow

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DataTrackerStyle.cardMuted)
                Image(systemName: row.systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DataTrackerStyle.orange)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(row.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)
            }

            Spacer()

            Text(row.detail)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.90))
        }
    }
}

private struct StatusTab: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("状态")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Data Tracker sync controls")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DataTrackerStyle.textMuted)
                }

                SurfaceCard {
                    Toggle("健康上报", isOn: Binding(
                        get: { viewModel.isReportingEnabled },
                        set: { viewModel.setReportingEnabled($0) }
                    ))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .tint(DataTrackerStyle.orange)
                }

                SurfaceCard {
                    StatusRow(title: "状态", value: viewModel.statusText)
                    StatusDivider()
                    StatusRow(title: "最近成功上报", value: viewModel.lastSyncText)
                    StatusDivider()
                    StatusRow(title: "待补发", value: viewModel.queuedText)
                }

                SurfaceCard {
                    DetailTextRow(title: "当前目标", text: viewModel.targetText)
                }

                SurfaceCard {
                    if let errorText = viewModel.errorText {
                        DetailTextRow(title: "最近错误", text: errorText)
                    } else {
                        StatusRow(title: "最近错误", value: "无")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .background(DataTrackerStyle.background.ignoresSafeArea())
    }
}

private struct SurfaceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct StatusRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DataTrackerStyle.textMuted)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct StatusDivider: View {
    var body: some View {
        Rectangle()
            .fill(DataTrackerStyle.separator)
            .frame(height: 1)
    }
}

private struct DetailTextRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(text)
                .font(.footnote.monospaced())
                .foregroundStyle(DataTrackerStyle.textMuted)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
