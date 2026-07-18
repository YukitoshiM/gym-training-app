import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var userProfile: UserProfile = .default
    @Published private(set) var plans: [TrainingPlan] = []
    @Published private(set) var workoutHistory: [WorkoutSession] = []
    @Published private(set) var bodyMetricEntries: [BodyMetricEntry] = []
    @Published private(set) var bodyMetricGoals: [BodyMetricGoal] = []
    @Published private(set) var mealEntries: [MealEntry] = []
    @Published private(set) var bodyPhotoEntries: [BodyPhotoEntry] = []
    @Published private(set) var customExercises: [Exercise] = []
    @Published private(set) var aiSettings: AISettings = .default
    @Published private(set) var aiInsights: [AIInsight] = []
    @Published private(set) var sensorSettings: SensorSettings = .default
    @Published private(set) var dailyWorkoutSelection: DailyWorkoutSelection?
    @Published private(set) var gymLocation: GymLocation?
    @Published private(set) var gymVisits: [GymVisit] = []
    @Published private(set) var subjectiveRecoveryEntries: [SubjectiveRecoveryEntry] = []
    @Published private(set) var pendingMissedGymPlan: DailyWorkoutSelection?
    @Published private(set) var aiTransmissionHistory: [AITransmissionRecord] = []
    @Published private(set) var appearanceSettings: AppAppearanceSettings = .default

    private let storage = LocalJSONStorage()

    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-ui-test-data") {
            storage.reset()
        }

        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--seed-theme-black-champagne") {
            storage.saveAppearanceSettings(.init(colorTheme: .blackChampagne, mode: .system))
        } else if arguments.contains("--seed-theme-royal-cobalt") {
            storage.saveAppearanceSettings(.init(colorTheme: .royalCobalt, mode: .system))
        }
        if arguments.contains("--force-light-appearance") {
            var settings = storage.loadAppearanceSettings()
            settings.mode = .light
            storage.saveAppearanceSettings(settings)
        } else if arguments.contains("--force-dark-appearance") {
            var settings = storage.loadAppearanceSettings()
            settings.mode = .dark
            storage.saveAppearanceSettings(settings)
        }

        if arguments.contains("--seed-alpha-ui-test-plan") {
            storage.savePlans([Self.alphaUITestPlan()])
            storage.saveWorkoutHistory([])
            storage.saveBodyMetricEntries([])
            storage.saveBodyMetricGoals(Self.defaultBodyMetricGoals())
            storage.saveMealEntries([])
            storage.saveBodyPhotoEntries([])
            storage.saveCustomExercises([])
            storage.saveAISettings(arguments.contains("--seed-ai-unreachable-settings") ? Self.unreachableAISettings() : .default)
            storage.saveAIInsights([])
            storage.saveUserProfile(.default)
        }

        userProfile = storage.loadUserProfile()
        plans = storage.loadPlans()
        workoutHistory = storage.loadWorkoutHistory()
        bodyMetricEntries = storage.loadBodyMetricEntries()
        bodyMetricGoals = storage.loadBodyMetricGoals()
        mealEntries = storage.loadMealEntries()
        bodyPhotoEntries = storage.loadBodyPhotoEntries()
        customExercises = storage.loadCustomExercises()
        aiSettings = storage.loadAISettings()
        aiInsights = storage.loadAIInsights()
        sensorSettings = storage.loadSensorSettings()
        dailyWorkoutSelection = storage.loadDailyWorkoutSelection()
        gymLocation = storage.loadGymLocation()
        gymVisits = storage.loadGymVisits()
        subjectiveRecoveryEntries = storage.loadSubjectiveRecoveryEntries()
        aiTransmissionHistory = storage.loadAITransmissionHistory()
        appearanceSettings = storage.loadAppearanceSettings()

        if let selection = dailyWorkoutSelection,
           !Calendar.current.isDateInToday(selection.date) {
            let planStillExists = plans.contains(where: { $0.id == selection.planID })
            let visitedGym = !gymVisits(on: selection.date).isEmpty
            let completedWorkout = !workoutSessions(on: selection.date).isEmpty
            if planStillExists, !visitedGym, !completedWorkout {
                pendingMissedGymPlan = selection
            }
            dailyWorkoutSelection = nil
            storage.saveDailyWorkoutSelection(nil)
        } else if let selection = dailyWorkoutSelection,
                  !plans.contains(where: { $0.id == selection.planID }) {
            dailyWorkoutSelection = nil
            storage.saveDailyWorkoutSelection(nil)
        }

        if bodyMetricGoals.isEmpty {
            bodyMetricGoals = Self.defaultBodyMetricGoals()
            storage.saveBodyMetricGoals(bodyMetricGoals)
        }
    }

    func saveUserProfile(_ profile: UserProfile) {
        userProfile = profile
        storage.saveUserProfile(profile)
    }

    func saveAISettings(_ settings: AISettings) {
        aiSettings = settings
        storage.saveAISettings(settings)
    }

    func saveSensorSettings(_ settings: SensorSettings) {
        sensorSettings = settings
        storage.saveSensorSettings(settings)
    }

    func saveAppearanceSettings(_ settings: AppAppearanceSettings) {
        appearanceSettings = settings
        storage.saveAppearanceSettings(settings)
    }

    func selectTodayPlan(_ planID: UUID) {
        guard plans.contains(where: { $0.id == planID }) else { return }
        let selection = DailyWorkoutSelection(date: Date(), planID: planID)
        dailyWorkoutSelection = selection
        storage.saveDailyWorkoutSelection(selection)
    }

    var todayPlan: TrainingPlan? {
        if let selection = dailyWorkoutSelection,
           Calendar.current.isDateInToday(selection.date),
           let plan = plans.first(where: { $0.id == selection.planID }) {
            return plan
        }

        return plans.first
    }

    var pendingMissedGymPlanName: String? {
        guard let pendingMissedGymPlan else { return nil }
        return plans.first(where: { $0.id == pendingMissedGymPlan.planID })?.name
    }

    func resolveMissedGymPlan(rescheduleForToday: Bool) {
        let pending = pendingMissedGymPlan
        pendingMissedGymPlan = nil
        guard rescheduleForToday,
              let pending,
              plans.contains(where: { $0.id == pending.planID }) else {
            return
        }
        selectTodayPlan(pending.planID)
    }

    func saveGymLocation(_ location: GymLocation?) {
        gymLocation = location
        storage.saveGymLocation(location)
    }

    func recordGymArrival(source: String, at date: Date = Date()) {
        guard gymVisits.first?.departedAt != nil || gymVisits.isEmpty else { return }
        gymVisits.insert(GymVisit(arrivedAt: date, source: source), at: 0)
        storage.saveGymVisits(gymVisits)
    }

    func recordGymDeparture(at date: Date = Date()) {
        guard !gymVisits.isEmpty, gymVisits[0].departedAt == nil else { return }
        gymVisits[0].departedAt = date
        storage.saveGymVisits(gymVisits)
    }

    func gymVisits(on date: Date) -> [GymVisit] {
        gymVisits.filter { Calendar.current.isDate($0.arrivedAt, inSameDayAs: date) }
    }

    var todaySubjectiveRecovery: SubjectiveRecoveryEntry? {
        subjectiveRecoveryEntries.first { Calendar.current.isDateInToday($0.recordedAt) }
    }

    func saveSubjectiveFatigue(_ level: Int, at date: Date = Date()) {
        if let index = subjectiveRecoveryEntries.firstIndex(where: {
            Calendar.current.isDate($0.recordedAt, inSameDayAs: date)
        }) {
            subjectiveRecoveryEntries[index].fatigueLevel = min(5, max(1, level))
            subjectiveRecoveryEntries[index].recordedAt = date
        } else {
            subjectiveRecoveryEntries.insert(
                SubjectiveRecoveryEntry(recordedAt: date, fatigueLevel: level),
                at: 0
            )
        }
        subjectiveRecoveryEntries.sort { $0.recordedAt > $1.recordedAt }
        storage.saveSubjectiveRecoveryEntries(subjectiveRecoveryEntries)
    }

    func saveAIInsight(_ insight: AIInsight) {
        if let index = aiInsights.firstIndex(where: { $0.id == insight.id }) {
            aiInsights[index] = insight
        } else {
            aiInsights.insert(insight, at: 0)
        }

        aiInsights.sort { $0.date > $1.date }
        storage.saveAIInsights(aiInsights)
    }

    func saveAITransmission(_ record: AITransmissionRecord) {
        if let index = aiTransmissionHistory.firstIndex(where: { $0.id == record.id }) {
            aiTransmissionHistory[index] = record
        } else {
            aiTransmissionHistory.insert(record, at: 0)
        }
        aiTransmissionHistory.sort { $0.sentAt > $1.sentAt }
        storage.saveAITransmissionHistory(aiTransmissionHistory)
    }

    func updateAITransmission(id: UUID, status: AITransmissionStatus) {
        guard let index = aiTransmissionHistory.firstIndex(where: { $0.id == id }) else { return }
        aiTransmissionHistory[index].status = status
        storage.saveAITransmissionHistory(aiTransmissionHistory)
    }

    func deleteAITransmissionHistory(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            aiTransmissionHistory.remove(at: offset)
        }
        storage.saveAITransmissionHistory(aiTransmissionHistory)
    }

    var allExercises: [Exercise] {
        (PresetExerciseStore.exercises + customExercises)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func savePlan(_ plan: TrainingPlan) {
        var nextPlan = plan
        nextPlan.updatedAt = Date()

        if let index = plans.firstIndex(where: { $0.id == nextPlan.id }) {
            plans[index] = nextPlan
        } else {
            plans.append(nextPlan)
        }

        plans.sort { $0.updatedAt > $1.updatedAt }
        storage.savePlans(plans)
    }

    func deletePlans(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            plans.remove(at: offset)
        }
        storage.savePlans(plans)
    }

    func finishWorkout(_ session: WorkoutSession) {
        var completedSession = session
        completedSession.endedAt = Date()

        if let index = workoutHistory.firstIndex(where: { $0.id == completedSession.id }) {
            workoutHistory[index] = completedSession
        } else {
            workoutHistory.insert(completedSession, at: 0)
        }

        workoutHistory.sort { $0.startedAt > $1.startedAt }
        storage.saveWorkoutHistory(workoutHistory)
    }

    func deleteWorkoutHistory(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            workoutHistory.remove(at: offset)
        }
        storage.saveWorkoutHistory(workoutHistory)
    }

    func deleteWorkout(_ session: WorkoutSession) {
        workoutHistory.removeAll { $0.id == session.id }
        storage.saveWorkoutHistory(workoutHistory)
    }

    func workoutSessions(on date: Date = Date()) -> [WorkoutSession] {
        workoutHistory
            .filter { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func saveWorkoutHistorySession(_ session: WorkoutSession) {
        if let index = workoutHistory.firstIndex(where: { $0.id == session.id }) {
            workoutHistory[index] = session
        } else {
            workoutHistory.append(session)
        }

        workoutHistory.sort { $0.startedAt > $1.startedAt }
        storage.saveWorkoutHistory(workoutHistory)
    }

    func saveCustomExercise(_ exercise: Exercise) {
        if let index = customExercises.firstIndex(where: { $0.id == exercise.id }) {
            customExercises[index] = exercise
        } else {
            customExercises.append(exercise)
        }

        customExercises.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        storage.saveCustomExercises(customExercises)
    }

    func deleteCustomExercises(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            customExercises.remove(at: offset)
        }
        storage.saveCustomExercises(customExercises)
    }

    func resetAllData() {
        storage.reset()
        userProfile = .default
        plans = []
        workoutHistory = []
        bodyMetricEntries = []
        bodyMetricGoals = Self.defaultBodyMetricGoals()
        mealEntries = []
        bodyPhotoEntries = []
        customExercises = []
        aiSettings = .default
        aiInsights = []
        sensorSettings = .default
        dailyWorkoutSelection = nil
        gymLocation = nil
        gymVisits = []
        subjectiveRecoveryEntries = []
        aiTransmissionHistory = []
        appearanceSettings = .default
        storage.saveBodyMetricGoals(bodyMetricGoals)
        storage.saveUserProfile(userProfile)
        storage.saveAISettings(aiSettings)
        storage.saveAIInsights(aiInsights)
        storage.saveSensorSettings(sensorSettings)
        storage.saveAppearanceSettings(appearanceSettings)
    }

    func makeExportData() throws -> Data {
        let export = GymDataExport(
            schemaVersion: 1,
            generatedAt: Date(),
            userProfile: userProfile,
            plans: plans,
            workoutHistory: workoutHistory,
            bodyMetricEntries: bodyMetricEntries,
            bodyMetricGoals: bodyMetricGoals,
            mealEntries: mealEntries,
            bodyPhotoEntries: bodyPhotoEntries,
            customExercises: customExercises,
            aiInsights: aiInsights,
            sensorSettings: sensorSettings,
            appearanceSettings: appearanceSettings,
            gymLocation: gymLocation,
            gymVisits: gymVisits,
            subjectiveRecoveryEntries: subjectiveRecoveryEntries,
            aiTransmissionHistory: aiTransmissionHistory
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    func latestCompletedSets(for exercise: Exercise) -> [WorkoutSet] {
        for session in workoutHistory {
            guard let workoutExercise = session.exercises.first(where: { $0.exercise.name == exercise.name }) else {
                continue
            }

            let completedSets = workoutExercise.sets.filter(\.isCompleted)
            if !completedSets.isEmpty {
                return completedSets.sorted { $0.setOrder < $1.setOrder }
            }
        }

        return []
    }

    func bodyMetricEntries(for kind: BodyMetricKind) -> [BodyMetricEntry] {
        bodyMetricEntries
            .filter { $0.kind == kind }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func bodyMetricEntries(for kind: BodyMetricKind, on date: Date) -> [BodyMetricEntry] {
        bodyMetricEntries(for: kind)
            .filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: date) }
    }

    func hasBodyMetricEntry(for kind: BodyMetricKind, on date: Date = Date()) -> Bool {
        !bodyMetricEntries(for: kind, on: date).isEmpty
    }

    func latestBodyMetricEntry(for kind: BodyMetricKind) -> BodyMetricEntry? {
        bodyMetricEntries(for: kind).first
    }

    func bodyMetricGoal(for kind: BodyMetricKind) -> BodyMetricGoal {
        bodyMetricGoals.first { $0.kind == kind } ?? BodyMetricGoal(kind: kind)
    }

    func saveBodyMetricEntry(_ entry: BodyMetricEntry) {
        if let index = bodyMetricEntries.firstIndex(where: { $0.id == entry.id }) {
            bodyMetricEntries[index] = entry
        } else {
            bodyMetricEntries.append(entry)
        }

        bodyMetricEntries.sort { $0.recordedAt > $1.recordedAt }
        storage.saveBodyMetricEntries(bodyMetricEntries)
    }

    func saveBodyMetricGoal(_ goal: BodyMetricGoal) {
        if let index = bodyMetricGoals.firstIndex(where: { $0.kind == goal.kind }) {
            bodyMetricGoals[index] = goal
        } else {
            bodyMetricGoals.append(goal)
        }

        storage.saveBodyMetricGoals(bodyMetricGoals)
    }

    func deleteBodyMetricEntries(kind: BodyMetricKind, at offsets: IndexSet) {
        let visibleEntries = bodyMetricEntries(for: kind)
        let idsToDelete = offsets.map { visibleEntries[$0].id }
        bodyMetricEntries.removeAll { idsToDelete.contains($0.id) }
        storage.saveBodyMetricEntries(bodyMetricEntries)
    }

    func mealEntries(on date: Date = Date()) -> [MealEntry] {
        mealEntries
            .filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: date) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func saveMealEntry(_ entry: MealEntry) {
        if let index = mealEntries.firstIndex(where: { $0.id == entry.id }) {
            mealEntries[index] = entry
        } else {
            mealEntries.append(entry)
        }

        mealEntries.sort { $0.recordedAt > $1.recordedAt }
        storage.saveMealEntries(mealEntries)
    }

    func deleteMealEntries(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            mealEntries.remove(at: offset)
        }
        storage.saveMealEntries(mealEntries)
    }

    func bodyPhotoEntries(on date: Date = Date()) -> [BodyPhotoEntry] {
        bodyPhotoEntries
            .filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: date) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func saveBodyPhotoEntry(_ entry: BodyPhotoEntry) {
        if let index = bodyPhotoEntries.firstIndex(where: { $0.id == entry.id }) {
            bodyPhotoEntries[index] = entry
        } else {
            bodyPhotoEntries.append(entry)
        }

        bodyPhotoEntries.sort { $0.recordedAt > $1.recordedAt }
        storage.saveBodyPhotoEntries(bodyPhotoEntries)
    }

    func deleteBodyPhotoEntries(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            bodyPhotoEntries.remove(at: offset)
        }
        storage.saveBodyPhotoEntries(bodyPhotoEntries)
    }

    private static func alphaUITestPlan() -> TrainingPlan {
        TrainingPlan(
            name: "胸の日",
            exercises: [
                PlanExercise(
                    exercise: PresetExerciseStore.exercises[0],
                    sortOrder: 0
                )
            ]
        )
    }

    private static func defaultBodyMetricGoals() -> [BodyMetricGoal] {
        BodyMetricKind.allCases.map {
            BodyMetricGoal(kind: $0)
        }
    }

    private static func unreachableAISettings() -> AISettings {
        AISettings(
            isEnabled: true,
            baseURLString: "http://127.0.0.1:1",
            apiKey: AISettings.default.apiKey
        )
    }
}

