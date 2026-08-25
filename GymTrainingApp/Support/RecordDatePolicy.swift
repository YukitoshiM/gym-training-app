import Foundation

enum RecordDatePolicy {
    static let maximumBackdatingDays = 7

    static func normalizedDay(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        clamped(calendar.startOfDay(for: date), now: now, calendar: calendar)
    }

    static func allowedRange(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        let earliest = calendar.date(
            byAdding: .day,
            value: -maximumBackdatingDays,
            to: today
        ) ?? today
        return earliest...now
    }

    static func clamped(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let range = allowedRange(now: now, calendar: calendar)
        return min(max(date, range.lowerBound), range.upperBound)
    }

    static func shifting(
        _ session: WorkoutSession,
        to newDate: Date,
        calendar: Calendar = .current
    ) -> WorkoutSession {
        var shifted = session
        let oldDay = calendar.startOfDay(for: session.startedAt)
        let newDay = calendar.startOfDay(for: newDate)
        let offset = newDay.timeIntervalSince(oldDay)
        shifted.startedAt = session.startedAt.addingTimeInterval(offset)
        shifted.endedAt = session.endedAt?.addingTimeInterval(offset)
        for exerciseIndex in shifted.exercises.indices {
            for setIndex in shifted.exercises[exerciseIndex].sets.indices {
                shifted.exercises[exerciseIndex].sets[setIndex].startedAt =
                    shifted.exercises[exerciseIndex].sets[setIndex].startedAt?.addingTimeInterval(offset)
                shifted.exercises[exerciseIndex].sets[setIndex].completedAt =
                    shifted.exercises[exerciseIndex].sets[setIndex].completedAt?.addingTimeInterval(offset)
            }
        }
        return shifted
    }
}
