import SwiftUI
import UIKit

private enum DataTrackerStyle {
    static let background = Color.black
    static let card = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let cardRaised = Color(red: 0.16, green: 0.16, blue: 0.16)
    static let cardMuted = Color(red: 0.20, green: 0.20, blue: 0.20)
    static let orange = Color(red: 1.00, green: 0.37, blue: 0.12)
    static let orangeMuted = Color(red: 0.45, green: 0.22, blue: 0.12)
    static let green = Color(red: 0.32, green: 0.84, blue: 0.45)
    static let greenMuted = Color(red: 0.13, green: 0.34, blue: 0.19)
    static let greenDeep = Color(red: 0.04, green: 0.42, blue: 0.18)
    static let textMuted = Color.white.opacity(0.62)
    static let separator = Color.white.opacity(0.10)
}

private enum DataTrackerTab: Hashable {
    case workout
    case calorie
    case status

    var accentColor: Color {
        switch self {
        case .workout, .status:
            return DataTrackerStyle.orange
        case .calorie:
            return DataTrackerStyle.green
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = HealthReporterViewModel()
    @State private var selectedTab: DataTrackerTab = .workout
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selectedTab) {
            WorkoutDashboardTab(viewModel: viewModel)
                .tabItem {
                    Label("运动", systemImage: "figure.run")
                }
                .tag(DataTrackerTab.workout)

            CalorieDashboardTab(viewModel: viewModel)
                .tabItem {
                    Label("热量", systemImage: "flame.fill")
                }
                .tag(DataTrackerTab.calorie)

            StatusTab(viewModel: viewModel)
                .tabItem {
                    Label("状态", systemImage: "checkmark.circle.fill")
                }
                .tag(DataTrackerTab.status)
        }
        .tint(selectedTab.accentColor)
        .task {
            await viewModel.load()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await viewModel.refreshDisplay()
                await viewModel.refreshWorkoutChart()
                await viewModel.refreshNutritionDashboard()
            }
        }
    }
}

private struct WorkoutDashboardTab: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DashboardHeader(syncBadgeText: viewModel.syncBadgeText)

                    CaloriesHeroCard(
                        totalText: viewModel.workoutCaloriesTotalText,
                        dailyAverageText: viewModel.workoutDailyAverageText
                    )

                    HStack(spacing: 12) {
                        MetricTile(title: "7 天训练", value: viewModel.workoutCountText, systemImage: "figure.run")
                        MetricTile(title: "7 天活跃", value: viewModel.workoutActiveDaysText, systemImage: "bolt.heart.fill")
                    }

                    WorkoutChartCard(viewModel: viewModel)
                    RecentWorkoutCard(rows: viewModel.recentWorkoutRows, allRows: viewModel.allWorkoutRows)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .background(DataTrackerStyle.background.ignoresSafeArea())
        }
    }
}

private struct CalorieDashboardTab: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DashboardHeader(syncBadgeText: viewModel.syncBadgeText)

                    CalorieIntakeHeroCard(
                        totalText: viewModel.calorieIntakeTotalText,
                        dailyAverageText: viewModel.calorieDailyAverageText,
                        trackedDaysText: viewModel.calorieTrackedDaysText
                    )

                    HStack(spacing: 12) {
                        MetricTile(
                            title: "最近体重",
                            value: viewModel.latestWeightText,
                            systemImage: "scalemass.fill",
                            accent: DataTrackerStyle.green
                        )
                        MetricTile(
                            title: "体重变化",
                            value: viewModel.weightDeltaText,
                            systemImage: "arrow.up.arrow.down",
                            accent: DataTrackerStyle.green
                        )
                    }

                    WeightTrendCard(viewModel: viewModel)
                    CalorieIntakeChartCard(viewModel: viewModel)
                    RecentHealthRecordCard(viewModel: viewModel)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .background(DataTrackerStyle.background.ignoresSafeArea())
        }
    }
}

private struct DashboardHeader: View {
    let syncBadgeText: String

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Data Tracker")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
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
                    Text("最近 7 天总消耗")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.90))

                VStack(alignment: .leading, spacing: 6) {
                    Text(totalText)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.78)
                    Text("日均 \(dailyAverageText) · 50 天热力图")
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

