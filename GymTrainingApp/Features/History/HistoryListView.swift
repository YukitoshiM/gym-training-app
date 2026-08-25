import SwiftUI

struct HistoryListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date? = Date()
    @State private var pendingDeleteSession: WorkoutSession?

    private var hasAnyLog: Bool {
        !appStore.workoutHistory.isEmpty
        || !appStore.bodyMetricEntries.isEmpty
        || !appStore.mealEntries.isEmpty
        || !appStore.bodyPhotoEntries.isEmpty
        || !appStore.gymVisits.isEmpty
    }

    private var visibleSessions: [WorkoutSession] {
        guard let selectedDate else {
            return appStore.workoutHistory
        }

        return appStore.workoutHistory.filter {
            Calendar.current.isDate($0.startedAt, inSameDayAs: selectedDate)
        }
    }

    private var dailySummaries: [DailyLogSummary] {
        let calendar = Calendar.current
        var dates: Set<Date> = []

        appStore.workoutHistory.forEach { dates.insert(calendar.startOfDay(for: $0.startedAt)) }
        appStore.bodyMetricEntries.forEach { dates.insert(calendar.startOfDay(for: $0.recordedAt)) }
        appStore.mealEntries.forEach { dates.insert(calendar.startOfDay(for: $0.recordedAt)) }
        appStore.bodyPhotoEntries.forEach { dates.insert(calendar.startOfDay(for: $0.recordedAt)) }
        appStore.gymVisits.forEach { dates.insert(calendar.startOfDay(for: $0.arrivedAt)) }

        return dates
            .map { dailySummary(on: $0) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasAnyLog {
                    VStack {
                        Spacer()

                        VStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(AppTheme.mutedInk)
                                .accessibilityHidden(true)
                            Text(L10n.string("training.2d6bc7bc380f", fallback: "履歴はまだありません"))
                                .font(.title2.bold())
                                .foregroundStyle(AppTheme.ink)
                            Text(L10n.string("training.bbb6e51d140e", fallback: "記録した内容を日別に見返せます。"))
                                .font(.body)
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        .appTourTarget(.historyTimeline)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            WorkoutCalendarView(
                                displayedMonth: $displayedMonth,
                                selectedDate: $selectedDate,
                                summaries: dailySummaries
                            )
                            .appTourTarget(.historyTimeline)

                            if let selectedDate {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.string("training.43ab6b5ca1ab", fallback: "選択日のまとめ"))
                                        .font(.footnote.bold())
                                        .foregroundStyle(AppTheme.mutedInk)

                                    DailyJournalSummaryCard(
                                        summary: dailySummary(on: selectedDate),
                                        weightUnit: appStore.userProfile.weightUnit
                                    )
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(selectedDateTitle)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.ink)

                                    Spacer()

                                    if selectedDate != nil {
                                        Button(L10n.string("training.c7fe2b510de0", fallback: "すべて")) {
                                            selectedDate = nil
                                        }
                                        .font(.footnote.bold())
                                    }
                                }

                                if visibleSessions.isEmpty {
                                    Text(selectedDate == nil ? L10n.string("training.7e246c7e390c", fallback: "トレーニング履歴はありません") : L10n.string("training.8a729334a0cc", fallback: "この日のトレーニングはありません"))
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.mutedInk)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 18)
                                }

                                ForEach(visibleSessions) { session in
                                    NavigationLink(value: session) {
                                        HistoryRow(session: session)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("historyRow-\(session.title)")
                                    .contextMenu {
                                        Button(L10n.string("training.ac806fcfe196", fallback: "削除"), role: .destructive) {
                                            pendingDeleteSession = session
                                        }
                                    }
                                }
                            }

                            if !appStore.workoutHistory.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(L10n.string("training.172f4e4cd7d1", fallback: "分析"))
                                            .font(.headline)
                                            .foregroundStyle(AppTheme.ink)
                                        Text(L10n.string("training.cb5d23c702e0", fallback: "蓄積した記録を期間・種目・センサー別に確認"))
                                            .font(.footnote)
                                            .foregroundStyle(AppTheme.mutedInk)
                                    }

                                    VStack(spacing: 0) {
                                        NavigationLink {
                                            HistoryPeriodComparisonView()
                                        } label: {
                                            HistoryAnalyticsLink(
                                                title: L10n.string("training.history_period_comparison", fallback: "期間比較"),
                                                systemImage: "calendar.badge.clock"
                                            )
                                        }
                                        .accessibilityIdentifier("historyPeriodComparisonLink")

                                        Divider()
                                            .padding(.leading, 44)

                                        NavigationLink {
                                            WeeklyVolumeView()
                                        } label: {
                                            HistoryAnalyticsLink(
                                                title: L10n.string("training.79469f04a73c", fallback: "週次ボリューム分析"),
                                                systemImage: "chart.bar.xaxis"
                                            )
                                        }
                                        .accessibilityIdentifier("weeklyVolumeLink")

                                        Divider()
                                            .padding(.leading, 44)

                                        NavigationLink {
                                            ExerciseHistoryListView()
                                        } label: {
                                            HistoryAnalyticsLink(
                                                title: L10n.string("training.f3db21504894", fallback: "種目別履歴"),
                                                systemImage: "dumbbell"
                                            )
                                        }
                                        .accessibilityIdentifier("exerciseHistoryLink")

                                        Divider()
                                            .padding(.leading, 44)

                                        NavigationLink {
                                            SensorTrainingAnalysisView()
                                        } label: {
                                            HistoryAnalyticsLink(
                                                title: L10n.string("training.71d42af1e263", fallback: "Watchセンサー分析"),
                                                systemImage: "heart.text.square"
                                            )
                                        }
                                        .accessibilityIdentifier("sensorTrainingAnalysisLink")
                                    }
                                    .buttonStyle(.plain)
                                    .background(
                                        AppTheme.elevatedBackground,
                                        in: RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(TrainingBackground())
                }
            }
            .navigationTitle(L10n.string("training.6157f8cd2251", fallback: "履歴"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WorkoutSession.self) { session in
                HistoryDetailView(session: session)
            }
            .confirmationDialog(
                L10n.string("training.5a03b277c63d", fallback: "この履歴を削除しますか？"),
                isPresented: Binding(
                    get: { pendingDeleteSession != nil },
                    set: { if !$0 { pendingDeleteSession = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(L10n.string("training.ac806fcfe196", fallback: "削除"), role: .destructive) {
                    if let pendingDeleteSession {
                        appStore.deleteWorkout(pendingDeleteSession)
                    }
                    pendingDeleteSession = nil
                }
                Button(L10n.string("training.76c1a8f001dd", fallback: "キャンセル"), role: .cancel) {
                    pendingDeleteSession = nil
                }
            }
        }
    }

    private var selectedDateTitle: String {
        guard let selectedDate else {
            return L10n.string("training.1c72d399dbcb", fallback: "すべての記録")
        }

        return AppFormatters.shortDate.string(from: selectedDate)
    }

    private func dailySummary(on date: Date) -> DailyLogSummary {
        let bodyMetricEntries = BodyMetricKind.allCases.flatMap { kind in
            appStore.bodyMetricEntries(for: kind, on: date)
        }
        .sorted { lhs, rhs in
            if lhs.kind.rawValue == rhs.kind.rawValue {
                return lhs.recordedAt > rhs.recordedAt
            }

            return lhs.kind.rawValue < rhs.kind.rawValue
        }

        return DailyLogSummary(
            date: Calendar.current.startOfDay(for: date),
            workouts: appStore.workoutSessions(on: date),
            bodyMetricEntries: bodyMetricEntries,
            meals: appStore.mealEntries(on: date),
            bodyPhotos: appStore.bodyPhotoEntries(on: date),
            gymVisits: appStore.gymVisits(on: date)
        )
    }
}

private struct HistoryAnalyticsLink: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)

            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(AppTheme.mutedInk)
        }
        .frame(minHeight: 48)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}

