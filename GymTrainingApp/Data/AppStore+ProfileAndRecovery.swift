import SwiftUI

@MainActor
extension AppStore {
    func saveUserProfile(_ profile: UserProfile) {
        userProfile = profile
        UserDefaults.standard.set(profile.weightUnit.rawValue, forKey: BodyUnitPreferences.weightKey)
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

    func deleteGymVisit(_ visit: GymVisit) {
        guard let index = gymVisits.firstIndex(where: { $0.id == visit.id }) else { return }
        let removed = gymVisits.remove(at: index)
        storage.saveGymVisits(gymVisits)
        moveToTrash(title: L10n.string("health_meals_body_ai.gym_visit", fallback: "ジム訪問"), payload: .gymVisit(removed))
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

    func deleteSubjectiveRecovery(_ entry: SubjectiveRecoveryEntry) {
        guard let index = subjectiveRecoveryEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        let removed = subjectiveRecoveryEntries.remove(at: index)
        storage.saveSubjectiveRecoveryEntries(subjectiveRecoveryEntries)
        moveToTrash(title: L10n.string("health_meals_body_ai.fatigue_record", fallback: "疲労記録"), payload: .subjectiveRecovery(removed))
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

    func deleteAIInsight(_ insight: AIInsight) {
        guard let index = aiInsights.firstIndex(where: { $0.id == insight.id }) else { return }
        let removed = aiInsights.remove(at: index)
        storage.saveAIInsights(aiInsights)
        moveToTrash(title: L10n.string("health_meals_body_ai.ai_report", fallback: "AIレポート"), payload: .aiInsight(removed))
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
        if status == .completed {
            aiTransmissionHistory[index].failureMessage = nil
            aiTransmissionHistory[index].recoverySuggestion = nil
            aiTransmissionHistory[index].canRetry = nil
            aiTransmissionHistory[index].consumedQuota = nil
        }
        storage.saveAITransmissionHistory(aiTransmissionHistory)
    }

    func recordAITransmissionFailure(id: UUID, error: Error) {
        let presentation = AIClientError.presentation(for: error)
        recordAITransmissionFailure(
            id: id,
            message: presentation.message,
            recovery: presentation.recovery,
            canRetry: Self.isRetryableAIError(error)
        )
    }

    func recordAITransmissionFailure(
        id: UUID,
        message: String,
        recovery: String?,
        canRetry: Bool
    ) {
        guard let index = aiTransmissionHistory.firstIndex(where: { $0.id == id }) else { return }
        aiTransmissionHistory[index].status = .failed
        aiTransmissionHistory[index].failureMessage = message
        aiTransmissionHistory[index].recoverySuggestion = recovery
        aiTransmissionHistory[index].canRetry = canRetry
        aiTransmissionHistory[index].consumedQuota = false
        storage.saveAITransmissionHistory(aiTransmissionHistory)
    }

    private static func isRetryableAIError(_ error: Error) -> Bool {
        guard let clientError = error as? AIClientError else { return true }
        switch clientError {
        case .disabled, .missingAPIKey, .invalidBaseURL, .insecureRemoteHTTPHost,
             .invalidImage, .emptyMealItems, .secureStorageFailed,
             .accountSignInRequired, .insufficientCredits:
            return false
        case .httpStatus(let code):
            return code == 408 || code == 429 || code >= 500
        case .quotaExceeded:
            return false
        case .serverPolicy, .invalidResponse, .requestFailed, .transport, .decodingFailed,
             .rewardedAdVerificationPending:
            return true
        }
    }

    func deleteAITransmissionHistory(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            guard aiTransmissionHistory.indices.contains(offset) else { continue }
            let record = aiTransmissionHistory.remove(at: offset)
            moveToTrash(title: record.purpose, payload: .aiTransmission(record))
        }
        storage.saveAITransmissionHistory(aiTransmissionHistory)
    }

    func appendCoachChatMessage(_ message: CoachChatMessage) {
        coachChatMessages.append(message)
        coachChatMessages = Array(coachChatMessages.suffix(200))
        storage.saveCoachChatMessages(coachChatMessages)
    }

    func clearCoachChatMessages() {
        for message in coachChatMessages {
            moveToTrash(title: L10n.string("health_meals_body_ai.ai_chat", fallback: "AIチャット"), payload: .coachChatMessage(message))
        }
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
            guard coachMemories.indices.contains(offset) else { continue }
            let memory = coachMemories.remove(at: offset)
            moveToTrash(title: memory.content, payload: .coachMemory(memory))
        }
        storage.saveCoachMemories(coachMemories)
    }

    func clearCoachMemories() {
        for memory in coachMemories {
            moveToTrash(title: memory.content, payload: .coachMemory(memory))
        }
        coachMemories = []
        storage.saveCoachMemories([])
    }

}
