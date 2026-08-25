import SwiftUI

@MainActor
extension AppStore {
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

    func bodyWeight(on date: Date) -> Double? {
        bodyMetricEntries(for: .bodyWeight, on: date).first?.value
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
        UsageAnalytics.shared.record(.bodyMetricSaved, dimension: entry.kind.rawValue)
    }

    @discardableResult
    func saveMissingBodyPhotoEstimates(
        from comment: BodyPhotoAIComment,
        at date: Date
    ) -> [BodyMetricEntry] {
        let entries = BodyMetricEstimateService.photoEstimates(
            from: comment.referenceEstimates ?? [],
            existingEntries: bodyMetricEntries,
            at: date
        )
        entries.forEach(saveBodyMetricEntry)
        return entries
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
        let removed = offsets.compactMap { visibleEntries.indices.contains($0) ? visibleEntries[$0] : nil }
        let idsToDelete = removed.map(\.id)
        bodyMetricEntries.removeAll { idsToDelete.contains($0.id) }
        storage.saveBodyMetricEntries(bodyMetricEntries)
        for entry in removed {
            moveToTrash(title: entry.kind.displayName, payload: .bodyMetric(entry))
        }
    }

    func mealEntries(on date: Date = Date()) -> [MealEntry] {
        mealEntries
            .filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: date) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func latestMealEntry(for mealType: MealType) -> MealEntry? {
        mealEntries.first { $0.mealType == mealType }
    }

    func saveMealEntry(_ entry: MealEntry) {
        if let index = mealEntries.firstIndex(where: { $0.id == entry.id }) {
            mealEntries[index] = entry
        } else {
            mealEntries.append(entry)
        }

        mealEntries.sort { $0.recordedAt > $1.recordedAt }
        storage.saveMealEntries(mealEntries)
        UsageAnalytics.shared.record(.mealSaved)
    }

    func deleteMealEntries(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            guard mealEntries.indices.contains(offset) else { continue }
            let entry = mealEntries.remove(at: offset)
            moveToTrash(title: entry.name, payload: .meal(entry))
        }
        storage.saveMealEntries(mealEntries)
    }

    func bodyPhotoEntries(on date: Date = Date()) -> [BodyPhotoEntry] {
        bodyPhotoEntries
            .filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: date) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    var bodyPhotoSets: [BodyPhotoSet] {
        BodyPhotoSet.grouped(bodyPhotoEntries)
    }

    func bodyPhotoSet(on date: Date = Date()) -> BodyPhotoSet? {
        bodyPhotoSets.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func saveBodyPhotoEntry(_ entry: BodyPhotoEntry) {
        if let index = bodyPhotoEntries.firstIndex(where: { $0.id == entry.id }) {
            bodyPhotoEntries[index] = entry
        } else {
            bodyPhotoEntries.append(entry)
        }

        bodyPhotoEntries.sort { $0.recordedAt > $1.recordedAt }
        storage.saveBodyPhotoEntries(bodyPhotoEntries)
        UsageAnalytics.shared.record(.bodyPhotoSaved)
    }

    func deleteBodyPhotoEntries(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            guard bodyPhotoEntries.indices.contains(offset) else { continue }
            let entry = bodyPhotoEntries.remove(at: offset)
            moveToTrash(title: entry.angle.displayName, payload: .bodyPhotos([entry]))
        }
        storage.saveBodyPhotoEntries(bodyPhotoEntries)
    }

    func saveBodyPhotoSet(
        _ entries: [BodyPhotoEntry],
        replacing date: Date,
        removingAngles: Set<BodyPhotoAngle> = []
    ) {
        let incomingPhotoAngles = Set(
            entries.compactMap { entry in entry.imageData == nil ? nil : entry.angle }
        )
        let retainedEntries = bodyPhotoEntries.filter { entry in
            guard Calendar.current.isDate(entry.recordedAt, inSameDayAs: date) else {
                return false
            }
            guard entry.imageData != nil else { return false }
            return !incomingPhotoAngles.contains(entry.angle) && !removingAngles.contains(entry.angle)
        }
        bodyPhotoEntries.removeAll { Calendar.current.isDate($0.recordedAt, inSameDayAs: date) }
        bodyPhotoEntries.append(contentsOf: retainedEntries)
        bodyPhotoEntries.append(contentsOf: entries)
        bodyPhotoEntries.sort { $0.recordedAt > $1.recordedAt }
        storage.saveBodyPhotoEntries(bodyPhotoEntries)
        if !entries.isEmpty || !retainedEntries.isEmpty {
            UsageAnalytics.shared.record(.bodyPhotoSaved)
        }
    }

    func updateBodyPhotoSetAnalysis(on date: Date, comment: BodyPhotoAIComment) {
        for index in bodyPhotoEntries.indices
        where Calendar.current.isDate(bodyPhotoEntries[index].recordedAt, inSameDayAs: date)
            && bodyPhotoEntries[index].imageData != nil {
            bodyPhotoEntries[index].aiComment = comment
        }
        storage.saveBodyPhotoEntries(bodyPhotoEntries)
    }

    func deleteBodyPhotoSets(at offsets: IndexSet) {
        let sets = bodyPhotoSets
        let dates = offsets.compactMap { sets.indices.contains($0) ? sets[$0].date : nil }
        let removed = bodyPhotoEntries.filter { entry in
            dates.contains { Calendar.current.isDate(entry.recordedAt, inSameDayAs: $0) }
        }
        bodyPhotoEntries.removeAll { entry in
            dates.contains { Calendar.current.isDate(entry.recordedAt, inSameDayAs: $0) }
        }
        storage.saveBodyPhotoEntries(bodyPhotoEntries)
        if !removed.isEmpty {
            moveToTrash(
                title: L10n.string("health_meals_body_ai.progress_photo_set", fallback: "体型写真セット"),
                payload: .bodyPhotos(removed)
            )
        }
    }

}
