import Foundation

enum WatchWorkoutSessionAction {
    case startSet(exerciseID: UUID, setID: UUID, startedAt: Date)
    case cancelSet(exerciseID: UUID, setID: UUID)
    case updateExerciseWeight(exerciseID: UUID, activeSetID: UUID, weight: Double)
    case updateReps(exerciseID: UUID, setID: UUID, reps: Int)
    case updateRPE(exerciseID: UUID, setID: UUID, rpe: Double?)
    case updatePlannedTempo(
        exerciseID: UUID,
        setID: UUID,
        concentricSeconds: Int,
        eccentricSeconds: Int,
        beatSpeed: Int
    )
    case updateObservedTempo(
        exerciseID: UUID,
        setID: UUID,
        concentricSeconds: Double,
        eccentricSeconds: Double,
        wasManuallyCorrected: Bool
    )
    case updateNote(String?)
    case completeSet(
        exerciseID: UUID,
        setID: UUID,
        isCompleted: Bool,
        completedAt: Date,
        sensorSummary: WatchSetSensorSummary?
    )
}

enum WatchWorkoutSessionReducer {
    @discardableResult
    static func reduce(
        session: inout WatchWorkoutSessionSnapshot,
        action: WatchWorkoutSessionAction
    ) -> Bool {
        switch action {
        case let .startSet(exerciseID, setID, startedAt):
            guard let selected = setLocation(
                in: session,
                exerciseID: exerciseID,
                setID: setID
            ), !session.exercises[selected.exercise].sets[selected.set].isCompleted else {
                return false
            }

            for exerciseIndex in session.exercises.indices {
                for setIndex in session.exercises[exerciseIndex].sets.indices {
                    let isSelected = exerciseIndex == selected.exercise && setIndex == selected.set
                    guard !isSelected,
                          session.exercises[exerciseIndex].sets[setIndex].startedAt != nil,
                          !session.exercises[exerciseIndex].sets[setIndex].isCompleted else {
                        continue
                    }

                    session.exercises[exerciseIndex].sets[setIndex].startedAt = nil
                    session.exercises[exerciseIndex].sets[setIndex].completedAt = nil
                    session.exercises[exerciseIndex].sets[setIndex].sensorSummary = nil
                    session.exercises[exerciseIndex].sets[setIndex].tempoPerformance = nil
                    session.exercises[exerciseIndex].sets[setIndex].rpe = nil
                }
            }

            let previousStarted = session.exercises[selected.exercise].sets[selected.set].startedAt
            session.exercises[selected.exercise].sets[selected.set].startedAt =
                previousStarted ?? startedAt
            if previousStarted == nil {
                session.exercises[selected.exercise].sets[selected.set].actualWeight =
                    session.exercises[selected.exercise].sets[selected.set].actualWeight
            }
            return true

        case let .cancelSet(exerciseID, setID):
            guard let location = setLocation(in: session, exerciseID: exerciseID, setID: setID),
                  !session.exercises[location.exercise].sets[location.set].isCompleted else {
                return false
            }
            session.exercises[location.exercise].sets[location.set].startedAt = nil
            session.exercises[location.exercise].sets[location.set].completedAt = nil
            session.exercises[location.exercise].sets[location.set].sensorSummary = nil
            session.exercises[location.exercise].sets[location.set].tempoPerformance = nil
            return true

        case let .updateExerciseWeight(exerciseID, activeSetID, weight):
            guard let location = setLocation(
                in: session,
                exerciseID: exerciseID,
                setID: activeSetID
            ), !session.exercises[location.exercise].sets[location.set].isCompleted else {
                return false
            }
            session.exercises[location.exercise].sets[location.set].actualWeight = weight
            return true

        case let .updateReps(exerciseID, setID, reps):
            guard let location = editableSetLocation(
                in: session,
                exerciseID: exerciseID,
                setID: setID
            ) else {
                return false
            }
            session.exercises[location.exercise].sets[location.set].actualReps = max(0, min(999, reps))
            return true

        case let .updateRPE(exerciseID, setID, rpe):
            guard let location = editableSetLocation(
                in: session,
                exerciseID: exerciseID,
                setID: setID
            ) else {
                return false
            }
            session.exercises[location.exercise].sets[location.set].rpe = rpe.map {
                min(10, max(1, ($0 * 2).rounded() / 2))
            }
            return true

        case let .updatePlannedTempo(
            exerciseID,
            setID,
            concentricSeconds,
            eccentricSeconds,
            beatSpeed
        ):
            guard let location = setLocation(in: session, exerciseID: exerciseID, setID: setID),
                  !session.exercises[location.exercise].sets[location.set].isCompleted,
                  (1...10).contains(concentricSeconds),
                  (1...10).contains(eccentricSeconds),
                  (1...3).contains(beatSpeed) else {
                return false
            }
            session.exercises[location.exercise].sets[location.set].plannedConcentricSeconds = concentricSeconds
            session.exercises[location.exercise].sets[location.set].plannedEccentricSeconds = eccentricSeconds
            session.exercises[location.exercise].sets[location.set].plannedTempoBeatSpeed = beatSpeed
            return true

        case let .updateObservedTempo(
            exerciseID,
            setID,
            concentricSeconds,
            eccentricSeconds,
            wasManuallyCorrected
        ):
            guard let location = setLocation(
                in: session,
                exerciseID: exerciseID,
                setID: setID
            ) else {
                return false
            }
            let set = session.exercises[location.exercise].sets[location.set]
            guard let performance = TempoPerformance(
                plannedConcentricSeconds: set.plannedConcentricSeconds,
                plannedEccentricSeconds: set.plannedEccentricSeconds,
                observedConcentricSeconds: concentricSeconds,
                observedEccentricSeconds: eccentricSeconds,
                wasManuallyCorrected: wasManuallyCorrected
            ) else {
                return false
            }
            session.exercises[location.exercise].sets[location.set].tempoPerformance = performance
            return true

        case let .updateNote(note):
            session.note = note
            return true

        case let .completeSet(exerciseID, setID, isCompleted, completedAt, sensorSummary):
            guard let location = setLocation(in: session, exerciseID: exerciseID, setID: setID) else {
                return false
            }
            if isCompleted {
                session.exercises[location.exercise].sets[location.set].startedAt =
                    session.exercises[location.exercise].sets[location.set].startedAt ?? completedAt
            }
            session.exercises[location.exercise].sets[location.set].isCompleted = isCompleted
            session.exercises[location.exercise].sets[location.set].completedAt = isCompleted ? completedAt : nil
            if isCompleted, let sensorSummary {
                session.exercises[location.exercise].sets[location.set].sensorSummary = sensorSummary
                if session.exercises[location.exercise].sets[location.set]
                    .tempoPerformance?.wasManuallyCorrected != true {
                    let set = session.exercises[location.exercise].sets[location.set]
                    session.exercises[location.exercise].sets[location.set].tempoPerformance = TempoPerformance(
                        plannedConcentricSeconds: set.plannedConcentricSeconds,
                        plannedEccentricSeconds: set.plannedEccentricSeconds,
                        observedConcentricSeconds: sensorSummary.averageConcentricDuration,
                        observedEccentricSeconds: sensorSummary.averageEccentricDuration,
                        wasManuallyCorrected: false
                    )
                }
            } else if !isCompleted {
                session.exercises[location.exercise].sets[location.set].sensorSummary = nil
                session.exercises[location.exercise].sets[location.set].tempoPerformance = nil
            }
            return true
        }
    }

    private static func editableSetLocation(
        in session: WatchWorkoutSessionSnapshot,
        exerciseID: UUID,
        setID: UUID
    ) -> (exercise: Int, set: Int)? {
        guard let location = setLocation(in: session, exerciseID: exerciseID, setID: setID),
              session.exercises[location.exercise].sets[location.set].startedAt != nil,
              !session.exercises[location.exercise].sets[location.set].isCompleted else {
            return nil
        }
        return location
    }

    private static func setLocation(
        in session: WatchWorkoutSessionSnapshot,
        exerciseID: UUID,
        setID: UUID
    ) -> (exercise: Int, set: Int)? {
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else {
            return nil
        }
        return (exerciseIndex, setIndex)
    }
}