private struct CalorieIntakeHeroCard: View {
    let totalText: String
    let dailyAverageText: String
    let trackedDaysText: String

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DataTrackerStyle.greenDeep,
                            DataTrackerStyle.green
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "leaf.fill")
                .font(.system(size: 120, weight: .bold))
                .foregroundStyle(.white.opacity(0.15))
                .rotationEffect(.degrees(-12))
                .offset(x: -6, y: 10)

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("最近 7 天摄入")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.90))

                VStack(alignment: .leading, spacing: 6) {
                    Text(totalText)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.78)
                    Text("日均 \(dailyAverageText) · 记录 \(trackedDaysText)")
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
    var accent: Color = DataTrackerStyle.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(accent)
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
                WorkoutHeatmapGrid(
                    points: viewModel.workoutCalories,
                    selectedDayID: viewModel.workoutHighlightedDayID,
                    maxKilocalories: viewModel.workoutHeatmapMaxKilocalories,
                    onSelect: { point in
                        viewModel.selectWorkoutDay(point)
                    }
                )
            } else {
                EmptyChartState(message: viewModel.workoutChartMessage ?? "最近 50 天没有 workout 卡路里")
                    .frame(height: 132)
            }
        }
        .padding(20)
        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct WorkoutHeatmapGrid: View {
    let points: [WorkoutCaloriesPoint]
    let selectedDayID: String?
    let maxKilocalories: Double
    let onSelect: (WorkoutCaloriesPoint) -> Void

    private let rowCount = 5
    private let cellSpacing: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(Array(pointColumns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: cellSpacing) {
                        ForEach(column) { point in
                            Button {
                                onSelect(point)
                            } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(color(for: point))
                                    .overlay {
                                        if point.id == selectedDayID {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(.white.opacity(0.78), lineWidth: 1.5)
                                        }
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accessibilityLabel(for: point))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }

            HStack(spacing: 7) {
                Text("低")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(legendColor(index))
                        .frame(width: 13, height: 13)
                }
                Text("高")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)

                Spacer()

                Text("点按格子查看当天数据")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)
            }
        }
        .padding(.top, 4)
    }

    private var pointColumns: [[WorkoutCaloriesPoint]] {
        stride(from: 0, to: points.count, by: rowCount).map { startIndex in
            let endIndex = min(startIndex + rowCount, points.count)
            return Array(points[startIndex..<endIndex])
        }
    }

    private func color(for point: WorkoutCaloriesPoint) -> Color {
        guard point.kilocalories > 0 else {
            return DataTrackerStyle.cardMuted.opacity(0.62)
        }

        if point.id == selectedDayID {
            return DataTrackerStyle.orange
        }

        return heatColor(intensity(for: point.kilocalories))
    }

    private func legendColor(_ index: Int) -> Color {
        if index == 0 {
            return DataTrackerStyle.cardMuted.opacity(0.62)
        }

        return heatColor(Double(index) / 4)
    }

    private func heatColor(_ intensity: Double) -> Color {
        switch intensity {
        case ..<0.26:
            return Color(red: 0.35, green: 0.18, blue: 0.10)
        case ..<0.51:
            return Color(red: 0.55, green: 0.25, blue: 0.11)
        case ..<0.76:
            return Color(red: 0.76, green: 0.30, blue: 0.10)
        default:
            return DataTrackerStyle.orange
        }
    }

    private func intensity(for kilocalories: Double) -> Double {
        guard maxKilocalories > 0 else {
            return 0
        }

        return min(1, max(0.12, kilocalories / maxKilocalories))
    }

    private func accessibilityLabel(for point: WorkoutCaloriesPoint) -> String {
        let dateText = DateFormatter.healthBridgeDay.string(from: point.date)
        let calories = Int(point.kilocalories.rounded())
        return "\(dateText), \(calories) kcal"
    }
}

