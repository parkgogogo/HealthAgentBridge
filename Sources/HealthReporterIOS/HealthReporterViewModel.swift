import Foundation

struct WorkoutCaloriesPoint: Identifiable, Hashable {
    var id: String
    var date: Date
    var kilocalories: Double
}

struct ActiveEnergySummaryCard: Identifiable, Hashable {
    var id: String
    var title: String
    var totalText: String
    var detailText: String

    static let placeholders = [
        ActiveEnergySummaryCard(id: "today", title: "今天活动消耗", totalText: "0 kcal", detailText: "今日实时累计 · 活动 0 天"),
        ActiveEnergySummaryCard(id: "seven-days", title: "最近 7 天活动消耗", totalText: "0 kcal", detailText: "日均 0 kcal · 活动 0 天"),
        ActiveEnergySummaryCard(id: "thirty-days", title: "最近 30 天活动消耗", totalText: "0 kcal", detailText: "日均 0 kcal · 活动 0 天")
    ]
}

struct RecentWorkoutRow: Identifiable, Hashable {
    var id: UUID
    var title: String
    var subtitle: String
    var detail: String
    var systemImage: String
}

struct CalorieIntakePoint: Identifiable, Hashable {
    var id: String
    var date: Date
    var kilocalories: Double?
}

struct WeightTrendPoint: Identifiable, Hashable {
    var id: String
    var date: Date
    var kilograms: Double
}

struct HealthRecordRow: Identifiable, Hashable {
    var id: String
    var packet: HealthPacket
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
    @Published private(set) var activeEnergyCards = ActiveEnergySummaryCard.placeholders
    @Published private(set) var workoutCaloriesTotalText = "0 kcal"
    @Published private(set) var workoutCountText = "0 次"
    @Published private(set) var workoutActiveDaysText = "0 天"
    @Published private(set) var workoutDailyAverageText = "0 kcal"
    @Published private(set) var workoutSelectedCaloriesText = "0 kcal"
    @Published private(set) var workoutSelectedDayText = "暂无训练日"
    @Published private(set) var workoutHighlightedDayID: String?
    @Published private(set) var workoutChartAverageKilocalories: Double = 0
    @Published private(set) var recentWorkoutRows: [RecentWorkoutRow] = []
    @Published private(set) var allWorkoutRows: [RecentWorkoutRow] = []
    @Published private(set) var latestWorkoutText = "暂无"
    @Published private(set) var syncBadgeText = "未同步"
    @Published private(set) var calorieIntake: [CalorieIntakePoint] = []
    @Published private(set) var calorieChartMessage: String? = "状态页开启健康上报后显示"
    @Published private(set) var calorieIntakeTotalText = "0 kcal"
    @Published private(set) var calorieDailyAverageText = "0 kcal"
    @Published private(set) var calorieTrackedDaysText = "0 天"
    @Published private(set) var calorieSelectedIntakeText = "0 kcal"
    @Published private(set) var calorieSelectedDayText = "暂无记录"
    @Published private(set) var calorieHighlightedDayID: String?
    @Published private(set) var weightTrendPoints: [WeightTrendPoint] = []
    @Published private(set) var weightTrendMessage = "至少记录 7 天体重后展示趋势"
    @Published private(set) var latestWeightText = "暂无"
    @Published private(set) var weightDeltaText = "数据不足"
    @Published private(set) var recentRecordRows: [HealthRecordRow] = []
    @Published private(set) var allRecordRows: [HealthRecordRow] = []
    @Published private(set) var recordErrorText: String?

    private let service = HealthReporterService.shared
    private let workoutChartDays = 50
    private let workoutSummaryDays = 7
    private let nutritionChartDays = 50
    private let nutritionSummaryDays = 7
    private let weightTrendMinimumDays = 7
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

    var workoutHeatmapMaxKilocalories: Double {
        workoutCalories.map(\.kilocalories).max() ?? 0
    }

    var hasCalorieIntake: Bool {
        calorieIntake.contains { ($0.kilocalories ?? 0) > 0 }
    }

    var hasWeightTrend: Bool {
        weightTrendPoints.count >= weightTrendMinimumDays
    }

    var calorieHeatmapMaxKilocalories: Double {
        max(2_400, calorieIntake.compactMap(\.kilocalories).max() ?? 0)
    }

