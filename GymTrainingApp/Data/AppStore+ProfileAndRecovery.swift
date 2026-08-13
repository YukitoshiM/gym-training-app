import SwiftUI

@MainActor
extension AppStore {
    func saveUserProfile(_ profile: UserProfile) {
        userProfile = profile
        storage.saveUserProfile(profile)
    }

    func saveAISettings(_ settings: AISettings) {
        if aiSettings.baseURLString != settings.baseURLString
            || aiSettings.apiKey != settings.apiKey
            || aiSettings.usesSessionTokens != settings.usesSessionTokens {
            AIAuthenticationStore.shared.reset()
        }
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

    func appendCoachChatMessage(_ message: CoachChatMessage) {
        coachChatMessages.append(message)
        coachChatMessages = Array(coachChatMessages.suffix(200))
        storage.saveCoachChatMessages(coachChatMessages)
    }

    func clearCoachChatMessages() {
        coachChatMessages = []
        storage.saveCoachChatMessages([])
    }

    func newCoachMemoryCandidates(_ candidates: [CoachMemoryCandidate]) -> [CoachMemoryCandidate] {
        CoachMemoryStore().candidatesNotAlreadyStored(candidates, memories: coachMemories)
    }

    func approveCoachMemory(_ candidate: CoachMemoryCandidate) {
        coachMemories = CoachMemoryStore().approving(candidate, in: coachMemories)
        storage.saveCoachMemories(coachMemories)
    }

    func deleteCoachMemories(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            coachMemories.remove(at: offset)
        }
        storage.saveCoachMemories(coachMemories)
    }

    func clearCoachMemories() {
        coachMemories = []
        storage.saveCoachMemories([])
    }

}