private struct EmptyChartState: View {
    let message: String
    var accent: Color = DataTrackerStyle.orange
    var systemImage: String = "chart.bar"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(accent.opacity(0.75))
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DataTrackerStyle.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DataTrackerStyle.cardRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WeightTrendCard: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("体重趋势")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(viewModel.hasWeightTrend ? "最近记录的体重变化" : viewModel.weightTrendMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DataTrackerStyle.textMuted)
                }

                Spacer()

                Text(viewModel.latestWeightText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
            }

            if viewModel.hasWeightTrend {
                WeightTrendLine(points: viewModel.weightTrendPoints)
                    .frame(height: 132)
            } else {
                EmptyChartState(
                    message: viewModel.weightTrendMessage,
                    accent: DataTrackerStyle.green,
                    systemImage: "scalemass.fill"
                )
                .frame(height: 132)
            }
        }
        .padding(20)
        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct WeightTrendLine: View {
    let points: [WeightTrendPoint]

    var body: some View {
        GeometryReader { proxy in
            let values = points.map(\.kilograms)
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let range = max(maxValue - minValue, 0.4)

            ZStack {
                VStack {
                    Rectangle().fill(DataTrackerStyle.separator).frame(height: 1)
                    Spacer()
                    Rectangle().fill(DataTrackerStyle.separator).frame(height: 1)
                    Spacer()
                    Rectangle().fill(DataTrackerStyle.separator).frame(height: 1)
                }

                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = points.count == 1
                            ? proxy.size.width / 2
                            : CGFloat(index) / CGFloat(points.count - 1) * proxy.size.width
                        let normalized = (point.kilograms - minValue) / range
                        let y = proxy.size.height - CGFloat(normalized) * proxy.size.height
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(DataTrackerStyle.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let x = points.count == 1
                        ? proxy.size.width / 2
                        : CGFloat(index) / CGFloat(points.count - 1) * proxy.size.width
                    let normalized = (point.kilograms - minValue) / range
                    let y = proxy.size.height - CGFloat(normalized) * proxy.size.height
                    Circle()
                        .fill(DataTrackerStyle.green)
                        .frame(width: 7, height: 7)
                        .position(x: x, y: y)
                        .accessibilityLabel("\(DateFormatter.healthBridgeDay.string(from: point.date)), \(String(format: "%.1f", point.kilograms)) kg")
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct CalorieIntakeChartCard: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Intake")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(viewModel.calorieSelectedDayText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DataTrackerStyle.textMuted)
                }

                Spacer()

                Text(viewModel.calorieSelectedIntakeText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
            }

            if viewModel.hasCalorieIntake {
                CalorieIntakeHeatmapGrid(
                    points: viewModel.calorieIntake,
                    selectedDayID: viewModel.calorieHighlightedDayID,
                    maxKilocalories: viewModel.calorieHeatmapMaxKilocalories,
                    onSelect: { point in
                        viewModel.selectCalorieDay(point)
                    }
                )
            } else {
                EmptyChartState(
                    message: viewModel.calorieChartMessage ?? "最近 50 天没有饮食热量记录",
                    accent: DataTrackerStyle.green,
                    systemImage: "fork.knife"
                )
                .frame(height: 132)
            }
        }
        .padding(20)
        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct CalorieIntakeHeatmapGrid: View {
    let points: [CalorieIntakePoint]
    let selectedDayID: String?
    let maxKilocalories: Double
    let onSelect: (CalorieIntakePoint) -> Void

    private let rowCount = 5
    private let cellSpacing: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(Array(pointColumns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: cellSpacing) {
                        ForEach(column) { point in
                            Button {
                                onSelect(point)
                            } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(color(for: point))
                                    .overlay {
                                        if point.id == selectedDayID {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(.white.opacity(0.78), lineWidth: 1.5)
                                        }
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accessibilityLabel(for: point))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }

            HStack(spacing: 7) {
                Text("低")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(legendColor(index))
                        .frame(width: 13, height: 13)
                }
                Text("高")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)

                Spacer()

                Text("摄入越低颜色越深")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)
            }
        }
        .padding(.top, 4)
    }

    private var pointColumns: [[CalorieIntakePoint]] {
        stride(from: 0, to: points.count, by: rowCount).map { startIndex in
            let endIndex = min(startIndex + rowCount, points.count)
            return Array(points[startIndex..<endIndex])
        }
    }

    private func color(for point: CalorieIntakePoint) -> Color {
        guard let kilocalories = point.kilocalories else {
            return DataTrackerStyle.cardMuted.opacity(0.62)
        }

        if point.id == selectedDayID {
            return DataTrackerStyle.green
        }

        return heatColor(intensity(for: kilocalories))
    }

    private func legendColor(_ index: Int) -> Color {
        if index == 0 {
            return DataTrackerStyle.greenDeep
        }

        return heatColor(1 - Double(index) / 4)
    }

    private func heatColor(_ intensity: Double) -> Color {
        switch intensity {
        case 0.76...:
            return DataTrackerStyle.greenDeep
        case 0.51..<0.76:
            return Color(red: 0.08, green: 0.55, blue: 0.24)
        case 0.26..<0.51:
            return Color(red: 0.18, green: 0.68, blue: 0.34)
        default:
            return Color(red: 0.47, green: 0.82, blue: 0.55)
        }
    }

    private func intensity(for kilocalories: Double) -> Double {
        guard maxKilocalories > 0 else {
            return 0
        }

        let normalizedHighIntake = min(1, max(0, kilocalories / maxKilocalories))
        return 1 - normalizedHighIntake
    }

    private func accessibilityLabel(for point: CalorieIntakePoint) -> String {
        let dateText = DateFormatter.healthBridgeDay.string(from: point.date)
        guard let kilocalories = point.kilocalories else {
            return "\(dateText), 无摄入记录"
        }
        return "\(dateText), \(Int(kilocalories.rounded())) kcal"
    }
}

