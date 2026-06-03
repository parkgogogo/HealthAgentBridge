import Foundation
import HealthKit
import UIKit

enum HealthReporterError: LocalizedError {
    case healthDataUnavailable
    case unsupportedType(String)
    case invalidPacket(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "这台设备不支持 HealthKit"
        case .unsupportedType(let type):
            return "不支持的健康数据类型：\(type)"
        case .invalidPacket(let message):
            return "Health Packet 无效：\(message)"
        }
    }
}

final class HealthReporterService {
    static let shared = HealthReporterService()

    private let healthStore = HKHealthStore()
    private let bridgeClient = BridgeClient()
    private let uploadQueue = HealthReportUploadQueue()
    private let defaults = UserDefaults.standard
    private let enabledKey = "healthReporting.enabled"
    private let lastSyncKey = "healthReporting.lastSuccessfulSyncDate"
    private let lastSyncEndpointKey = "healthReporting.lastSuccessfulEndpoint"
    private let lastUploadErrorKey = "healthReporting.lastUploadError"
    private let queryQueue = DispatchQueue(label: "HealthReporter.HealthKit")
    private var observerQueries: [HKObserverQuery] = []

    var isReportingEnabled: Bool {
        defaults.bool(forKey: enabledKey)
    }

    var lastSuccessfulSyncDate: Date? {
        defaults.object(forKey: lastSyncKey) as? Date
    }

    var lastSuccessfulEndpoint: String? {
        defaults.string(forKey: lastSyncEndpointKey)
    }

    var lastUploadError: String? {
        defaults.string(forKey: lastUploadErrorKey)
    }

    private init() {}

    func resumeIfNeeded() async {
        guard isReportingEnabled else { return }
        do {
            try await startReporting()
            try await syncRecentHealthData(reason: "resume")
        } catch {
            NSLog("HealthReporter resume failed: \(error.localizedDescription)")
        }
    }

    func setReportingEnabled(_ enabled: Bool) async throws {
        if enabled {
            try await startReporting()
            defaults.set(true, forKey: enabledKey)
            do {
                try await syncRecentHealthData(reason: "enabled")
            } catch {
                NSLog("HealthReporter initial sync failed: \(error.localizedDescription)")
            }
        } else {
            stopReporting()
            defaults.set(false, forKey: enabledKey)
            defaults.removeObject(forKey: lastUploadErrorKey)
        }
    }

    func pendingReportCount() async -> Int {
        await uploadQueue.count()
    }

    func recentWorkoutsForDisplay(days: Int, limit: Int) async throws -> [HealthWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthReporterError.healthDataUnavailable
        }