private struct LocalJSONStorage {
    private let userProfileKey = "gym.training.alpha.userProfile"
    private let plansKey = "gym.training.alpha.plans"
    private let historyKey = "gym.training.alpha.history"
    private let bodyMetricEntriesKey = "gym.training.alpha.bodyMetricEntries"
    private let bodyMetricGoalsKey = "gym.training.alpha.bodyMetricGoals"
    private let mealEntriesKey = "gym.training.alpha.mealEntries"
    private let bodyPhotoEntriesKey = "gym.training.alpha.bodyPhotoEntries"
    private let customExercisesKey = "gym.training.alpha.customExercises"
    private let aiSettingsKey = "gym.training.alpha.aiSettings"
    private let aiInsightsKey = "gym.training.alpha.aiInsights"
    private let sensorSettingsKey = "gym.training.alpha.sensorSettings"
    private let dailyWorkoutSelectionKey = "gym.training.alpha.dailyWorkoutSelection"
    private let gymLocationKey = "gym.training.alpha.gymLocation"
    private let gymVisitsKey = "gym.training.alpha.gymVisits"
    private let subjectiveRecoveryEntriesKey = "gym.training.alpha.subjectiveRecoveryEntries"
    private let aiTransmissionHistoryKey = "gym.training.alpha.aiTransmissionHistory"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func loadUserProfile() -> UserProfile {
        load(UserProfile.self, key: userProfileKey) ?? .default
    }

