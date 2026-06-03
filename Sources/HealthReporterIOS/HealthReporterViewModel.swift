import Foundation

struct WorkoutCaloriesPoint: Identifiable, Hashable {
    var id: String
    var date: Date
    var kilocalories: Double
}

struct RecentWorkoutRow: Identifiable, Hashable {
    var id: UUID
    var title: String
    var subtitle: String
    var detail: String
    var systemImage: String
}

@MainActor
final class HealthReporterViewModel: ObservableObject {
    @Published private(set) var isReportingEnabled = false
    @Published private(set) var statusText = "未开启"
    @Published private(set) var lastSyncText = "尚未成功上报"
    @Published private(set) var targetText = "MagicDNS：\(HealthBridgeConstants.tailnetHost):\(HealthBridgeConstants.port)"
    @Published private(set) var queuedText = "无"
    @Published private(set) var errorText: String?
    @Published private(set) var workoutCalories: [WorkoutCaloriesPoint] = []
    @Published private(set) var workoutChartMessage: String? = "状态页开启健康上报后显示"
    @Published private(set) var workoutCaloriesTotalText = "0 kcal"
    @Published private(set) var workoutCountText = "0 次"
    @Published private(set) var workoutActiveDaysText = "0 天"
    @Published private(set) var workoutDailyAverageText = "0 kcal"
    @Published private(set) var workoutSelectedCaloriesText = "0 kcal"
    @Published private(set) var workoutSelectedDayText = "暂无训练日"
    @Published private(set) var workoutHighlightedDayID: String?
    @Published private(set) var workoutChartAverageKilocalories: Double = 0
    @Published private(set) var recentWorkoutRows: [RecentWorkoutRow] = []
    @Published private(set) var latestWorkoutText = "暂无"
    @Published private(set) var syncBadgeText = "未同步"

    private let service = HealthReporterService.shared
    private let workoutChartDays = 30
    private static let workoutDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let workoutDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    var hasWorkoutCalories: Bool {
        workoutCalories.contains { $0.kilocalories > 0 }
    }

    func load() async {
        isReportingEnabled = service.isReportingEnabled
        updateStatusText()
        await refreshDisplay()
        await refreshWorkoutChart()
    }

    func setReportingEnabled(_ enabled: Bool) {
        isReportingEnabled = enabled
        statusText = enabled ? "正在授权并启动" : "正在关闭"

        Task {
            do {
                try await service.setReportingEnabled(enabled)
                await MainActor.run {
                    self.isReportingEnabled = self.service.isReportingEnabled
                    self.updateStatusText()
                }
                await self.refreshDisplay()
                await self.refreshWorkoutChart()
            } catch {
                await MainActor.run {
                    self.isReportingEnabled = self.service.isReportingEnabled
                    self.statusText = error.localizedDescription
                }
                await self.refreshDisplay()
                await self.refreshWorkoutChart()
            }
        }
    }

    func refreshDisplay() async {
        let queuedCount = await service.pendingReportCount()
        await MainActor.run {
            self.lastSyncText = HealthBridgeDisplayTime.latestSyncText(for: self.service.lastSuccessfulSyncDate)
            self.syncBadgeText = self.compactSyncText(for: self.service.lastSuccessfulSyncDate)
            self.targetText = self.service.lastSuccessfulEndpoint
                ?? "MagicDNS：\(HealthBridgeConstants.tailnetHost):\(HealthBridgeConstants.port)\n备用 IPv4：\(HealthBridgeConstants.tailnetIPv4):\(HealthBridgeConstants.port)"
            self.queuedText = queuedCount == 0 ? "无" : "\(queuedCount) 条待补发"
            self.errorText = self.service.lastUploadError
            self.updateStatusText()
        }
    }

    func refreshWorkoutChart() async {
        guard isReportingEnabled else {
            workoutCalories = emptyWorkoutCalories()
            workoutChartMessage = "状态页开启健康上报后显示"
            workoutCaloriesTotalText = "0 kcal"
            workoutCountText = "0 次"
            workoutActiveDaysText = "0 天"
            workoutDailyAverageText = "0 kcal"
            workoutSelectedCaloriesText = "0 kcal"
            workoutSelectedDayText = "暂无训练日"
            workoutHighlightedDayID = nil
            workoutChartAverageKilocalories = 0
            recentWorkoutRows = []
            latestWorkoutText = "暂无"
            return
        }

        do {
            let workouts = try await service.recentWorkoutsForDisplay(days: workoutChartDays, limit: 100)
            let points = makeWorkoutCaloriesPoints(from: workouts)
            let total = points.reduce(0) { $0 + $1.kilocalories }
            let activeDays = points.filter { $0.kilocalories > 0 }.count
            let latestWorkout = workouts.max { $0.startDate < $1.startDate }
            let highlightedPoint = points.filter { $0.kilocalories > 0 }.max { $0.date < $1.date }

            workoutCalories = points
            workoutChartMessage = total > 0 ? nil : "最近 \(workoutChartDays) 天没有可展示的 workout 卡路里"
            workoutCaloriesTotalText = formatCalories(total)
            workoutCountText = "\(workouts.count) 次"
            workoutActiveDaysText = "\(activeDays) 天"
            workoutDailyAverageText = formatCalories(total / Double(workoutChartDays))
            workoutSelectedCaloriesText = highlightedPoint.map { formatCalories($0.kilocalories) } ?? "0 kcal"
            workoutSelectedDayText = highlightedPoint.map { "\(Self.workoutDayFormatter.string(from: $0.date)) · 最近训练日" } ?? "暂无训练日"
            workoutHighlightedDayID = highlightedPoint?.id
            workoutChartAverageKilocalories = activeDays > 0 ? total / Double(activeDays) : 0
            recentWorkoutRows = makeRecentWorkoutRows(from: workouts)
            latestWorkoutText = latestWorkout.map(formatLatestWorkout) ?? "暂无"
        } catch {
            workoutCalories = emptyWorkoutCalories()
            workoutChartMessage = error.localizedDescription
            workoutCaloriesTotalText = "0 kcal"
            workoutCountText = "0 次"
            workoutActiveDaysText = "0 天"
            workoutDailyAverageText = "0 kcal"
            workoutSelectedCaloriesText = "0 kcal"
            workoutSelectedDayText = "暂无训练日"
            workoutHighlightedDayID = nil
            workoutChartAverageKilocalories = 0
            recentWorkoutRows = []
            latestWorkoutText = "暂无"
        }
    }