    func load() async {
        isReportingEnabled = service.isReportingEnabled
        updateStatusText()
        await refreshDisplay()
        await refreshWorkoutChart()
        await refreshNutritionDashboard()
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
                await self.refreshNutritionDashboard()
            } catch {
                await MainActor.run {
                    self.isReportingEnabled = self.service.isReportingEnabled
                    self.statusText = error.localizedDescription
                }
                await self.refreshDisplay()
                await self.refreshWorkoutChart()
                await self.refreshNutritionDashboard()
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
            activeEnergyCards = emptyActiveEnergyCards()
            workoutCaloriesTotalText = "0 kcal"
            workoutCountText = "0 次"
            workoutActiveDaysText = "0 天"
            workoutDailyAverageText = "0 kcal"
            workoutSelectedCaloriesText = "0 kcal"
            workoutSelectedDayText = "暂无训练日"
            workoutHighlightedDayID = nil
            workoutChartAverageKilocalories = 0
            recentWorkoutRows = []
            allWorkoutRows = []
            latestWorkoutText = "暂无"
            return
        }

        do {
            async let summariesTask = service.dailySummariesForDisplay(days: workoutChartDays)
            async let workoutsTask = service.recentWorkoutsForDisplay(days: workoutChartDays, limit: 100)
            let (summaries, workouts) = try await (summariesTask, workoutsTask)
            let points = makeWorkoutCaloriesPoints(from: workouts)
            let chartTotal = points.reduce(0) { $0 + $1.kilocalories }
            let chartActiveDays = points.filter { $0.kilocalories > 0 }.count
            let summaryPoints = workoutSummaryPoints(from: points)
            let summaryTotal = summaryPoints.reduce(0) { $0 + $1.kilocalories }
            let summaryActiveDays = summaryPoints.filter { $0.kilocalories > 0 }.count
            let summaryWorkouts = workoutsInSummaryWindow(workouts, summaryPoints: summaryPoints)
            let latestWorkout = workouts.max { $0.startDate < $1.startDate }
            let highlightedPoint = points.first { $0.id == workoutHighlightedDayID }
                ?? points.filter { $0.kilocalories > 0 }.max { $0.date < $1.date }

            workoutCalories = points
            workoutChartMessage = chartTotal > 0 ? nil : "最近 \(workoutChartDays) 天没有可展示的 workout 热量"
            activeEnergyCards = makeActiveEnergyCards(from: summaries)
            workoutCaloriesTotalText = formatCalories(summaryTotal)
            workoutCountText = "\(summaryWorkouts.count) 次"
            workoutActiveDaysText = "\(summaryActiveDays) 天"
            workoutDailyAverageText = formatCalories(summaryTotal / Double(workoutSummaryDays))
            updateSelectedWorkoutPoint(highlightedPoint, reason: highlightedPoint?.kilocalories ?? 0 > 0 ? "最近训练日" : "已选择")
            workoutChartAverageKilocalories = chartActiveDays > 0 ? chartTotal / Double(chartActiveDays) : 0
            allWorkoutRows = makeWorkoutRows(from: workouts)
            recentWorkoutRows = Array(allWorkoutRows.prefix(3))
            latestWorkoutText = latestWorkout.map(formatLatestWorkout) ?? "暂无"
        } catch {
            workoutCalories = emptyWorkoutCalories()
            workoutChartMessage = error.localizedDescription
            activeEnergyCards = emptyActiveEnergyCards()
            workoutCaloriesTotalText = "0 kcal"
            workoutCountText = "0 次"
            workoutActiveDaysText = "0 天"
            workoutDailyAverageText = "0 kcal"
            workoutSelectedCaloriesText = "0 kcal"
            workoutSelectedDayText = "暂无训练日"
            workoutHighlightedDayID = nil
            workoutChartAverageKilocalories = 0
            recentWorkoutRows = []
            allWorkoutRows = []
            latestWorkoutText = "暂无"
        }
    }

    func refreshNutritionDashboard() async {
        guard isReportingEnabled else {
            resetNutritionDashboard(message: "状态页开启健康上报后显示")
            return
        }

        do {
            async let summariesTask = service.dailySummariesForDisplay(days: nutritionChartDays)
            async let packetsTask = service.recentHealthPacketsForDisplay(limit: 100)
            let (summaries, packets) = try await (summariesTask, packetsTask)
            let caloriePoints = makeCalorieIntakePoints(from: summaries)
            let summaryPoints = Array(caloriePoints.suffix(nutritionSummaryDays))
            let trackedSummaryPoints = summaryPoints.compactMap(\.kilocalories)
            let summaryTotal = trackedSummaryPoints.reduce(0, +)
            let trackedDays = trackedSummaryPoints.count
            let highlightedPoint = caloriePoints.first { $0.id == calorieHighlightedDayID }
                ?? caloriePoints.reversed().first { $0.kilocalories != nil }
            let weights = makeWeightTrendPoints(from: summaries)
            let rows = makeRecordRows(from: packets)

            calorieIntake = caloriePoints
            calorieChartMessage = caloriePoints.contains { $0.kilocalories != nil }
                ? nil
                : "最近 \(nutritionChartDays) 天没有饮食热量记录"
            calorieIntakeTotalText = formatCalories(summaryTotal)
            calorieDailyAverageText = trackedDays > 0 ? formatCalories(summaryTotal / Double(trackedDays)) : "0 kcal"
            calorieTrackedDaysText = "\(trackedDays) 天"
            updateSelectedCaloriePoint(highlightedPoint, reason: highlightedPoint?.kilocalories == nil ? "无记录" : "已选择")
            weightTrendPoints = weights
            latestWeightText = weights.last.map { String(format: "%.1f kg", $0.kilograms) } ?? "暂无"
            weightDeltaText = formatWeightDelta(weights)
            weightTrendMessage = weights.count >= weightTrendMinimumDays
                ? ""
                : "已有 \(weights.count) 天，至少 \(weightTrendMinimumDays) 天后展示趋势"
            allRecordRows = rows
            recentRecordRows = Array(rows.prefix(3))
            recordErrorText = nil
        } catch {
            resetNutritionDashboard(message: error.localizedDescription)
        }
    }

    func selectWorkoutDay(_ point: WorkoutCaloriesPoint) {
        updateSelectedWorkoutPoint(point, reason: point.kilocalories > 0 ? "已选择" : "无 workout")
    }

    func selectCalorieDay(_ point: CalorieIntakePoint) {
        updateSelectedCaloriePoint(point, reason: point.kilocalories == nil ? "无记录" : "已选择")
    }

    func updateBodyWeightPacket(_ packet: HealthPacket, measuredAt: Date, kilograms: Double, rawText: String?, note: String?) async throws {
        let payload = BodyWeightPayload(
            measuredAt: measuredAt,
            weightKilograms: kilograms,
            rawText: rawText?.nilIfBlank,
            note: note?.nilIfBlank
        )
        _ = try await service.updateHealthPacketForDisplay(
            packetId: packet.packetId,
            request: HealthPacketUpdateRequest(foodIntake: nil, bodyWeight: payload)
        )
        await refreshDisplay()
        await refreshNutritionDashboard()
    }

    func updateFoodPacket(
        _ packet: HealthPacket,
        occurredAt: Date,
        rawText: String,
        mealType: String?,
        calories: Double,
        protein: Double?,
        carbohydrates: Double?,
        fat: Double?,
        confidence: HealthPacketConfidence
    ) async throws {
        let payload = FoodIntakePayload(
            occurredAt: occurredAt,
            mealType: mealType?.nilIfBlank,
            rawText: rawText,
            foodItems: [
                FoodItemEstimate(
                    name: rawText,
                    estimatedCaloriesKcal: calories,
                    proteinGrams: protein,
                    carbohydrateGrams: carbohydrates,
                    fatGrams: fat
                )
            ],
            estimatedCaloriesKcal: calories,
            proteinGrams: protein,
            carbohydrateGrams: carbohydrates,
            fatGrams: fat,
            confidence: confidence,
            estimationNotes: nil
        )
        _ = try await service.updateHealthPacketForDisplay(
            packetId: packet.packetId,
            request: HealthPacketUpdateRequest(foodIntake: payload, bodyWeight: nil)
        )
        await refreshDisplay()
        await refreshNutritionDashboard()
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

    private func makeActiveEnergyCards(from summaries: [DailyHealthSummary]) -> [ActiveEnergySummaryCard] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let summariesByDay = Dictionary(uniqueKeysWithValues: summaries.map { ($0.date, $0) })

        let todayEnergy = activeEnergyTotal(
            days: 1,
            today: today,
            calendar: calendar,
            summariesByDay: summariesByDay
        )
        let sevenDayEnergy = activeEnergyTotal(
            days: 7,
            today: today,
            calendar: calendar,
            summariesByDay: summariesByDay
        )
        let thirtyDayEnergy = activeEnergyTotal(
            days: 30,
            today: today,
            calendar: calendar,
            summariesByDay: summariesByDay
        )

        return [
            ActiveEnergySummaryCard(
                id: "today",
                title: "今天活动消耗",
                totalText: formatCalories(todayEnergy.total),
                detailText: "今日实时累计 · 活动 \(todayEnergy.activeDays) 天"
            ),
            ActiveEnergySummaryCard(
                id: "seven-days",
                title: "最近 7 天活动消耗",
                totalText: formatCalories(sevenDayEnergy.total),
                detailText: "日均 \(formatCalories(sevenDayEnergy.average)) · 活动 \(sevenDayEnergy.activeDays) 天"
            ),
            ActiveEnergySummaryCard(
                id: "thirty-days",
                title: "最近 30 天活动消耗",
                totalText: formatCalories(thirtyDayEnergy.total),
                detailText: "日均 \(formatCalories(thirtyDayEnergy.average)) · 活动 \(thirtyDayEnergy.activeDays) 天"
            )
        ]
    }

    private func emptyActiveEnergyCards() -> [ActiveEnergySummaryCard] {
        ActiveEnergySummaryCard.placeholders
    }

    private func activeEnergyTotal(
        days: Int,
        today: Date,
        calendar: Calendar,
        summariesByDay: [String: DailyHealthSummary]
    ) -> (total: Double, average: Double, activeDays: Int) {
        let values = (0..<days).compactMap { offset -> Double? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let id = DateFormatter.healthBridgeDay.string(from: day)
            return summariesByDay[id]?.activeEnergyKilocalories ?? 0
        }
        let total = values.reduce(0, +)
        let activeDays = values.filter { $0 > 0 }.count
        let average = days > 0 ? total / Double(days) : 0
        return (total, average, activeDays)
    }

    private func workoutSummaryPoints(from points: [WorkoutCaloriesPoint]) -> [WorkoutCaloriesPoint] {
        Array(points.suffix(workoutSummaryDays))
    }

    private func workoutsInSummaryWindow(_ workouts: [HealthWorkout], summaryPoints: [WorkoutCaloriesPoint]) -> [HealthWorkout] {
        guard let startDate = summaryPoints.first?.date,
              let endDate = summaryPoints.last?.date
        else {
            return []
        }

        let calendar = Calendar.current
        return workouts.filter { workout in
            let day = calendar.startOfDay(for: workout.startDate)
            return day >= startDate && day <= endDate
        }
    }

    private func formatLatestWorkout(_ workout: HealthWorkout) -> String {
        let activity = localizedWorkoutName(workout.activityName)
        let calories = workout.totalEnergyBurnedKilocalories.map(formatCalories) ?? "无 kcal"
        let time = HealthBridgeDisplayTime.latestSyncText(for: workout.endDate)
        return "\(activity) · \(calories) · \(time)"
    }

    private func updateSelectedWorkoutPoint(_ point: WorkoutCaloriesPoint?, reason: String) {
        guard let point else {
            workoutSelectedCaloriesText = "0 kcal"
            workoutSelectedDayText = "暂无训练日"
            workoutHighlightedDayID = nil
            return
        }

        workoutSelectedCaloriesText = formatCalories(point.kilocalories)
        workoutSelectedDayText = "\(Self.workoutDayFormatter.string(from: point.date)) · \(reason)"
        workoutHighlightedDayID = point.id
    }

    private func updateSelectedCaloriePoint(_ point: CalorieIntakePoint?, reason: String) {
        guard let point else {
            calorieSelectedIntakeText = "0 kcal"
            calorieSelectedDayText = "暂无记录"
            calorieHighlightedDayID = nil
            return
        }

        calorieSelectedIntakeText = point.kilocalories.map(formatCalories) ?? "无记录"
        calorieSelectedDayText = "\(Self.workoutDayFormatter.string(from: point.date)) · \(reason)"
        calorieHighlightedDayID = point.id
    }

    private func resetNutritionDashboard(message: String) {
        calorieIntake = emptyCalorieIntake()
        calorieChartMessage = message
        calorieIntakeTotalText = "0 kcal"
        calorieDailyAverageText = "0 kcal"
        calorieTrackedDaysText = "0 天"
        calorieSelectedIntakeText = "0 kcal"
        calorieSelectedDayText = "暂无记录"
        calorieHighlightedDayID = nil
        weightTrendPoints = []
        weightTrendMessage = "至少记录 \(weightTrendMinimumDays) 天体重后展示趋势"
        latestWeightText = "暂无"
        weightDeltaText = "数据不足"
        recentRecordRows = []
        allRecordRows = []
        recordErrorText = message
    }

    private func makeCalorieIntakePoints(from summaries: [DailyHealthSummary]) -> [CalorieIntakePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(nutritionChartDays - 1), to: today) else {
            return []
        }

        var summariesByDay: [String: DailyHealthSummary] = [:]
        for summary in summaries {
            summariesByDay[summary.date] = summary
        }

        return (0..<nutritionChartDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            let id = DateFormatter.healthBridgeDay.string(from: day)
            return CalorieIntakePoint(
                id: id,
                date: day,
                kilocalories: summariesByDay[id]?.dietaryEnergyKilocalories
            )
        }
    }

    private func emptyCalorieIntake() -> [CalorieIntakePoint] {
        makeCalorieIntakePoints(from: [])
    }

    private func makeWeightTrendPoints(from summaries: [DailyHealthSummary]) -> [WeightTrendPoint] {
        summaries.compactMap { summary in
            guard let kilograms = summary.bodyMassKilograms,
                  let date = DateFormatter.healthBridgeDay.date(from: summary.date) else {
                return nil
            }
            return WeightTrendPoint(id: summary.date, date: date, kilograms: kilograms)
        }
        .sorted { $0.date < $1.date }
    }

    private func formatWeightDelta(_ points: [WeightTrendPoint]) -> String {
        guard let first = points.first, let last = points.last, points.count >= 2 else {
            return "数据不足"
        }

        let delta = last.kilograms - first.kilograms
        if abs(delta) < 0.05 {
            return "基本持平"
        }

        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", delta)) kg"
    }

    private func makeRecordRows(from packets: [HealthPacket]) -> [HealthRecordRow] {
        packets
            .filter { $0.type == .foodIntake || $0.type == .bodyWeight }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { packet in
                switch packet.type {
                case .bodyWeight:
                    let payload = packet.bodyWeight
                    let weight = payload.map { String(format: "%.1f kg", $0.weightKilograms) } ?? "体重"
                    let date = payload.map { Self.workoutDateFormatter.string(from: $0.measuredAt) } ?? Self.workoutDateFormatter.string(from: packet.updatedAt)
                    return HealthRecordRow(
                        id: packet.packetId,
                        packet: packet,
                        title: "体重",
                        subtitle: "\(date) · \(localizedPacketStatus(packet.status))",
                        detail: weight,
                        systemImage: "scalemass.fill"
                    )
                case .foodIntake:
                    let payload = packet.foodIntake
                    let title = payload?.mealType?.nilIfBlank ?? "饮食"
                    let date = payload.map { Self.workoutDateFormatter.string(from: $0.occurredAt) } ?? Self.workoutDateFormatter.string(from: packet.updatedAt)
                    return HealthRecordRow(
                        id: packet.packetId,
                        packet: packet,
                        title: title,
                        subtitle: "\(date) · \(localizedPacketStatus(packet.status))",
                        detail: payload.map { formatCalories($0.estimatedCaloriesKcal) } ?? "无 kcal",
                        systemImage: "fork.knife"
                    )
                }
            }
    }

    private func localizedPacketStatus(_ status: HealthPacketStatus) -> String {
        switch status {
        case .pendingIOSSync:
            return "待写入"
        case .writtenToHealthKit:
            return "已写入"
        case .failed:
            return "失败"
        case .cancelled:
            return "已取消"
        }
    }

    private func makeWorkoutRows(from workouts: [HealthWorkout]) -> [RecentWorkoutRow] {
        workouts
            .sorted { $0.startDate > $1.startDate }
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
        if value < 1 {
            return "0 kcal"
        }

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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