private struct DailyLogSummary: Identifiable {
    let date: Date
    let workouts: [WorkoutSession]
    let bodyMetricEntries: [BodyMetricEntry]
    let meals: [MealEntry]
    let bodyPhotos: [BodyPhotoEntry]
    let gymVisits: [GymVisit]

    var id: Date { date }

    var bodyPhotoSets: [BodyPhotoSet] {
        BodyPhotoSet.grouped(bodyPhotos)
    }

    var totalLogCount: Int {
        workouts.count + bodyMetricEntries.count + meals.count + bodyPhotoSets.count + gymVisits.count
    }

    var totalCalories: Double {
        meals.reduce(0) { $0 + $1.calories }
    }

    var totalProtein: Double {
        meals.reduce(0) { $0 + $1.protein }
    }

    var totalFat: Double {
        meals.reduce(0) { $0 + $1.fat }
    }

    var totalCarbs: Double {
        meals.reduce(0) { $0 + $1.carbs }
    }

    var totalVolume: Double {
        workouts.reduce(0) { $0 + $1.totalVolume }
    }
}

private struct WorkoutCalendarView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date?

    let summaries: [DailyLogSummary]

    private let calendar = Calendar.current
    private let weekdays = [L10n.string("training.3064c4117490", fallback: "日"), L10n.string("training.f29b58714fe0", fallback: "月"), L10n.string("training.29166d008ccd", fallback: "火"), L10n.string("training.d34df1b5c392", fallback: "水"), L10n.string("training.0ec9a1b0cd59", fallback: "木"), L10n.string("training.78d7f266fb1e", fallback: "金"), L10n.string("training.bb83fd66413b", fallback: "土")]

    var body: some View {
        let days = calendarDays

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROGRESS CALENDAR")
                        .font(.footnote.bold())
                        .tracking(1)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("historyCalendar")

                    Text(monthTitle)
                        .font(.title3.bold())
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        moveMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L10n.string("training.0d59a64e0167", fallback: "前の月"))

                    Button {
                        moveMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L10n.string("training.e7954b54321d", fallback: "次の月"))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.ink)
            }

            Grid(horizontalSpacing: 6, verticalSpacing: 8) {
                GridRow {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.footnote.bold())
                            .foregroundStyle(AppTheme.mutedInk)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(0..<((days.count + 6) / 7), id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column
                            if index < days.count {
                                let day = days[index]
                                CalendarDayButton(
                                    day: day,
                                    summary: summary(on: day.date),
                                    isSelected: selectedDate.map {
                                        calendar.isDate($0, inSameDayAs: day.date)
                                    } ?? false
                                ) {
                                    selectedDate = day.date
                                }
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: 42)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 0) {
                ForEach(CalendarRecordKind.allCases) { kind in
                    Label {
                        Text(kind.title)
                    } icon: {
                        Image(systemName: kind.systemImage)
                    }
                    .font(.footnote.bold())
                    .foregroundStyle(kind.tint)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.string("training.f71407d1df3f", fallback: "記録種別、筋トレ、身体、食事、写真、ジム"))
        }
        .padding(16)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 14, x: 0, y: 8)
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.year().month(.wide).locale(.autoupdatingCurrent))
    }

    private var calendarDays: [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let monthStartWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthEndWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1)) else {
            return []
        }

        var days: [CalendarDay] = []
        var current = monthStartWeek.start

        while current < monthEndWeek.end {
            days.append(
                CalendarDay(
                    date: current,
                    isInDisplayedMonth: calendar.isDate(current, equalTo: displayedMonth, toGranularity: .month)
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = next
        }

        return days
    }

    private func summary(on date: Date) -> DailyLogSummary? {
        summaries.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func moveMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
        selectedDate = nil
    }
}