    func saveUserProfile(_ profile: UserProfile) {
        save(profile, key: userProfileKey)
    }

    func loadPlans() -> [TrainingPlan] {
        load([TrainingPlan].self, key: plansKey)
    }

    func savePlans(_ plans: [TrainingPlan]) {
        save(plans, key: plansKey)
    }

    func loadWorkoutHistory() -> [WorkoutSession] {
        load([WorkoutSession].self, key: historyKey)
    }

    func saveWorkoutHistory(_ history: [WorkoutSession]) {
        save(history, key: historyKey)
    }

    func loadBodyMetricEntries() -> [BodyMetricEntry] {
        load([BodyMetricEntry].self, key: bodyMetricEntriesKey)
    }

    func saveBodyMetricEntries(_ entries: [BodyMetricEntry]) {
        save(entries, key: bodyMetricEntriesKey)
    }

    func loadBodyMetricGoals() -> [BodyMetricGoal] {
        load([BodyMetricGoal].self, key: bodyMetricGoalsKey)
    }

    func saveBodyMetricGoals(_ goals: [BodyMetricGoal]) {
        save(goals, key: bodyMetricGoalsKey)
    }

    func loadMealEntries() -> [MealEntry] {
        load([MealEntry].self, key: mealEntriesKey)
    }

