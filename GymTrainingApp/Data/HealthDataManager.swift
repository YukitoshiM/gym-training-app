import Foundation
@preconcurrency import HealthKit
@preconcurrency import CoreLocation

@MainActor
final class HealthDataManager: ObservableObject {
    @Published private(set) var accessState: HealthAccessState
    @Published private(set) var snapshot = DailyHealthSnapshot.empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var recoveryHistory: [DailyRecoveryTrendRecord] = []

    private let healthStore = HKHealthStore()
    private let requestedKey = "gym.training.health.authorizationRequested"
    private let recoveryHistoryKey = "gym.training.health.recoveryHistory"
    private let isUITestMode: Bool

    init() {
        isUITestMode = ProcessInfo.processInfo.arguments.contains("--seed-sensor-ui-test-data")

        if isUITestMode {
            accessState = .ready
            snapshot = Self.uiTestSnapshot
            recoveryHistory = Self.uiTestRecoveryHistory
        } else if !HKHealthStore.isHealthDataAvailable() {
            accessState = .unavailable
        } else if UserDefaults.standard.bool(forKey: requestedKey) {
            accessState = .ready
        } else {
            accessState = .notRequested
        }


        if !isUITestMode,
           let data = UserDefaults.standard.data(forKey: recoveryHistoryKey),
           let stored = try? JSONDecoder().decode([DailyRecoveryTrendRecord].self, from: data) {
            recoveryHistory = stored
        }
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable(), !isUITestMode else { return }

        accessState = .requesting

        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            UserDefaults.standard.set(true, forKey: requestedKey)
            accessState = .ready
            await refresh()
        } catch {
            accessState = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable(), !isUITestMode else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let baselineStart = calendar.date(byAdding: .day, value: -14, to: now) ?? startOfDay

        async let steps = cumulativeValue(.stepCount, unit: .count(), start: startOfDay, end: now)
        async let energy = cumulativeValue(.activeEnergyBurned, unit: .kilocalorie(), start: startOfDay, end: now)
        async let restingEnergy = cumulativeValue(.basalEnergyBurned, unit: .kilocalorie(), start: startOfDay, end: now)
        async let distance = cumulativeValue(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), start: startOfDay, end: now)
        async let flights = cumulativeValue(.flightsClimbed, unit: .count(), start: startOfDay, end: now)
        async let sleep = sleepSummary(end: now)
        async let restingHeartRate = latestValue(.restingHeartRate, unit: beatsPerMinute)
        async let hrv = latestValue(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let respiratoryRate = latestValue(.respiratoryRate, unit: breathsPerMinute)
        async let wristTemperature = latestValue(.appleSleepingWristTemperature, unit: .degreeCelsius())
        async let audioExposure = latestValue(.environmentalAudioExposure, unit: .decibelAWeightedSoundPressureLevel())
        async let heartRecovery = latestValue(.heartRateRecoveryOneMinute, unit: beatsPerMinute)
        async let activity = todayActivityProgress(now: now)
        async let restingBaseline = averageValue(.restingHeartRate, unit: beatsPerMinute, start: baselineStart, end: now)
        async let hrvBaseline = averageValue(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: baselineStart, end: now)
        async let temperatureBaseline = averageValue(.appleSleepingWristTemperature, unit: .degreeCelsius(), start: baselineStart, end: now)
        async let respiratoryBaseline = averageValue(.respiratoryRate, unit: breathsPerMinute, start: baselineStart, end: now)
        async let outdoorRoute = latestOutdoorRunningRoute()

        snapshot = await DailyHealthSnapshot(
            generatedAt: now,
            steps: steps,
            activeEnergyKilocalories: energy,
            restingEnergyKilocalories: restingEnergy,
            walkingRunningDistanceKilometers: distance,
            flightsClimbed: flights,
            sleepHours: sleep?.totalHours,
            sleepSummary: sleep,
            restingHeartRate: restingHeartRate,
            heartRateVariabilityMilliseconds: hrv,
            respiratoryRate: respiratoryRate,
            wristTemperatureCelsius: wristTemperature,
            environmentalAudioExposureDecibels: audioExposure,
            heartRateRecovery: heartRecovery,
            activityProgress: activity,
            baselines: RecoveryBaselines(
                restingHeartRate: restingBaseline,
                heartRateVariabilityMilliseconds: hrvBaseline,
                wristTemperatureCelsius: temperatureBaseline,
                respiratoryRate: respiratoryBaseline
            ),
            latestOutdoorRoute: outdoorRoute
        )
        persistRecoveryTrend(from: snapshot)
    }

