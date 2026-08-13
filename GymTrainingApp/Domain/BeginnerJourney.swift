import Foundation

struct BeginnerJourneyProgress: Equatable {
    enum NextAction: Equatable {
        case createPlan
        case startWorkout
        case explorePlans
    }

    let hasPlan: Bool
    let completedWorkoutCount: Int

    var level: Int {
        if completedWorkoutCount >= 15 { return 5 }
        if completedWorkoutCount >= 8 { return 4 }
        if completedWorkoutCount >= 3 { return 3 }
        if completedWorkoutCount >= 1 { return 2 }
        return 1
    }

    var completedMilestoneCount: Int {
        (hasPlan ? 1 : 0)
            + (completedWorkoutCount >= 1 ? 1 : 0)
            + (completedWorkoutCount >= 3 ? 1 : 0)
    }

    var progressValue: Double {
        Double(completedMilestoneCount) / 3
    }

    var isFoundationComplete: Bool {
        completedWorkoutCount >= 3
    }

    var nextLevelWorkoutTarget: Int? {
        switch level {
        case 1: 1
        case 2: 3
        case 3: 8
        case 4: 15
        default: nil
        }
    }

    var levelProgressValue: Double {
        switch level {
        case 1:
            return hasPlan ? 0.5 : 0
        case 2:
            return min(1, Double(completedWorkoutCount - 1) / 2)
        case 3:
            return min(1, Double(completedWorkoutCount - 3) / 5)
        case 4:
            return min(1, Double(completedWorkoutCount - 8) / 7)
        default:
            return 1
        }
    }

    var nextAction: NextAction {
        if !hasPlan {
            return .createPlan
        }
        if completedWorkoutCount < 3 {
            return .startWorkout
        }
        return .explorePlans
    }
}