    func saveMealEntries(_ entries: [MealEntry]) {
        save(entries, key: mealEntriesKey)
    }

    func loadBodyPhotoEntries() -> [BodyPhotoEntry] {
        load([BodyPhotoEntry].self, key: bodyPhotoEntriesKey)
    }

    func saveBodyPhotoEntries(_ entries: [BodyPhotoEntry]) {
        save(entries, key: bodyPhotoEntriesKey)
    }

    func loadCustomExercises() -> [Exercise] {
        load([Exercise].self, key: customExercisesKey)
    }

    func saveCustomExercises(_ exercises: [Exercise]) {
        save(exercises, key: customExercisesKey)
    }

    func loadAISettings() -> AISettings {
        load(AISettings.self, key: aiSettingsKey) ?? .default
    }

    func saveAISettings(_ settings: AISettings) {
        save(settings, key: aiSettingsKey)
    }

    func loadAIInsights() -> [AIInsight] {
        load([AIInsight].self, key: aiInsightsKey)
    }

    func saveAIInsights(_ insights: [AIInsight]) {
        save(insights, key: aiInsightsKey)
    }

    func loadSensorSettings() -> SensorSettings {
        load(SensorSettings.self, key: sensorSettingsKey) ?? .default
    }

    func saveSensorSettings(_ settings: SensorSettings) {
        save(settings, key: sensorSettingsKey)
    }