        return try await collectRecentWorkouts(days: days, limit: limit)
    }

    private func startReporting() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthReporterError.healthDataUnavailable
        }

        let types = try monitoredSampleTypes()
        try await requestAuthorization(
            shareTypes: Set(try writableSampleTypes()),
            readTypes: Set(types.map { $0 as HKObjectType })
        )
        try await enableBackgroundDelivery(for: types)
        startObserverQueries(for: types)
    }

    private func stopReporting() {
        observerQueries.forEach { healthStore.stop($0) }
        observerQueries.removeAll()

        for type in (try? monitoredSampleTypes()) ?? [] {
            healthStore.disableBackgroundDelivery(for: type) { _, _ in }
        }
    }

    private func requestAuthorization(shareTypes: Set<HKSampleType>, readTypes: Set<HKObjectType>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthReporterError.healthDataUnavailable)
                }
            }
        }
    }

    private func enableBackgroundDelivery(for types: [HKSampleType]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for type in types {
                group.addTask { [healthStore] in
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { success, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else if success {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: HealthReporterError.healthDataUnavailable)
                            }
                        }
                    }
                }
            }

            try await group.waitForAll()
        }
    }

    private func startObserverQueries(for types: [HKSampleType]) {
        guard observerQueries.isEmpty else { return }

        observerQueries = types.map { type in
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                if let error {
                    NSLog("HealthKit observer error: \(error.localizedDescription)")
                    completionHandler()
                    return
                }

                Task {
                    do {
                        try await self?.syncRecentHealthData(reason: "observer")
                    } catch {
                        NSLog("HealthKit background sync failed: \(error.localizedDescription)")
                    }
                    completionHandler()
                }
            }
            healthStore.execute(query)
            return query
        }
    }

    private func syncRecentHealthData(reason: String) async throws {
        let report = try await collectReport(reason: reason)
        do {
            try await flushQueuedReports()
            let result = try await bridgeClient.upload(report)
            markSuccessfulUpload(result)
            await syncPendingPacketsAndUploadRefresh()
        } catch {
            try? await uploadQueue.enqueue(report)
            recordUploadFailure(error)
            throw error
        }
    }

    private func flushQueuedReports() async throws {
        while let report = try await uploadQueue.firstReport() {
            let result = try await bridgeClient.upload(report)
            markSuccessfulUpload(result)
            try await uploadQueue.removeFirstReport()
        }
    }

    private func markSuccessfulUpload(_ result: BridgeUploadResult) {
        defaults.set(Date(), forKey: lastSyncKey)
        defaults.set(result.endpointDescription, forKey: lastSyncEndpointKey)
        defaults.removeObject(forKey: lastUploadErrorKey)
    }

    private func syncPendingPacketsAndUploadRefresh() async {
        do {
            let writtenCount = try await syncPendingHealthPackets()
            guard writtenCount > 0 else { return }
            let refreshedReport = try await collectReport(reason: "packet-sync")
            let result = try await bridgeClient.upload(refreshedReport)
            markSuccessfulUpload(result)
        } catch {
            NSLog("HealthReporter packet sync failed: \(error.localizedDescription)")
        }
    }

    private func syncPendingHealthPackets() async throws -> Int {
        let packets = try await bridgeClient.fetchPendingPackets(limit: 50)
        guard !packets.isEmpty else {
            return 0
        }

        try await requestAuthorization(
            shareTypes: Set(try writableSampleTypes()),
            readTypes: Set(try monitoredSampleTypes().map { $0 as HKObjectType })
        )

        var writtenCount = 0
        for packet in packets {
            do {
                let healthKitObjectIds = try await writePacketToHealthKit(packet)
                _ = try await bridgeClient.acknowledgePacket(
                    packetId: packet.packetId,
                    request: HealthPacketAcknowledgeRequest(
                        status: .writtenToHealthKit,
                        healthKitObjectIds: healthKitObjectIds,
                        errorMessage: nil
                    )
                )
                writtenCount += 1
            } catch {
                _ = try? await bridgeClient.acknowledgePacket(
                    packetId: packet.packetId,
                    request: HealthPacketAcknowledgeRequest(
                        status: .failed,
                        healthKitObjectIds: nil,
                        errorMessage: error.localizedDescription
                    )
                )
            }
        }

        return writtenCount
    }

    private func recordUploadFailure(_ error: Error) {
        defaults.set(error.localizedDescription, forKey: lastUploadErrorKey)
    }

    private func collectReport(reason: String) async throws -> HealthReportEnvelope {
        async let summaries = collectDailySummaries(days: 14)
        async let samples = collectRecentSamples(hours: 24)
        async let workouts = collectRecentWorkouts(days: 30, limit: 100)

        return try await HealthReportEnvelope(
            schemaVersion: HealthBridgeConstants.schemaVersion,
            deviceName: UIDevice.current.name,
            generatedAt: Date(),
            reason: reason,
            dailySummaries: summaries,
            samples: samples,
            workouts: workouts
        )
    }

    private func monitoredSampleTypes() throws -> [HKSampleType] {
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .activeEnergyBurned,
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .distanceWalkingRunning,
            .appleExerciseTime,
            .heartRate,
            .restingHeartRate,
            .bodyMass
        ]

        var types: [HKSampleType] = try quantityIdentifiers.map { identifier in
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
                throw HealthReporterError.unsupportedType(identifier.rawValue)
            }
            return type
        }

        guard let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthReporterError.unsupportedType(HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
        }
        types.append(sleep)
        types.append(HKObjectType.workoutType())
        return types
    }

    private func writableSampleTypes() throws -> [HKQuantityType] {
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal
        ]

        return try quantityIdentifiers.map { identifier in
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
                throw HealthReporterError.unsupportedType(identifier.rawValue)
            }
            return type
        }
    }

    private func collectDailySummaries(days: Int) async throws -> [DailyHealthSummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let endDate = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }

        var summariesByDay: [Date: DailyHealthSummary] = [:]
        for dayOffset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            summariesByDay[day] = DailyHealthSummary(date: DateFormatter.healthBridgeDay.string(from: day))
        }

        let quantitySpecs: [(HKQuantityTypeIdentifier, HKUnit, HKStatisticsOptions)] = [
            (.stepCount, .count(), .cumulativeSum),
            (.activeEnergyBurned, .kilocalorie(), .cumulativeSum),
            (.dietaryEnergyConsumed, .kilocalorie(), .cumulativeSum),
            (.dietaryProtein, .gram(), .cumulativeSum),
            (.dietaryCarbohydrates, .gram(), .cumulativeSum),
            (.dietaryFatTotal, .gram(), .cumulativeSum),
            (.distanceWalkingRunning, .meter(), .cumulativeSum),
            (.appleExerciseTime, .minute(), .cumulativeSum),
            (.heartRate, HKUnit.count().unitDivided(by: .minute()), .discreteAverage),
            (.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), .discreteAverage),
            (.bodyMass, .gramUnit(with: .kilo), .discreteAverage)
        ]

        for spec in quantitySpecs {
            let values = try await statisticsByDay(
                identifier: spec.0,
                unit: spec.1,
                options: spec.2,
                startDate: startDate,
                endDate: endDate
            )

            for (day, value) in values {
                var summary = summariesByDay[day] ?? DailyHealthSummary(date: DateFormatter.healthBridgeDay.string(from: day))
                switch spec.0 {
                case .stepCount:
                    summary.stepCount = value
                case .activeEnergyBurned:
                    summary.activeEnergyKilocalories = value
                case .dietaryEnergyConsumed:
                    summary.dietaryEnergyKilocalories = value
                case .dietaryProtein:
                    summary.dietaryProteinGrams = value
                case .dietaryCarbohydrates:
                    summary.dietaryCarbohydratesGrams = value
                case .dietaryFatTotal:
                    summary.dietaryFatGrams = value
                case .distanceWalkingRunning:
                    summary.walkingRunningDistanceMeters = value
                case .appleExerciseTime:
                    summary.exerciseMinutes = value
                case .heartRate:
                    summary.heartRateAverageBPM = value
                case .restingHeartRate:
                    summary.restingHeartRateAverageBPM = value
                case .bodyMass:
                    summary.bodyMassKilograms = value
                default:
                    break
                }
                summariesByDay[day] = summary
            }
        }

        let sleepValues = try await sleepMinutesByDay(startDate: startDate, endDate: endDate)
        for (day, minutes) in sleepValues {
            var summary = summariesByDay[day] ?? DailyHealthSummary(date: DateFormatter.healthBridgeDay.string(from: day))
            summary.sleepAsleepMinutes = minutes
            summariesByDay[day] = summary
        }

        return summariesByDay
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    private func statisticsByDay(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        startDate: Date,
        endDate: Date
    ) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthReporterError.unsupportedType(identifier.rawValue)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: startDate,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var values: [Date: Double] = [:]
                collection?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    let quantity = options.contains(.cumulativeSum)
                        ? statistics.sumQuantity()
                        : statistics.averageQuantity()
                    guard let quantity else { return }
                    values[Calendar.current.startOfDay(for: statistics.startDate)] = quantity.doubleValue(for: unit)
                }

                continuation.resume(returning: values)
            }

            healthStore.execute(query)
        }
    }

    private func sleepMinutesByDay(startDate: Date, endDate: Date) async throws -> [Date: Double] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthReporterError.unsupportedType(HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
        }

        let samples: [HKCategorySample] = try await sampleQuery(sampleType: type, startDate: startDate, endDate: endDate, limit: HKObjectQueryNoLimit)
        let calendar = Calendar.current
        var minutesByDay: [Date: Double] = [:]

        for sample in samples where isAsleepSleepValue(sample.value) {
            var cursor = max(sample.startDate, startDate)
            let clampedEnd = min(sample.endDate, endDate)

            while cursor < clampedEnd {
                let day = calendar.startOfDay(for: cursor)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let segmentEnd = min(nextDay, clampedEnd)
                minutesByDay[day, default: 0] += segmentEnd.timeIntervalSince(cursor) / 60
                cursor = segmentEnd
            }
        }

        return minutesByDay
    }

    private func collectRecentSamples(hours: Int) async throws -> [HealthSample] {
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .hour, value: -hours, to: endDate) else {
            return []
        }

        let specs: [(String, HKQuantityTypeIdentifier, HKUnit, String)] = [
            ("heartRate", .heartRate, HKUnit.count().unitDivided(by: .minute()), "count/min"),
            ("restingHeartRate", .restingHeartRate, HKUnit.count().unitDivided(by: .minute()), "count/min"),
            ("bodyMass", .bodyMass, .gramUnit(with: .kilo), "kg"),
            ("dietaryEnergyConsumed", .dietaryEnergyConsumed, .kilocalorie(), "kcal"),
            ("dietaryProtein", .dietaryProtein, .gram(), "g"),
            ("dietaryCarbohydrates", .dietaryCarbohydrates, .gram(), "g"),
            ("dietaryFatTotal", .dietaryFatTotal, .gram(), "g")
        ]

        var output: [HealthSample] = []
        for spec in specs {
            guard let type = HKObjectType.quantityType(forIdentifier: spec.1) else { continue }
            let samples: [HKQuantitySample] = try await sampleQuery(sampleType: type, startDate: startDate, endDate: endDate, limit: 200)
            output.append(contentsOf: samples.map { sample in
                HealthSample(
                    id: UUID(),
                    type: spec.0,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    value: sample.quantity.doubleValue(for: spec.2),
                    unit: spec.3,
                    sourceName: sample.sourceRevision.source.name
                )
            })
        }

        return output.sorted { $0.startDate < $1.startDate }
    }

    private func collectRecentWorkouts(days: Int, limit: Int) async throws -> [HealthWorkout] {
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else {
            return []
        }

        let workoutType = HKObjectType.workoutType()
        let workouts: [HKWorkout] = try await sampleQuery(
            sampleType: workoutType,
            startDate: startDate,
            endDate: endDate,
            limit: limit
        )

        return workouts.map { workout in
            HealthWorkout(
                id: UUID(),
                activityType: workout.workoutActivityType.rawValue,
                activityName: workoutActivityName(workout.workoutActivityType),
                startDate: workout.startDate,
                endDate: workout.endDate,
                durationSeconds: workout.duration,
                totalEnergyBurnedKilocalories: workoutSum(
                    workout,
                    identifier: .activeEnergyBurned,
                    unit: .kilocalorie()
                ),
                totalDistanceMeters: workoutSum(
                    workout,
                    identifier: .distanceWalkingRunning,
                    unit: .meter()
                ),
                sourceName: workout.sourceRevision.source.name
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private func sampleQuery<T: HKSample>(
        sampleType: HKSampleType,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [T]) ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func isAsleepSleepValue(_ value: Int) -> Bool {
        value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            || value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
            || value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            || value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
    }

    private func workoutSum(_ workout: HKWorkout, identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        return workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: unit)
    }

    private func writePacketToHealthKit(_ packet: HealthPacket) async throws -> [String] {
        switch packet.type {
        case .bodyWeight:
            return try await writeBodyWeightPacket(packet)
        case .foodIntake:
            return try await writeFoodIntakePacket(packet)
        }
    }

    private func writeBodyWeightPacket(_ packet: HealthPacket) async throws -> [String] {
        guard let payload = packet.bodyWeight else {
            throw HealthReporterError.invalidPacket("bodyWeight payload is missing")
        }
        guard payload.weightKilograms > 0 else {
            throw HealthReporterError.invalidPacket("bodyWeight.weightKilograms must be positive")
        }
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthReporterError.unsupportedType(HKQuantityTypeIdentifier.bodyMass.rawValue)
        }

        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: payload.weightKilograms),
            start: payload.measuredAt,
            end: payload.measuredAt,
            metadata: healthPacketMetadata(packet, label: payload.rawText ?? payload.note)
        )

        try await saveHealthObjects([sample])
        return [sample.uuid.uuidString]
    }

    private func writeFoodIntakePacket(_ packet: HealthPacket) async throws -> [String] {
        guard let payload = packet.foodIntake else {
            throw HealthReporterError.invalidPacket("foodIntake payload is missing")
        }
        guard payload.estimatedCaloriesKcal > 0 else {
            throw HealthReporterError.invalidPacket("foodIntake.estimatedCaloriesKcal must be positive")
        }

        var samples: [HKQuantitySample] = []
        let metadata = healthPacketMetadata(packet, label: payload.rawText, mealType: payload.mealType)

        try appendQuantitySample(
            to: &samples,
            identifier: .dietaryEnergyConsumed,
            unit: .kilocalorie(),
            value: payload.estimatedCaloriesKcal,
            date: payload.occurredAt,
            metadata: metadata
        )
        try appendQuantitySample(
            to: &samples,
            identifier: .dietaryProtein,
            unit: .gram(),
            value: payload.proteinGrams,
            date: payload.occurredAt,
            metadata: metadata
        )
        try appendQuantitySample(
            to: &samples,
            identifier: .dietaryCarbohydrates,
            unit: .gram(),
            value: payload.carbohydrateGrams,
            date: payload.occurredAt,
            metadata: metadata
        )
        try appendQuantitySample(
            to: &samples,
            identifier: .dietaryFatTotal,
            unit: .gram(),
            value: payload.fatGrams,
            date: payload.occurredAt,
            metadata: metadata
        )

        guard !samples.isEmpty else {
            throw HealthReporterError.invalidPacket("foodIntake has no writable nutrition samples")
        }

        try await saveHealthObjects(samples)
        return samples.map { $0.uuid.uuidString }
    }

    private func appendQuantitySample(
        to samples: inout [HKQuantitySample],
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        value: Double?,
        date: Date,
        metadata: [String: Any]
    ) throws {
        guard let value, value > 0 else {
            return
        }
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthReporterError.unsupportedType(identifier.rawValue)
        }

        samples.append(
            HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date,
                end: date,
                metadata: metadata
            )
        )
    }

    private func healthPacketMetadata(_ packet: HealthPacket, label: String?, mealType: String? = nil) -> [String: Any] {
        var metadata: [String: Any] = [
            "DataTrackerPacketId": packet.packetId,
            "DataTrackerPacketType": packet.type.rawValue,
            "DataTrackerPacketRevision": packet.revision,
            "DataTrackerPacketSource": packet.source.rawValue,
            HKMetadataKeyWasUserEntered: true
        ]

        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["DataTrackerRawText"] = label
            metadata[HKMetadataKeyFoodType] = label
        }
        if let mealType, !mealType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["DataTrackerMealType"] = mealType
        }

        return metadata
    }

    private func saveHealthObjects(_ objects: [HKObject]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(objects) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthReporterError.healthDataUnavailable)
                }
            }
        }
    }

    private func workoutActivityName(_ activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running:
            return "running"
        case .walking:
            return "walking"
        case .cycling:
            return "cycling"
        case .hiking:
            return "hiking"
        case .swimming:
            return "swimming"
        case .yoga:
            return "yoga"
        case .traditionalStrengthTraining:
            return "traditionalStrengthTraining"
        case .functionalStrengthTraining:
            return "functionalStrengthTraining"
        case .highIntensityIntervalTraining:
            return "highIntensityIntervalTraining"
        case .coreTraining:
            return "coreTraining"
        case .elliptical:
            return "elliptical"
        case .rowing:
            return "rowing"
        case .stairClimbing:
            return "stairClimbing"
        case .mindAndBody:
            return "mindAndBody"
        case .other:
            return "other"
        default:
            return "activityType-\(activityType.rawValue)"
        }
    }
}

private actor HealthReportUploadQueue {
    private let fileURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthAgentBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        self.fileURL = baseURL.appendingPathComponent("queued-reports.json")
    }

    func count() -> Int {
        (try? loadReports().count) ?? 0
    }

    func firstReport() throws -> HealthReportEnvelope? {
        try loadReports().first
    }

    func enqueue(_ report: HealthReportEnvelope) throws {
        var reports = try loadReports()
        reports.append(report)
        try save(reports)
    }

    func removeFirstReport() throws {
        var reports = try loadReports()
        guard !reports.isEmpty else { return }
        reports.removeFirst()
        try save(reports)
    }

    private func loadReports() throws -> [HealthReportEnvelope] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONCoding.decoder.decode([HealthReportEnvelope].self, from: data)
    }

    private func save(_ reports: [HealthReportEnvelope]) throws {
        if reports.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let data = try JSONCoding.encoder.encode(reports)
        try data.write(to: fileURL, options: [.atomic])
    }
}
