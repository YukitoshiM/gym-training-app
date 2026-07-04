import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var userProfile: UserProfile = .default
    @Published private(set) var plans: [TrainingPlan] = []
    @Published private(set) var workoutHistory: [WorkoutSession] = []
    @Published private(set) var bodyMetricEntries: [BodyMetricEntry] = []
    @Published private(set) var bodyMetricGoals: [BodyMetricGoal] = []

    private let storage = LocalJSONStorage()

    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-ui-test-data") {
            storage.reset()
        }

        if ProcessInfo.processInfo.arguments.contains("--seed-alpha-ui-test-plan") {
            storage.savePlans([Self.alphaUITestPlan()])
            storage.saveWorkoutHistory([])
            storage.saveBodyMetricEntries([])
            storage.saveBodyMetricGoals(Self.defaultBodyMetricGoals())
            storage.saveUserProfile(.default)
        }

        userProfile = storage.loadUserProfile()
        plans = storage.loadPlans()
        workoutHistory = storage.loadWorkoutHistory()
        bodyMetricEntries = storage.loadBodyMetricEntries()
        bodyMetricGoals = storage.loadBodyMetricGoals()

        if bodyMetricGoals.isEmpty {
            bodyMetricGoals = Self.defaultBodyMetricGoals()
            storage.saveBodyMetricGoals(bodyMetricGoals)
        }
    }

    func saveUserProfile(_ profile: UserProfile) {
        userProfile = profile
        storage.saveUserProfile(profile)
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
}

private struct LocalJSONStorage {
    private let userProfileKey = "gym.training.alpha.userProfile"
    private let plansKey = "gym.training.alpha.plans"
    private let historyKey = "gym.training.alpha.history"
    private let bodyMetricEntriesKey = "gym.training.alpha.bodyMetricEntries"
    private let bodyMetricGoalsKey = "gym.training.alpha.bodyMetricGoals"
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

    func reset() {
        UserDefaults.standard.removeObject(forKey: userProfileKey)
        UserDefaults.standard.removeObject(forKey: plansKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
        UserDefaults.standard.removeObject(forKey: bodyMetricEntriesKey)
        UserDefaults.standard.removeObject(forKey: bodyMetricGoalsKey)
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
}
