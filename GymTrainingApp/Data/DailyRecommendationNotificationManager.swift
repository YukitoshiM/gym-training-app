import Foundation
@preconcurrency import UserNotifications

@MainActor
enum DailyRecommendationNotificationManager {
    static let enabledKey = "bodymode.omakase.notificationsEnabled"
    static let morningIdentifier = "bodymode.omakase.morning"
    static let eveningIdentifier = "bodymode.omakase.evening"
    private static let identifiers = [morningIdentifier, eveningIdentifier]
    private static let scheduledDaysKey = "bodymode.omakase.notificationScheduledDays"
    private static let openedDaysKey = "bodymode.omakase.notificationOpenedDays"
    private static let successfulSchedulesKey = "bodymode.omakase.notificationSuccessfulSchedules.v2"
    private static let responsesKey = "bodymode.omakase.notificationResponses.v2"
    private static let migrationVersionKey = "bodymode.omakase.notificationMeasurementMigrationVersion"
    struct NotificationMetrics: Equatable {
        let scheduledCount: Int
        let openedCount: Int

        var responseRate: Double {
            guard scheduledCount > 0 else { return 0 }
            return Double(openedCount) / Double(scheduledCount)
        }
    }

    static func setEnabled(_ enabled: Bool, recommendation: DailyRecommendation?) async {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        guard enabled else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            UsageAnalytics.shared.record(.notificationDisabled)
            return
        }
        let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        guard granted == true else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            return
        }
        schedule(recommendation: recommendation)
    }

    static func schedule(recommendation: DailyRecommendation?) {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let morning = UNMutableNotificationContent()
        morning.title = L10n.string("health_meals_body_ai.79c97ab01e64", fallback: "今日の3つが決まりました")
        morning.body = recommendation?.activeActions.first?.title ?? L10n.string("health_meals_body_ai.2984f299585f", fallback: "今日やることを確認しましょう。")
        morning.sound = .default
        let morningRequest = UNNotificationRequest(
            identifier: morningIdentifier,
            content: morning,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: 8, minute: 0),
                repeats: true
            )
        )
        center.add(morningRequest) { error in
            Task { @MainActor in
                recordSchedulingResult(identifier: morningIdentifier, at: Date(), error: error)
            }
        }

        guard shouldScheduleEvening else { return }

        let evening = UNMutableNotificationContent()
        evening.title = L10n.string("health_meals_body_ai.41cc3b9ae0d5", fallback: "今日の進み具合を確認")
        evening.body = L10n.string("health_meals_body_ai.c8c7a19a1169", fallback: "できたことを明日の提案へ反映します。")
        evening.sound = .default
        let eveningRequest = UNNotificationRequest(
            identifier: eveningIdentifier,
            content: evening,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: 20, minute: 30),
                repeats: true
            )
        )
        center.add(eveningRequest) { error in
            Task { @MainActor in
                recordSchedulingResult(identifier: eveningIdentifier, at: Date(), error: error)
            }
        }
    }

    static func recordOpen(identifier: String, notificationDate: Date = Date()) {
        guard identifiers.contains(identifier) else { return }
        recordOpen(identifier: identifier, at: notificationDate, defaults: .standard)
        UsageAnalytics.shared.record(.notificationOpened, dimension: identifier)
    }

    static var optimizationSummary: String {
        let evening = metrics(for: eveningIdentifier)
        guard evening.scheduledCount >= 7 else { return L10n.string("health_meals_body_ai.d11125844b6c", fallback: "朝・夜の通知を控えめに試しています。") }
        return shouldScheduleEvening
            ? L10n.string("health_meals_body_ai.499175873569", fallback: "通知への反応を見ながら朝・夜に案内します。")
            : L10n.string("health_meals_body_ai.a65c82a761d0", fallback: "通知への反応が少ないため、夜の通知を自動で休止しています。")
    }

    private static var shouldScheduleEvening: Bool {
        let evening = metrics(for: eveningIdentifier)
        return shouldScheduleEvening(
            scheduledDayCount: evening.scheduledCount,
            openedDayCount: evening.openedCount
        )
    }

    nonisolated static func shouldScheduleEvening(scheduledDayCount: Int, openedDayCount: Int) -> Bool {
        guard scheduledDayCount >= 7 else { return true }
        return Double(max(0, openedDayCount)) / Double(max(1, scheduledDayCount)) >= 0.1
    }

    static func resetOptimization() {
        UserDefaults.standard.removeObject(forKey: scheduledDaysKey)
        UserDefaults.standard.removeObject(forKey: openedDaysKey)
        UserDefaults.standard.removeObject(forKey: successfulSchedulesKey)
        UserDefaults.standard.removeObject(forKey: responsesKey)
        UserDefaults.standard.removeObject(forKey: migrationVersionKey)
    }

    static func recordSchedulingResult(
        identifier: String,
        at date: Date,
        error: Error?,
        defaults: UserDefaults = .standard
    ) {
        guard identifiers.contains(identifier), error == nil else { return }
        migrateLegacyDataIfNeeded(defaults: defaults)
        appendRecord(identifier: identifier, date: date, key: successfulSchedulesKey, defaults: defaults)
    }

    static func recordOpen(
        identifier: String,
        at date: Date,
        defaults: UserDefaults
    ) {
        guard identifiers.contains(identifier) else { return }
        migrateLegacyDataIfNeeded(defaults: defaults)
        appendRecord(identifier: identifier, date: date, key: responsesKey, defaults: defaults)
    }

    static func metrics(
        for identifier: String,
        defaults: UserDefaults = .standard
    ) -> NotificationMetrics {
        guard identifiers.contains(identifier) else {
            return NotificationMetrics(scheduledCount: 0, openedCount: 0)
        }
        migrateLegacyDataIfNeeded(defaults: defaults)
        let scheduled = records(for: identifier, key: successfulSchedulesKey, defaults: defaults)
        let opened = records(for: identifier, key: responsesKey, defaults: defaults)
        return NotificationMetrics(
            scheduledCount: scheduled.count,
            openedCount: scheduled.intersection(opened).count
        )
    }

    private static func migrateLegacyDataIfNeeded(defaults: UserDefaults) {
        guard defaults.integer(forKey: migrationVersionKey) < 1 else { return }

        if defaults.stringArray(forKey: successfulSchedulesKey) == nil {
            let legacyScheduled = defaults.stringArray(forKey: scheduledDaysKey) ?? []
            defaults.set(
                legacyScheduled.map { record(identifier: morningIdentifier, day: $0) },
                forKey: successfulSchedulesKey
            )
        }
        if defaults.stringArray(forKey: responsesKey) == nil {
            // The legacy format did not retain morning/evening identity. Keep it as
            // morning history so it cannot incorrectly keep evening notifications enabled.
            let legacyOpened = defaults.stringArray(forKey: openedDaysKey) ?? []
            defaults.set(
                legacyOpened.map { record(identifier: morningIdentifier, day: $0) },
                forKey: responsesKey
            )
        }
        defaults.set(1, forKey: migrationVersionKey)
    }

    private static func appendRecord(
        identifier: String,
        date: Date,
        key: String,
        defaults: UserDefaults
    ) {
        var values = Set(defaults.stringArray(forKey: key) ?? [])
        values.insert(record(identifier: identifier, day: dayKey(date)))
        defaults.set(Array(values.sorted().suffix(60)), forKey: key)
    }

    private static func records(
        for identifier: String,
        key: String,
        defaults: UserDefaults
    ) -> Set<String> {
        let prefix = "\(identifier)|"
        return Set((defaults.stringArray(forKey: key) ?? []).filter { $0.hasPrefix(prefix) })
    }

    private static func record(identifier: String, day: String) -> String {
        "\(identifier)|\(day)"
    }

    private static func dayKey(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}