private struct CalendarDay: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

private enum CalendarRecordKind: String, CaseIterable, Identifiable {
    case workout
    case bodyMetric
    case meal
    case bodyPhoto
    case gymVisit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workout: L10n.string("training.0902af066756", fallback: "筋トレ")
        case .bodyMetric: L10n.string("training.f7f7fa19af19", fallback: "身体")
        case .meal: L10n.string("training.98bedebd5bd9", fallback: "食事")
        case .bodyPhoto: L10n.string("training.7cbb717aa7f1", fallback: "写真")
        case .gymVisit: L10n.string("training.1f24d20a2866", fallback: "ジム")
        }
    }

    var systemImage: String {
        switch self {
        case .workout: "dumbbell.fill"
        case .bodyMetric: "scalemass.fill"
        case .meal: "fork.knife"
        case .bodyPhoto: "camera.fill"
        case .gymVisit: "mappin.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .workout: AppTheme.accent
        case .bodyMetric: AppTheme.blue
        case .meal: AppTheme.orange
        case .bodyPhoto: AppTheme.purple
        case .gymVisit: AppTheme.tertiaryAccent
        }
    }

    func count(in summary: DailyLogSummary?) -> Int {
        switch self {
        case .workout: summary?.workouts.count ?? 0
        case .bodyMetric: summary?.bodyMetricEntries.count ?? 0
        case .meal: summary?.meals.count ?? 0
        case .bodyPhoto: summary?.bodyPhotoSets.count ?? 0
        case .gymVisit: summary?.gymVisits.count ?? 0
        }
    }
}