    private func updateStatusText() {
        if isReportingEnabled {
            if service.lastUploadError == nil {
                statusText = "已开启"
            } else {
                statusText = "已开启，等待 Mac 可达"
            }
        } else {
            statusText = "未开启"
        }
    }

    private func makeWorkoutCaloriesPoints(from workouts: [HealthWorkout]) -> [WorkoutCaloriesPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(workoutChartDays - 1), to: today) else {
            return []
        }

        var totalsByDay: [Date: Double] = [:]
        for dayOffset in 0..<workoutChartDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            totalsByDay[day] = 0
        }

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            guard day >= startDate, day <= today else { continue }
            totalsByDay[day, default: 0] += workout.totalEnergyBurnedKilocalories ?? 0
        }

        return totalsByDay
            .sorted { $0.key < $1.key }
            .map { day, kilocalories in
                WorkoutCaloriesPoint(
                    id: DateFormatter.healthBridgeDay.string(from: day),
                    date: day,
                    kilocalories: kilocalories
                )
            }
    }

    private func emptyWorkoutCalories() -> [WorkoutCaloriesPoint] {
        makeWorkoutCaloriesPoints(from: [])
    }

    private func formatLatestWorkout(_ workout: HealthWorkout) -> String {
        let activity = localizedWorkoutName(workout.activityName)
        let calories = workout.totalEnergyBurnedKilocalories.map(formatCalories) ?? "无 kcal"
        let time = HealthBridgeDisplayTime.latestSyncText(for: workout.endDate)
        return "\(activity) · \(calories) · \(time)"
    }

    private func makeRecentWorkoutRows(from workouts: [HealthWorkout]) -> [RecentWorkoutRow] {
        workouts
            .sorted { $0.startDate > $1.startDate }
            .prefix(3)
            .map { workout in
                RecentWorkoutRow(
                    id: workout.id,
                    title: localizedWorkoutName(workout.activityName),
                    subtitle: "\(Self.workoutDateFormatter.string(from: workout.startDate)) · \(formatDuration(workout.durationSeconds))",
                    detail: workout.totalEnergyBurnedKilocalories.map(formatCalories) ?? "无 kcal",
                    systemImage: workoutSystemImage(workout.activityName)
                )
            }
    }

    private func localizedWorkoutName(_ activityName: String) -> String {
        switch activityName {
        case "walking":
            return "步行"
        case "running":
            return "跑步"
        case "cycling":
            return "骑行"
        case "hiking":
            return "徒步"
        case "swimming":
            return "游泳"
        case "yoga":
            return "瑜伽"
        case "traditionalStrengthTraining":
            return "力量训练"
        case "functionalStrengthTraining":
            return "功能力量"
        case "highIntensityIntervalTraining":
            return "HIIT"
        case "coreTraining":
            return "核心训练"
        case "elliptical":
            return "椭圆机"
        case "rowing":
            return "划船"
        case "stairClimbing":
            return "爬楼"
        case "mindAndBody":
            return "身心训练"
        case "other":
            return "其他"
        default:
            return activityName
        }
    }

    private func formatCalories(_ value: Double) -> String {
        if value >= 100 {
            return "\(Int(value.rounded())) kcal"
        }

        return String(format: "%.1f kcal", value)
    }

    private func compactSyncText(for date: Date?) -> String {
        guard let date else {
            return "未同步"
        }

        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "刚刚"
        }

        if elapsed < 3_600 {
            return "\(Int(elapsed / 60)) 分钟前"
        }

        if elapsed < 86_400 {
            return "\(Int(elapsed / 3_600)) 小时前"
        }

        return DateFormatter.healthBridgeDay.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 {
            return "\(minutes) 分钟"
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours) 小时"
        }

        return "\(hours) 小时 \(remainder) 分钟"
    }

    private func workoutSystemImage(_ activityName: String) -> String {
        switch activityName {
        case "walking":
            return "figure.walk"
        case "running":
            return "figure.run"
        case "cycling":
            return "bicycle"
        case "hiking":
            return "figure.hiking"
        case "swimming":
            return "figure.pool.swim"
        case "yoga", "mindAndBody":
            return "figure.mind.and.body"
        case "traditionalStrengthTraining", "functionalStrengthTraining":
            return "dumbbell"
        case "highIntensityIntervalTraining":
            return "flame.fill"
        case "coreTraining":
            return "figure.core.training"
        case "elliptical":
            return "figure.elliptical"
        case "rowing":
            return "figure.rower"
        case "stairClimbing":
            return "figure.stair.stepper"
        default:
            return "figure.mixed.cardio"
        }
    }
}