    func readinessAssessment(
        recentWorkouts: [WorkoutSession],
        subjectiveRecovery: SubjectiveRecoveryEntry? = nil
    ) -> ReadinessAssessment {
        var score = 70
        var factors: [String] = []
        var availableCount = 0

        if let sleepHours = snapshot.sleepHours {
            availableCount += 1
            if sleepHours >= 7 {
                score += 10
                factors.append("睡眠 \(sleepHours.formatted(.number.precision(.fractionLength(1))))時間を確保")
            } else if sleepHours < 6 {
                score -= 15
                factors.append("睡眠が短め")
            } else {
                factors.append("睡眠はやや短め")
            }
        }

        if let current = snapshot.restingHeartRate?.value,
           let baseline = snapshot.baselines.restingHeartRate,
           baseline > 0 {
            availableCount += 1
            let delta = current - baseline
            if delta >= 7 {
                score -= 12
                factors.append("安静時心拍が14日平均より高め")
            } else if delta <= -3 {
                score += 5
                factors.append("安静時心拍は平均より低め")
            } else {
                factors.append("安静時心拍は普段どおり")
            }
        }

        if let current = snapshot.heartRateVariabilityMilliseconds?.value,
           let baseline = snapshot.baselines.heartRateVariabilityMilliseconds,
           baseline > 0 {
            availableCount += 1
            let ratio = current / baseline
            if ratio < 0.75 {
                score -= 12
                factors.append("HRVが14日平均より低め")
            } else if ratio > 1.1 {
                score += 7
                factors.append("HRVは平均より高め")
            } else {
                factors.append("HRVは普段の範囲")
            }
        }

        if let current = snapshot.wristTemperatureCelsius?.value,
           let baseline = snapshot.baselines.wristTemperatureCelsius {
            availableCount += 1
            let delta = abs(current - baseline)
            if delta >= 0.7 {
                score -= 8
                factors.append("手首皮膚温が普段と異なる傾向")
            } else {
                factors.append("手首皮膚温は普段の範囲")
            }
        }

        if let current = snapshot.respiratoryRate?.value,
           let baseline = snapshot.baselines.respiratoryRate,
           baseline > 0 {
            availableCount += 1
            let ratio = current / baseline
            if ratio >= 1.12 {
                score -= 8
                factors.append("呼吸数が14日平均より高め")
            } else if ratio <= 0.9 {
                score += 3
                factors.append("呼吸数は14日平均より低め")
            } else {
                factors.append("呼吸数は普段の範囲")
            }
        }

        let fortyEightHoursAgo = Date().addingTimeInterval(-48 * 60 * 60)
        let recentCount = recentWorkouts.filter { $0.startedAt >= fortyEightHoursAgo }.count
        if !recentWorkouts.isEmpty {
            availableCount += 1
            if recentCount >= 3 {
                score -= 8
                factors.append("48時間のトレーニング回数が多め")
            } else {
                factors.append("直近のトレーニング量は通常範囲")
            }
        }


        if let steps = snapshot.steps {
            availableCount += 1
            if steps >= 18_000 {
                score -= 5
                factors.append("今日の活動量が多め")
            } else {
                factors.append("今日の活動量を反映")
            }
        }

        if let subjectiveRecovery,
           Calendar.current.isDateInToday(subjectiveRecovery.recordedAt) {
            availableCount += 1
            switch subjectiveRecovery.fatigueLevel {
            case 4...5:
                score -= subjectiveRecovery.fatigueLevel == 5 ? 15 : 9
                factors.append("主観疲労が高め")
            case 1:
                score += 6
                factors.append("主観疲労は低め")
            default:
                factors.append("主観疲労は通常範囲")
            }
        }

        guard availableCount > 0 else {
            return ReadinessAssessment(
                score: nil,
                level: .moderate,
                summary: "データがそろうと、睡眠・回復・運動量をまとめて確認できます。",
                factors: ["未取得の項目は0として扱いません"],
                availableFactorCount: 0
            )
        }

        score = min(100, max(0, score))
        let level: ReadinessAssessment.Level = score >= 80 ? .good : (score >= 55 ? .moderate : .recover)
        let summary: String = switch level {
        case .good: "通常どおり取り組めそうです。ウォームアップ中の感覚も確認しましょう。"
        case .moderate: "普段どおりを目安に、RPEを見ながら調整しましょう。"
        case .recover: "今日は重量やセット数を抑え、回復を優先する選択肢があります。"
        }

        return ReadinessAssessment(
            score: score,
            level: level,
            summary: summary,
            factors: factors,
            availableFactorCount: availableCount
        )
    }