private struct CalendarDayButton: View {
    let day: CalendarDay
    let summary: DailyLogSummary?
    let isSelected: Bool
    let action: () -> Void

    private var dayNumber: Int {
        Calendar.current.component(.day, from: day.date)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(dayNumber)")
                    .font(.subheadline.weight(totalLogCount > 0 ? .bold : .regular))

                HStack(spacing: 1) {
                    ForEach(recordKinds) { kind in
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundStyle(indicatorColor(for: kind))
                            .frame(width: 7, height: 7)
                    }

                    if recordKinds.isEmpty {
                        Color.clear
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(height: 7)
                .opacity(day.isInDisplayedMonth ? 1 : 0.45)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isSelected ? AppTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("historyCalendarDay-\(accessibilityDateID)")
    }

    private var foregroundColor: Color {
        if isSelected {
            return AppTheme.onAccent
        }

        return day.isInDisplayedMonth ? AppTheme.ink : AppTheme.mutedInk.opacity(0.45)
    }
    private var accessibilityLabel: String {
        let date = day.date.formatted(
            .dateTime.month().day().weekday(.wide).locale(.autoupdatingCurrent)
        )
        if totalLogCount == 0 {
            return L10n.string("training.4547089161d9", fallback: "{{value1}}、記録なし", values: [String(describing: date)])
        }

        let details = recordKinds
            .map { L10n.string("training.4fbc27d5b179", fallback: "{{value1}}{{value2}}件", values: [String(describing: $0.title), String(describing: $0.count(in: summary))]) }
            .joined(separator: "、")
        return "\(date)、\(details)"
    }

    private var accessibilityDateID: String {
        Self.identifierFormatter.string(from: day.date)
    }

    private var totalLogCount: Int {
        summary?.totalLogCount ?? 0
    }

    private var recordKinds: [CalendarRecordKind] {
        CalendarRecordKind.allCases.filter { $0.count(in: summary) > 0 }
    }

    private func indicatorColor(for kind: CalendarRecordKind) -> Color {
        isSelected ? AppTheme.onAccent : kind.tint
    }

    private static let identifierFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct DailyJournalSummaryCard: View {
    let summary: DailyLogSummary
    let weightUnit: WeightUnit

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DAY JOURNAL")
                            .font(.footnote.bold())
                            .tracking(1)
                            .foregroundStyle(AppTheme.accent)

                        Text(AppFormatters.shortDate.string(from: summary.date))
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.ink)
                    }

                    Spacer()

                    Text(L10n.string("training.c3bdfc0865be", fallback: "{{value1}}件", values: [summary.totalLogCount.formatted()]))
                        .font(.footnote.bold())
                        .foregroundStyle(summary.totalLogCount > 0 ? AppTheme.ink : AppTheme.mutedInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            (summary.totalLogCount > 0 ? AppTheme.accent : AppTheme.mutedInk).opacity(0.16),
                            in: Capsule()
                        )
                }

                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        DailyJournalStat(
                            title: L10n.string("training.f7f7fa19af19", fallback: "身体"),
                            value: L10n.string("training.c3bdfc0865be", fallback: "{{value1}}件", values: [summary.bodyMetricEntries.count.formatted()]),
                            systemImage: "scalemass",
                            tint: AppTheme.blue
                        )

