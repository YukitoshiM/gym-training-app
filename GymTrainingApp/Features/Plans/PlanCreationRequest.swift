import Foundation

enum PlanEditorMode: Equatable {
    case standard
    case beginnerStarter
    case beginnerProgression
    case aiCoach
}

struct PlanCreationRequest: Identifiable, Equatable {
    let id = UUID()
    let draft: TrainingPlan
    let mode: PlanEditorMode

    static var blank: PlanCreationRequest {
        PlanCreationRequest(
            draft: TrainingPlan(name: ""),
            mode: .standard
        )
    }

    static func beginnerStarter(_ draft: TrainingPlan) -> PlanCreationRequest {
        PlanCreationRequest(draft: draft, mode: .beginnerStarter)
    }

    static func beginnerProgression(_ draft: TrainingPlan) -> PlanCreationRequest {
        PlanCreationRequest(draft: draft, mode: .beginnerProgression)
    }

    static func aiCoach(_ draft: TrainingPlan) -> PlanCreationRequest {
        PlanCreationRequest(draft: draft, mode: .aiCoach)
    }
}