    func saveBodyMetricIfAuthorized(_ entry: BodyMetricEntry) async {
        let identifier: HKQuantityTypeIdentifier
        let quantity: HKQuantity

        switch entry.kind {
        case .bodyWeight:
            identifier = .bodyMass
            quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: entry.value)
        case .waist:
            identifier = .waistCircumference
            quantity = HKQuantity(unit: .meter(), doubleValue: entry.value / 100)
        case .bodyFatPercentage:
            identifier = .bodyFatPercentage
            quantity = HKQuantity(unit: .percent(), doubleValue: entry.value / 100)
        }

        guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
              healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
            return
        }

        let sample = HKQuantitySample(
            type: type,
            quantity: quantity,
            start: entry.recordedAt,
            end: entry.recordedAt
        )

        do {
            try await healthStore.save(sample)
        } catch {
            NSLog("Body metric Health save failed: \(error.localizedDescription)")
        }
    }

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(bodyMass)
        }
        if let waist = HKQuantityType.quantityType(forIdentifier: .waistCircumference) {
            types.insert(waist)
        }
        if let bodyFat = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            types.insert(bodyFat)
        }
        return types
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.activitySummaryType(),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKSeriesType.workoutRoute()
        ]

        for identifier in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    private var quantityIdentifiers: [HKQuantityTypeIdentifier] {
        [
            .stepCount,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .distanceWalkingRunning,
            .flightsClimbed,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .respiratoryRate,
            .appleSleepingWristTemperature,
            .environmentalAudioExposure,
            .heartRateRecoveryOneMinute,
            .bodyMass,
            .waistCircumference,
            .bodyFatPercentage
        ]
    }

    private var beatsPerMinute: HKUnit {
        HKUnit.count().unitDivided(by: .minute())
    }

    private var breathsPerMinute: HKUnit {
        HKUnit.count().unitDivided(by: .minute())
    }

    private func cumulativeValue(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func averageValue(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func latestValue(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> HealthMetricValue? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        let predicate = start.map { HKQuery.predicateForSamples(withStart: $0, end: Date()) }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: HealthMetricValue(
                        value: sample.quantity.doubleValue(for: unit),
                        recordedAt: sample.endDate
                    )
                )
            }
            healthStore.execute(query)
        }
    }

    private func sleepSummary(end: Date) async -> SleepSummary? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let start = Calendar.current.date(byAdding: .hour, value: -36, to: end) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sleepingValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let grouped = Dictionary(grouping: samples) {
                    $0.sourceRevision.source.bundleIdentifier
                }
                let selected = grouped.values.max { lhs, rhs in
                    let lhsDetailed = lhs.filter {
                        [
                            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                            HKCategoryValueSleepAnalysis.asleepREM.rawValue
                        ].contains($0.value)
                    }.count
                    let rhsDetailed = rhs.filter {
                        [
                            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                            HKCategoryValueSleepAnalysis.asleepREM.rawValue
                        ].contains($0.value)
                    }.count
                    if lhsDetailed != rhsDetailed { return lhsDetailed < rhsDetailed }
                    return lhs.count < rhs.count
                } ?? []

                func hours(for values: Set<Int>) -> Double {
                    selected
                        .filter { values.contains($0.value) }
                        .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3_600
                }

                let total = hours(for: sleepingValues)
                guard total > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let core = hours(for: [HKCategoryValueSleepAnalysis.asleepCore.rawValue])
                let deep = hours(for: [HKCategoryValueSleepAnalysis.asleepDeep.rawValue])
                let rem = hours(for: [HKCategoryValueSleepAnalysis.asleepREM.rawValue])
                let awakeSamples = selected.filter {
                    $0.value == HKCategoryValueSleepAnalysis.awake.rawValue
                        && $0.endDate.timeIntervalSince($0.startDate) >= 60
                }
                let awake = awakeSamples.reduce(0) {
                    $0 + $1.endDate.timeIntervalSince($1.startDate)
                } / 3_600
                let hasStages = core + deep + rem > 0
                let quality = Self.sleepQualityScore(
                    totalHours: total,
                    deepHours: hasStages ? deep : nil,
                    remHours: hasStages ? rem : nil,
                    interruptionCount: awakeSamples.count
                )

                continuation.resume(
                    returning: SleepSummary(
                        totalHours: total,
                        coreHours: hasStages ? core : nil,
                        deepHours: hasStages ? deep : nil,
                        remHours: hasStages ? rem : nil,
                        awakeHours: awake > 0 ? awake : nil,
                        interruptionCount: awakeSamples.isEmpty ? 0 : awakeSamples.count,
                        qualityScore: quality,
                        hasDetailedStages: hasStages
                    )
                )
            }
            healthStore.execute(query)
        }
    }

    nonisolated private static func sleepQualityScore(
        totalHours: Double,
        deepHours: Double?,
        remHours: Double?,
        interruptionCount: Int
    ) -> Int {
        var score = min(55, max(0, totalHours / 7.5 * 55))
        if let deepHours, totalHours > 0 {
            let ratio = deepHours / totalHours
            score += max(0, 22 - abs(ratio - 0.2) * 110)
        }
        if let remHours, totalHours > 0 {
            let ratio = remHours / totalHours
            score += max(0, 23 - abs(ratio - 0.25) * 92)
        }
        score -= min(15, Double(interruptionCount) * 3)
        return Int(min(100, max(0, score)).rounded())
    }

    private func persistRecoveryTrend(from snapshot: DailyHealthSnapshot) {
        let day = Calendar.current.startOfDay(for: snapshot.generatedAt)
        let restingDelta: Double? = {
            guard let current = snapshot.restingHeartRate?.value,
                  let baseline = snapshot.baselines.restingHeartRate else { return nil }
            return current - baseline
        }()
        let hrvRatio: Double? = {
            guard let current = snapshot.heartRateVariabilityMilliseconds?.value,
                  let baseline = snapshot.baselines.heartRateVariabilityMilliseconds,
                  baseline > 0 else { return nil }
            return current / baseline
        }()
        let record = DailyRecoveryTrendRecord(
            date: day,
            sleepHours: snapshot.sleepHours,
            restingHeartRateDelta: restingDelta,
            hrvRatio: hrvRatio,
            activeEnergyKilocalories: snapshot.activeEnergyKilocalories
        )

        recoveryHistory.removeAll { Calendar.current.isDate($0.date, inSameDayAs: day) }
        recoveryHistory.append(record)
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: day) ?? .distantPast
        recoveryHistory = recoveryHistory
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
        if let data = try? JSONEncoder().encode(recoveryHistory) {
            UserDefaults.standard.set(data, forKey: recoveryHistoryKey)
        }
    }

    private func todayActivityProgress(now: Date) async -> ActivityProgress? {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.era, .year, .month, .day], from: now)
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: components, end: components)

        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let summary = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: ActivityProgress(
                        moveKilocalories: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                        moveGoalKilocalories: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                        exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
                        exerciseGoalMinutes: summary.appleExerciseTimeGoal.doubleValue(for: .minute()),
                        standHours: summary.appleStandHours.doubleValue(for: .count()),
                        standGoalHours: summary.appleStandHoursGoal.doubleValue(for: .count())
                    )
                )
            }
            healthStore.execute(query)
        }
    }

    private func latestOutdoorRunningRoute() async -> OutdoorWorkoutRouteSummary? {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForWorkouts(with: .running)

        return await withCheckedContinuation { continuation in
            let workoutQuery = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { [weak healthStore] _, samples, _ in
                guard let healthStore,
                      let workout = samples?.first as? HKWorkout else {
                    continuation.resume(returning: nil)
                    return
                }

                let routeQuery = HKSampleQuery(
                    sampleType: HKSeriesType.workoutRoute(),
                    predicate: HKQuery.predicateForObjects(from: workout),
                    limit: 1,
                    sortDescriptors: nil
                ) { _, routes, _ in
                    guard let route = routes?.first as? HKWorkoutRoute else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let accumulator = RouteLocationAccumulator()
                    let pointsQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                        if let locations {
                            accumulator.locations.append(contentsOf: locations)
                        }
                        guard done || error != nil else { return }
                        guard error == nil, !accumulator.locations.isEmpty else {
                            continuation.resume(returning: nil)
                            return
                        }

                        let locations = accumulator.locations.sorted { $0.timestamp < $1.timestamp }
                        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
                        let distanceQuantity = distanceType.flatMap {
                            workout.statistics(for: $0)?.sumQuantity()
                        }
                        let distance = distanceQuantity?.doubleValue(for: .meterUnit(with: .kilo))
                        let speed = distance.map { $0 / max(workout.duration / 3_600, 0.01) }
                        let elevation = zip(locations.dropFirst(), locations).reduce(0.0) { total, pair in
                            total + max(0, pair.0.altitude - pair.1.altitude)
                        }

                        continuation.resume(
                            returning: OutdoorWorkoutRouteSummary(
                                workoutID: workout.uuid,
                                startedAt: workout.startDate,
                                durationSeconds: workout.duration,
                                distanceKilometers: distance,
                                averageSpeedKilometersPerHour: speed,
                                elevationGainMeters: elevation,
                                points: locations.map {
                                    OutdoorRoutePoint(
                                        latitude: $0.coordinate.latitude,
                                        longitude: $0.coordinate.longitude,
                                        altitudeMeters: $0.altitude,
                                        recordedAt: $0.timestamp
                                    )
                                }
                            )
                        )
                    }
                    healthStore.execute(pointsQuery)
                }
                healthStore.execute(routeQuery)
            }
            healthStore.execute(workoutQuery)
        }
    }

    private static let uiTestSnapshot = DailyHealthSnapshot(
        generatedAt: Date(),
        steps: 7_842,
        activeEnergyKilocalories: 486,
        restingEnergyKilocalories: 1_420,
        walkingRunningDistanceKilometers: 5.7,
        flightsClimbed: 6,
        sleepHours: 7.4,
        sleepSummary: SleepSummary(
            totalHours: 7.4,
            coreHours: 4.5,
            deepHours: 1.2,
            remHours: 1.7,
            awakeHours: 0.2,
            interruptionCount: 2,
            qualityScore: 86,
            hasDetailedStages: true
        ),
        restingHeartRate: HealthMetricValue(value: 58, recordedAt: Date()),
        heartRateVariabilityMilliseconds: HealthMetricValue(value: 49, recordedAt: Date()),
        respiratoryRate: HealthMetricValue(value: 14.8, recordedAt: Date()),
        wristTemperatureCelsius: HealthMetricValue(value: 35.8, recordedAt: Date()),
        environmentalAudioExposureDecibels: HealthMetricValue(value: 68, recordedAt: Date()),
        heartRateRecovery: HealthMetricValue(value: 31, recordedAt: Date()),
        activityProgress: ActivityProgress(
            moveKilocalories: 486,
            moveGoalKilocalories: 600,
            exerciseMinutes: 38,
            exerciseGoalMinutes: 30,
            standHours: 9,
            standGoalHours: 12
        ),
        baselines: RecoveryBaselines(
            restingHeartRate: 59,
            heartRateVariabilityMilliseconds: 45,
            wristTemperatureCelsius: 35.7,
            respiratoryRate: 14.5
        ),
        latestOutdoorRoute: OutdoorWorkoutRouteSummary(
            workoutID: UUID(),
            startedAt: Date().addingTimeInterval(-86_400),
            durationSeconds: 1_920,
            distanceKilometers: 5.1,
            averageSpeedKilometersPerHour: 9.6,
            elevationGainMeters: 42,
            points: [
                OutdoorRoutePoint(latitude: 35.6812, longitude: 139.7671, altitudeMeters: 8, recordedAt: Date()),
                OutdoorRoutePoint(latitude: 35.6840, longitude: 139.7710, altitudeMeters: 16, recordedAt: Date()),
                OutdoorRoutePoint(latitude: 35.6880, longitude: 139.7750, altitudeMeters: 22, recordedAt: Date())
            ]
        )
    )

    private static let uiTestRecoveryHistory = makeUITestRecoveryHistory()

    private static func makeUITestRecoveryHistory() -> [DailyRecoveryTrendRecord] {
        let now = Date()
        var records: [DailyRecoveryTrendRecord] = []
        for offset in 0..<14 {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: now) ?? now
            records.append(
                DailyRecoveryTrendRecord(
                    date: date,
                    sleepHours: 6.8 + Double(offset % 3) * 0.3,
                    restingHeartRateDelta: Double(offset % 4) - 1,
                    hrvRatio: 0.9 + Double(offset % 3) * 0.08,
                    activeEnergyKilocalories: 420 + Double(offset % 4) * 45
                )
            )
        }
        return records
    }
}

private final class RouteLocationAccumulator: @unchecked Sendable {
    var locations: [CLLocation] = []
}
