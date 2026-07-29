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
                    ContentUnavailableView {
                        Label("履歴はまだありません", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("身体・食事・写真・トレーニングを記録すると、ここから日別にまとめて見返せます。")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            WorkoutCalendarView(
                                displayedMonth: $displayedMonth,
                                selectedDate: $selectedDate,
                                summaries: dailySummaries
                            )

                            if let selectedDate {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("選択日のまとめ")
                                        .font(.caption.bold())
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
                                        Button("すべて") {
                                            selectedDate = nil
                                        }
                                        .font(.caption.bold())
                                    }
                                }

                                if visibleSessions.isEmpty {
                                    Text(selectedDate == nil ? "トレーニング履歴はありません" : "この日のトレーニングはありません")
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
                                        Button("削除", role: .destructive) {
                                            pendingDeleteSession = session
                                        }
                                    }
                                }
                            }

                            if !appStore.workoutHistory.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("分析")
                                            .font(.headline)
                                            .foregroundStyle(AppTheme.ink)
                                        Text("蓄積した記録を期間・種目・センサー別に確認")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.mutedInk)
                                    }

                                    VStack(spacing: 0) {
                                        NavigationLink {
                                            WeeklyVolumeView()
                                        } label: {
                                            HistoryAnalyticsLink(
                                                title: "週次ボリューム分析",
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
                                                title: "種目別履歴",
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
                                                title: "Watchセンサー分析",
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
            .navigationTitle("履歴")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WorkoutSession.self) { session in
                HistoryDetailView(session: session)
            }
            .confirmationDialog(
                "この履歴を削除しますか？",
                isPresented: Binding(
                    get: { pendingDeleteSession != nil },
                    set: { if !$0 { pendingDeleteSession = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let pendingDeleteSession {
                        appStore.deleteWorkout(pendingDeleteSession)
                    }
                    pendingDeleteSession = nil
                }
                Button("キャンセル", role: .cancel) {
                    pendingDeleteSession = nil
                }
            }
        }
    }

    private var selectedDateTitle: String {
        guard let selectedDate else {
            return "すべての記録"
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
                .font(.caption.bold())
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

    var totalLogCount: Int {
        workouts.count + bodyMetricEntries.count + meals.count + bodyPhotos.count + gymVisits.count
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
    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        let days = calendarDays

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROGRESS CALENDAR")
                        .font(.caption.bold())
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
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("前の月")

                    Button {
                        moveMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("次の月")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.ink)
            }

            Grid(horizontalSpacing: 6, verticalSpacing: 8) {
                GridRow {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption.bold())
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
                    .font(.caption2.bold())
                    .foregroundStyle(kind.tint)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("記録種別の凡例")
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
        displayedMonth.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "ja_JP")))
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
        case .workout: "筋トレ"
        case .bodyMetric: "身体"
        case .meal: "食事"
        case .bodyPhoto: "写真"
        case .gymVisit: "ジム"
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
        case .bodyPhoto: summary?.bodyPhotos.count ?? 0
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
        .accessibilityIdentifier("historyCalendarDay-\(accessibilityDateID)")
    }

    private var foregroundColor: Color {
        if isSelected {
            return AppTheme.onAccent
        }

        return day.isInDisplayedMonth ? AppTheme.ink : AppTheme.mutedInk.opacity(0.45)
    }
    private var accessibilityLabel: String {
        if totalLogCount == 0 {
            return "\(dayNumber)日 記録なし"
        }

        let details = recordKinds
            .map { "\($0.title)\($0.count(in: summary))件" }
            .joined(separator: "、")
        return "\(dayNumber)日 \(details)"
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
                            .font(.caption.bold())
                            .tracking(1)
                            .foregroundStyle(AppTheme.accent)

                        Text(AppFormatters.shortDate.string(from: summary.date))
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.ink)
                    }

                    Spacer()

                    Text("\(summary.totalLogCount)件")
                        .font(.caption.bold())
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
                            title: "身体",
                            value: "\(summary.bodyMetricEntries.count)件",
                            systemImage: "scalemass",
                            tint: AppTheme.blue
                        )

                        DailyJournalStat(
                            title: "食事",
                            value: summary.meals.isEmpty ? "0件" : AppFormatters.calories(summary.totalCalories),
                            systemImage: "fork.knife",
                            tint: AppTheme.orange
                        )
                    }

                    GridRow {
                        DailyJournalStat(
                            title: "写真",
                            value: "\(summary.bodyPhotos.count)件",
                            systemImage: "camera",
                            tint: AppTheme.purple
                        )

                        DailyJournalStat(
                            title: "トレーニング",
                            value: summary.workouts.isEmpty ? "0件" : AppFormatters.volume(summary.totalVolume, unit: weightUnit),
                            systemImage: "dumbbell",
                            tint: AppTheme.accent
                        )
                    }

                    GridRow {
                        DailyJournalStat(
                            title: "ジム訪問",
                            value: "\(summary.gymVisits.count)回",
                            systemImage: "mappin.and.ellipse",
                            tint: AppTheme.tertiaryAccent
                        )

                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    journalSectionHeader("身体測定", systemImage: "scalemass", tint: AppTheme.blue)
                    if summary.bodyMetricEntries.isEmpty {
                        DailyJournalEmptyLine(text: "身体測定は未記録")
                    } else {
                        ForEach(summary.bodyMetricEntries) { entry in
                            DailyJournalLine(
                                title: entry.kind.displayName,
                                detail: AppFormatters.metricValue(entry.value, unit: entry.kind.unit),
                                footnote: entry.note.isEmpty ? AppFormatters.shortDateTime.string(from: entry.recordedAt) : entry.note
                            )
                        }
                    }

                    journalSectionHeader("食事", systemImage: "fork.knife", tint: AppTheme.orange)
                    if summary.meals.isEmpty {
                        DailyJournalEmptyLine(text: "食事は未記録")
                    } else {
                        Text("合計 \(AppFormatters.calories(summary.totalCalories)) / P \(AppFormatters.grams(summary.totalProtein)) F \(AppFormatters.grams(summary.totalFat)) C \(AppFormatters.grams(summary.totalCarbs))")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.ink)

                        ForEach(summary.meals) { meal in
                            DailyJournalLine(
                                title: "\(meal.mealType.displayName) \(meal.name)",
                                detail: AppFormatters.calories(meal.calories),
                                footnote: meal.memo.isEmpty ? "P \(AppFormatters.grams(meal.protein)) / F \(AppFormatters.grams(meal.fat)) / C \(AppFormatters.grams(meal.carbs))" : meal.memo
                            )
                        }
                    }

                    journalSectionHeader("体型写真", systemImage: "camera", tint: AppTheme.purple)
                    if summary.bodyPhotos.isEmpty {
                        DailyJournalEmptyLine(text: "体型写真は未記録")
                    } else {
                        ForEach(summary.bodyPhotos) { photo in
                            DailyJournalLine(
                                title: photo.angle.displayName,
                                detail: photo.memo.isEmpty ? "メモなし" : photo.memo,
                                footnote: photo.aiComment?.summary ?? AppFormatters.shortDateTime.string(from: photo.recordedAt)
                            )
                        }
                    }

                    journalSectionHeader("トレーニング", systemImage: "dumbbell", tint: AppTheme.accent)
                    if summary.workouts.isEmpty {
                        DailyJournalEmptyLine(text: "トレーニングは未記録")
                    } else {
                        ForEach(summary.workouts) { workout in
                            DailyJournalLine(
                                title: workout.title,
                                detail: AppFormatters.volume(workout.totalVolume, unit: weightUnit),
                                footnote: "達成率 \(AppFormatters.percent(workout.achievementRate))"
                            )
                        }
                    }

                    journalSectionHeader("ジム訪問", systemImage: "mappin.and.ellipse", tint: AppTheme.tertiaryAccent)
                    if summary.gymVisits.isEmpty {
                        DailyJournalEmptyLine(text: "ジム訪問は未記録")
                    } else {
                        ForEach(summary.gymVisits) { visit in
                            DailyJournalLine(
                                title: "ジム到着",
                                detail: visit.departedAt.map { formatVisitDuration(from: visit.arrivedAt, to: $0) } ?? "滞在中",
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
        return "\(minutes)分"
    }
    return "\(minutes / 60)時間\(minutes % 60)分"
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
                    .font(.caption)
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
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(2)
            }

            Spacer()

            Text(detail)
                .font(.caption.bold())
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
            .font(.caption)
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
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    Spacer()

                    Text(AppFormatters.percent(session.achievementRate))
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.accent)
                }

                HStack(spacing: 10) {
                    Label(AppFormatters.volume(session.totalVolume, unit: appStore.userProfile.weightUnit), systemImage: "scalemass")
                    Label("\(session.exercises.count)種目", systemImage: "dumbbell")
                    Label("\(session.completedPlannedSetCount)/\(session.plannedSetCount)", systemImage: "checklist")
                }
                .font(.caption)
                .foregroundStyle(AppTheme.mutedInk)

                Text("目標差 \(AppFormatters.signedVolume(session.volumeDelta, unit: appStore.userProfile.weightUnit))")
                    .font(.caption.bold())
                    .foregroundStyle(session.volumeDelta >= 0 ? AppTheme.positive : AppTheme.orange)

                VStack(spacing: 5) {
                    ForEach(session.exercises) { exercise in
                        HStack(spacing: 8) {
                            Text(exercise.exercise.name)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(exercise.isSkipped ? "スキップ" : "\(exercise.completedSetCount)セット・\(exercise.completedRepCount)回")
                                .foregroundStyle(exercise.isSkipped ? AppTheme.mutedInk : AppTheme.ink)
                        }
                        .accessibilityIdentifier("historyExerciseResult-\(exercise.sortOrder)")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    HistoryListView()
        .environmentObject(AppStore())
}