private struct RecentWorkoutCard: View {
    let rows: [RecentWorkoutRow]
    let allRows: [RecentWorkoutRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("最近训练")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if !allRows.isEmpty {
                    NavigationLink {
                        WorkoutHistoryView(rows: allRows)
                    } label: {
                        HStack(spacing: 4) {
                            Text("查看更多")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DataTrackerStyle.orange)
                    }
                }
            }

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

private struct WorkoutHistoryView: View {
    let rows: [RecentWorkoutRow]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if rows.isEmpty {
                    EmptyWorkoutHistoryState()
                } else {
                    ForEach(rows) { row in
                        RecentWorkoutRowView(row: row)
                            .padding(18)
                            .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(DataTrackerStyle.background.ignoresSafeArea())
        .navigationTitle("全部训练")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DataTrackerStyle.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct EmptyWorkoutHistoryState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(DataTrackerStyle.orange.opacity(0.78))
            Text("暂无训练记录")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DataTrackerStyle.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

private struct RecentHealthRecordCard: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("最近记录")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if !viewModel.allRecordRows.isEmpty {
                    NavigationLink {
                        HealthRecordHistoryView(viewModel: viewModel)
                    } label: {
                        HStack(spacing: 4) {
                            Text("查看更多")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DataTrackerStyle.green)
                    }
                }
            }

            if viewModel.recentRecordRows.isEmpty {
                Text("暂无体重或饮食记录")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DataTrackerStyle.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(viewModel.recentRecordRows) { row in
                    HealthRecordRowView(row: row)

                    if row.id != viewModel.recentRecordRows.last?.id {
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

private struct HealthRecordHistoryView: View {
    @ObservedObject var viewModel: HealthReporterViewModel
    @State private var editingPacket: HealthPacket?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.allRecordRows.isEmpty {
                    EmptyHealthRecordState()
                } else {
                    ForEach(viewModel.allRecordRows) { row in
                        Button {
                            editingPacket = row.packet
                        } label: {
                            HealthRecordRowView(row: row)
                                .padding(18)
                                .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(DataTrackerStyle.background.ignoresSafeArea())
        .navigationTitle("全部记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DataTrackerStyle.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $editingPacket) { packet in
            HealthRecordEditorView(viewModel: viewModel, packet: packet)
        }
    }
}

private struct EmptyHealthRecordState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(DataTrackerStyle.green.opacity(0.78))
            Text("暂无记录")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DataTrackerStyle.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct HealthRecordRowView: View {
    let row: HealthRecordRow

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DataTrackerStyle.green.opacity(0.13))
                Image(systemName: row.systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DataTrackerStyle.green)
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

private struct HealthRecordEditorView: View {
    @ObservedObject var viewModel: HealthReporterViewModel
    let packet: HealthPacket

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var weightText: String
    @State private var rawText: String
    @State private var noteText: String
    @State private var mealTypeText: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbohydratesText: String
    @State private var fatText: String
    @State private var confidence: HealthPacketConfidence
    @State private var errorText: String?
    @State private var isSaving = false

    init(viewModel: HealthReporterViewModel, packet: HealthPacket) {
        self.viewModel = viewModel
        self.packet = packet

        let bodyWeight = packet.bodyWeight
        let foodIntake = packet.foodIntake
        _date = State(initialValue: bodyWeight?.measuredAt ?? foodIntake?.occurredAt ?? packet.updatedAt)
        _weightText = State(initialValue: bodyWeight.map { String(format: "%.1f", $0.weightKilograms) } ?? "")
        _rawText = State(initialValue: bodyWeight?.rawText ?? foodIntake?.rawText ?? "")
        _noteText = State(initialValue: bodyWeight?.note ?? "")
        _mealTypeText = State(initialValue: foodIntake?.mealType ?? "")
        _caloriesText = State(initialValue: foodIntake.map { String(format: "%.0f", $0.estimatedCaloriesKcal) } ?? "")
        _proteinText = State(initialValue: foodIntake?.proteinGrams.map { String(format: "%.1f", $0) } ?? "")
        _carbohydratesText = State(initialValue: foodIntake?.carbohydrateGrams.map { String(format: "%.1f", $0) } ?? "")
        _fatText = State(initialValue: foodIntake?.fatGrams.map { String(format: "%.1f", $0) } ?? "")
        _confidence = State(initialValue: foodIntake?.confidence ?? .medium)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if packet.type == .bodyWeight {
                        EditorField(title: "体重 kg", text: $weightText, keyboardType: .decimalPad)
                        EditorField(title: "原始记录", text: $rawText)
                        EditorField(title: "备注", text: $noteText)
                    } else {
                        EditorField(title: "描述", text: $rawText)
                        EditorField(title: "热量 kcal", text: $caloriesText, keyboardType: .decimalPad)
                        EditorField(title: "餐别", text: $mealTypeText)
                        HStack(spacing: 10) {
                            EditorField(title: "蛋白 g", text: $proteinText, keyboardType: .decimalPad)
                            EditorField(title: "碳水 g", text: $carbohydratesText, keyboardType: .decimalPad)
                            EditorField(title: "脂肪 g", text: $fatText, keyboardType: .decimalPad)
                        }
                        Picker("置信度", selection: $confidence) {
                            Text("低").tag(HealthPacketConfidence.low)
                            Text("中").tag(HealthPacketConfidence.medium)
                            Text("高").tag(HealthPacketConfidence.high)
                        }
                        .pickerStyle(.segmented)
                    }

                    DatePicker("时间", selection: $date)
                        .datePickerStyle(.compact)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red.opacity(0.86))
                            .padding(.top, 2)
                    }
                }
                .padding(20)
            }
            .background(DataTrackerStyle.background.ignoresSafeArea())
            .navigationTitle(packet.type == .bodyWeight ? "编辑体重" : "编辑饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DataTrackerStyle.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中" : "保存") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        errorText = nil
        isSaving = true
        defer { isSaving = false }

        do {
            if packet.type == .bodyWeight {
                guard let kilograms = Double(weightText.trimmingCharacters(in: .whitespacesAndNewlines)), kilograms > 0 else {
                    errorText = "请输入有效体重"
                    return
                }
                try await viewModel.updateBodyWeightPacket(
                    packet,
                    measuredAt: date,
                    kilograms: kilograms,
                    rawText: rawText,
                    note: noteText
                )
            } else {
                guard let calories = Double(caloriesText.trimmingCharacters(in: .whitespacesAndNewlines)), calories > 0 else {
                    errorText = "请输入有效热量"
                    return
                }
                let protein = optionalDouble(proteinText)
                let carbohydrates = optionalDouble(carbohydratesText)
                let fat = optionalDouble(fatText)
                try await viewModel.updateFoodPacket(
                    packet,
                    occurredAt: date,
                    rawText: rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "饮食记录" : rawText,
                    mealType: mealTypeText,
                    calories: calories,
                    protein: protein,
                    carbohydrates: carbohydrates,
                    fat: fat,
                    confidence: confidence
                )
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func optionalDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}

private struct EditorField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DataTrackerStyle.textMuted)
            TextField(title, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(DataTrackerStyle.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