                        DailyJournalStat(
                            title: L10n.string("training.98bedebd5bd9", fallback: "食事"),
                            value: summary.meals.isEmpty ? L10n.string("training.593a06e5b8ca", fallback: "0件") : AppFormatters.calories(summary.totalCalories),
                            systemImage: "fork.knife",
                            tint: AppTheme.orange
                        )
                    }

                    GridRow {
                        DailyJournalStat(
                            title: L10n.string("training.7cbb717aa7f1", fallback: "写真"),
                            value: L10n.string("training.a6a1cc3a4bfc", fallback: "{{value1}}セット", values: [String(describing: summary.bodyPhotoSets.count)]),
                            systemImage: "camera",
                            tint: AppTheme.purple
                        )

                        DailyJournalStat(
                            title: L10n.string("training.d76c7025a2c6", fallback: "トレーニング"),
                            value: summary.workouts.isEmpty ? L10n.string("training.593a06e5b8ca", fallback: "0件") : AppFormatters.volume(summary.totalVolume, unit: weightUnit),
                            systemImage: "dumbbell",
                            tint: AppTheme.accent
                        )
                    }

                    GridRow {
                        DailyJournalStat(
                            title: L10n.string("training.17ca9a7a2745", fallback: "ジム訪問"),
                            value: L10n.string("training.b76f27bcd552", fallback: "{{value1}}回", values: [String(describing: summary.gymVisits.count)]),
                            systemImage: "mappin.and.ellipse",
                            tint: AppTheme.tertiaryAccent
                        )

                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    journalSectionHeader(L10n.string("training.b4ec903162bc", fallback: "身体測定"), systemImage: "scalemass", tint: AppTheme.blue)
                    if summary.bodyMetricEntries.isEmpty {
                        DailyJournalEmptyLine(text: L10n.string("training.04d1487f6347", fallback: "身体測定は未記録"))
                    } else {
                        ForEach(summary.bodyMetricEntries) { entry in
                            DailyJournalLine(
                                title: entry.kind.displayName,
                                detail: AppFormatters.metricValue(entry.value, unit: entry.kind.unit),
                                footnote: entry.note.isEmpty ? AppFormatters.shortDateTime.string(from: entry.recordedAt) : entry.note
                            )
                        }
                    }

                    journalSectionHeader(L10n.string("training.98bedebd5bd9", fallback: "食事"), systemImage: "fork.knife", tint: AppTheme.orange)
                    if summary.meals.isEmpty {
                        DailyJournalEmptyLine(text: L10n.string("training.2f46f8d9486a", fallback: "食事は未記録"))
                    } else {
                        Text(L10n.string("training.ed9a0cee2df7", fallback: "合計 {{value1}} / P {{value2}} F {{value3}} C {{value4}}", values: [String(describing: AppFormatters.calories(summary.totalCalories)), String(describing: AppFormatters.grams(summary.totalProtein)), String(describing: AppFormatters.grams(summary.totalFat)), String(describing: AppFormatters.grams(summary.totalCarbs))]))
                            .font(.footnote.bold())
                            .foregroundStyle(AppTheme.ink)

                        ForEach(summary.meals) { meal in
                            DailyJournalLine(
                                title: "\(meal.mealType.displayName) \(meal.name)",
                                detail: AppFormatters.calories(meal.calories),
                                footnote: meal.memo.isEmpty ? "P \(AppFormatters.grams(meal.protein)) / F \(AppFormatters.grams(meal.fat)) / C \(AppFormatters.grams(meal.carbs))" : meal.memo
                            )
                        }
                    }

                    journalSectionHeader(L10n.string("training.d7d8f0d93063", fallback: "体型写真"), systemImage: "camera", tint: AppTheme.purple)
                    if summary.bodyPhotoSets.isEmpty {
                        DailyJournalEmptyLine(text: L10n.string("training.82865627f395", fallback: "体型写真は未記録"))
                    } else {
                        ForEach(summary.bodyPhotoSets) { set in
                            let angles = set.angleEntries.map(\.angle.displayName).joined(separator: L10n.string("training.a2333d5b2d78", fallback: "・"))
                            let angleSummary = angles.isEmpty ? L10n.string("training.9fc01e5510fb", fallback: "写真なし") : angles
                            DailyJournalLine(
                                title: L10n.string("training.ccf4abb42a0e", fallback: "{{value1}}枚（{{value2}}）", values: [String(describing: set.photoEntries.count), String(describing: angleSummary)]),
                                detail: set.memo.isEmpty ? L10n.string("training.ecbfec695cfb", fallback: "撮影セット") : set.memo,
                                footnote: set.analysis?.summary ?? AppFormatters.shortDateTime.string(from: set.recordedAt)
                            )
                        }
                    }

                    journalSectionHeader(L10n.string("training.d76c7025a2c6", fallback: "トレーニング"), systemImage: "dumbbell", tint: AppTheme.accent)
                    if summary.workouts.isEmpty {
                        DailyJournalEmptyLine(text: L10n.string("training.e7426ea8f8c7", fallback: "トレーニングは未記録"))
                    } else {
                        ForEach(summary.workouts) { workout in
                            DailyJournalLine(
                                title: workout.title,
                                detail: AppFormatters.volume(workout.totalVolume, unit: weightUnit),
                                footnote: L10n.string("training.f3374f25ffb6", fallback: "達成率 {{value1}}", values: [String(describing: AppFormatters.percent(workout.achievementRate))])
                            )
                        }
                    }

                    journalSectionHeader(L10n.string("training.17ca9a7a2745", fallback: "ジム訪問"), systemImage: "mappin.and.ellipse", tint: AppTheme.tertiaryAccent)
                    if summary.gymVisits.isEmpty {
                        DailyJournalEmptyLine(text: L10n.string("training.be1f44fd2a48", fallback: "ジム訪問は未記録"))
                    } else {
                        ForEach(summary.gymVisits) { visit in
                            DailyJournalLine(
                                title: L10n.string("training.89e769e459b9", fallback: "ジム到着"),
                                detail: visit.departedAt.map { formatVisitDuration(from: visit.arrivedAt, to: $0) } ?? L10n.string("training.57ea66302bcf", fallback: "滞在中"),
                                footnote: AppFormatters.shortDateTime.string(from: visit.arrivedAt)
                            )
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("dailyJournalSummary")
    }

    private func journalSectionHeader(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)
        }
        .padding(.top, 2)
    }
}

