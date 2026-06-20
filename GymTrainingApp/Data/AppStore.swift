import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var plans: [TrainingPlan] = []
    @Published private(set) var workoutHistory: [WorkoutSession] = []

    private let storage = LocalJSONStorage()

    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-ui-test-data") {
            storage.reset()
        }

        if ProcessInfo.processInfo.arguments.contains("--seed-alpha-ui-test-plan") {
            storage.savePlans([Self.alphaUITestPlan()])
            storage.saveWorkoutHistory([])
        }

        plans = storage.loadPlans()
        workoutHistory = storage.loadWorkoutHistory()
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
}

private struct LocalJSONStorage {
    private let plansKey = "gym.training.alpha.plans"
    private let historyKey = "gym.training.alpha.history"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

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

    func reset() {
        UserDefaults.standard.removeObject(forKey: plansKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    private func load<T: Decodable>(_ type: [T].Type, key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? decoder.decode(type, from: data) else {
            return []
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