    func loadDailyWorkoutSelection() -> DailyWorkoutSelection? {
        load(DailyWorkoutSelection.self, key: dailyWorkoutSelectionKey)
    }

    func saveDailyWorkoutSelection(_ selection: DailyWorkoutSelection?) {
        saveOptional(selection, key: dailyWorkoutSelectionKey)
    }

    func loadGymLocation() -> GymLocation? {
        load(GymLocation.self, key: gymLocationKey)
    }

    func saveGymLocation(_ location: GymLocation?) {
        saveOptional(location, key: gymLocationKey)
    }

    func loadGymVisits() -> [GymVisit] {
        load([GymVisit].self, key: gymVisitsKey)
    }

    func saveGymVisits(_ visits: [GymVisit]) {
        save(visits, key: gymVisitsKey)
    }

    func loadSubjectiveRecoveryEntries() -> [SubjectiveRecoveryEntry] {
        load([SubjectiveRecoveryEntry].self, key: subjectiveRecoveryEntriesKey)
    }

    func saveSubjectiveRecoveryEntries(_ entries: [SubjectiveRecoveryEntry]) {
        save(entries, key: subjectiveRecoveryEntriesKey)
    }

    func loadAITransmissionHistory() -> [AITransmissionRecord] {
        load([AITransmissionRecord].self, key: aiTransmissionHistoryKey)
    }