private func formatVisitDuration(from start: Date, to end: Date) -> String {
    let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
    if minutes < 60 {
        return L10n.string("training.2c02454ec433", fallback: "{{value1}}分", values: [String(describing: minutes)])
    }
    return L10n.string("training.bb1a78b0b78c", fallback: "{{value1}}時間{{value2}}分", values: [String(describing: minutes / 60), String(describing: minutes % 60)])
}

private struct DailyJournalStat: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

private struct DailyJournalLine: View {
    let title: String
    let detail: String
    let footnote: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.bold())
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(2)
            }

            Spacer()

            Text(detail)
                .font(.footnote.bold())
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct DailyJournalEmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(AppTheme.mutedInk)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var appStore: AppStore

    let session: WorkoutSession

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.headline)
                        Text(AppFormatters.shortDateTime.string(from: session.startedAt))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    Spacer()

                    Text(session.outdoorCardio == nil ? AppFormatters.percent(session.achievementRate) : cardioGoalProgress)
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.accent)
                }

                if let cardio = session.outdoorCardio {
                    HStack(spacing: 10) {
                        Label(AppFormatters.distance(kilometers: cardio.distanceKilometers), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        if let pace = cardio.averagePaceSecondsPerKilometer {
                            Label(AppFormatters.pace(secondsPerKilometer: pace), systemImage: "speedometer")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                } else {
                    HStack(spacing: 10) {
                        Label(AppFormatters.volume(session.totalVolume, unit: appStore.userProfile.weightUnit), systemImage: "scalemass")
                        Label(L10n.string("training.70d17961dda6", fallback: "{{value1}}種目", values: [String(describing: session.exercises.count)]), systemImage: "dumbbell")
                        Label("\(session.completedPlannedSetCount)/\(session.plannedSetCount)", systemImage: "checklist")
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)

                    Text(L10n.string("training.7f60357273d2", fallback: "目標差 {{value1}}", values: [String(describing: AppFormatters.signedVolume(session.volumeDelta, unit: appStore.userProfile.weightUnit))]))
                        .font(.footnote.bold())
                        .foregroundStyle(session.volumeDelta >= 0 ? AppTheme.positive : AppTheme.orange)
                }

                VStack(spacing: 5) {
                    ForEach(session.exercises) { exercise in
                        HStack(spacing: 8) {
                            Text(exercise.exercise.name)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(exercise.isSkipped ? L10n.string("training.17135f0f1ac6", fallback: "スキップ") : L10n.string("training.7ccbd585d5ee", fallback: "{{value1}}セット・{{value2}}回", values: [String(describing: exercise.completedSetCount), String(describing: exercise.completedRepCount)]))
                                .foregroundStyle(exercise.isSkipped ? AppTheme.mutedInk : AppTheme.ink)
                        }
                        .accessibilityIdentifier("historyExerciseResult-\(exercise.sortOrder)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .padding(.vertical, 3)
    }

    private var cardioGoalProgress: String {
        guard let cardio = session.outdoorCardio else { return "-" }
        let duration = session.sensorSummary?.durationSeconds
            ?? max(0, (session.endedAt ?? Date()).timeIntervalSince(session.startedAt))
        return cardio.progress(elapsedSeconds: duration).map(AppFormatters.percent) ?? "-"
    }
}

#Preview {
    HistoryListView()
        .environmentObject(AppStore())
}