    func saveAITransmissionHistory(_ records: [AITransmissionRecord]) {
        save(records, key: aiTransmissionHistoryKey)
    }

    func loadAppearanceSettings() -> AppAppearanceSettings {
        .load()
    }

    func saveAppearanceSettings(_ settings: AppAppearanceSettings) {
        settings.save()
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: userProfileKey)
        UserDefaults.standard.removeObject(forKey: plansKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
        UserDefaults.standard.removeObject(forKey: bodyMetricEntriesKey)
        UserDefaults.standard.removeObject(forKey: bodyMetricGoalsKey)
        UserDefaults.standard.removeObject(forKey: mealEntriesKey)
        UserDefaults.standard.removeObject(forKey: bodyPhotoEntriesKey)
        UserDefaults.standard.removeObject(forKey: customExercisesKey)
        UserDefaults.standard.removeObject(forKey: aiSettingsKey)
        UserDefaults.standard.removeObject(forKey: aiInsightsKey)
        UserDefaults.standard.removeObject(forKey: sensorSettingsKey)
        UserDefaults.standard.removeObject(forKey: dailyWorkoutSelectionKey)
        UserDefaults.standard.removeObject(forKey: gymLocationKey)
        UserDefaults.standard.removeObject(forKey: gymVisitsKey)
        UserDefaults.standard.removeObject(forKey: subjectiveRecoveryEntriesKey)
        UserDefaults.standard.removeObject(forKey: aiTransmissionHistoryKey)
        AppAppearanceSettings.reset()
    }

    private func load<T: Decodable>(_ type: [T].Type, key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? decoder.decode(type, from: data) else {
            return []
        }

        return value
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? decoder.decode(type, from: data) else {
            return nil
        }

        return value
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        UserDefaults.standard.set(data, forKey: key)
    }

    private func saveOptional<T: Encodable>(_ value: T?, key: String) {
        guard let value else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        save(value, key: key)
    }
}
