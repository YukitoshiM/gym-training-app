import SwiftUI

struct HistoryListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?

    private var visibleSessions: [WorkoutSession] {
        guard let selectedDate else {
            return appStore.workoutHistory
        }

        return appStore.workoutHistory.filter {
            Calendar.current.isDate($0.startedAt, inSameDayAs: selectedDate)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appStore.workoutHistory.isEmpty {
                    ContentUnavailableView {
                        Label("履歴はまだありません", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("ワークアウトを完了すると、ここから過去の重量・回数を見返せます。")
                    }
                } else {
                    List {
                        Section {
                            WorkoutCalendarView(
                                displayedMonth: $displayedMonth,
                                selectedDate: $selectedDate,
                                sessions: appStore.workoutHistory
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }

                        Section {
                            if visibleSessions.isEmpty {
                                Text("この日の記録はありません")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 18)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }

                            ForEach(visibleSessions) { session in
                                NavigationLink(value: session) {
                                    HistoryRow(session: session)
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .accessibilityIdentifier("historyRow-\(session.title)")
                            }
                            .onDelete(perform: deleteVisibleSessions)
                        } header: {
                            HStack {
                                Text(selectedDateTitle)
                                Spacer()
                                if selectedDate != nil {
                                    Button("すべて") {
                                        selectedDate = nil
                                    }
                                    .font(.caption.bold())
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(TrainingBackground())
                }
            }
            .navigationTitle("履歴")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WorkoutSession.self) { session in
                HistoryDetailView(session: session)
            }
        }
    }

    private var selectedDateTitle: String {
        guard let selectedDate else {
            return "すべての記録"
        }

        return AppFormatters.shortDate.string(from: selectedDate)
    }

    private func deleteVisibleSessions(at offsets: IndexSet) {
        for offset in offsets {
            appStore.deleteWorkout(visibleSessions[offset])
        }
    }
}

private struct WorkoutCalendarView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date?

    let sessions: [WorkoutSession]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GYM CALENDAR")
                        .font(.caption.bold())
                        .tracking(1)
                        .foregroundStyle(AppTheme.accent)

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

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(calendarDays) { day in
                    CalendarDayButton(
                        day: day,
                        sessionCount: sessionCount(on: day.date),
                        isSelected: selectedDate.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false
                    ) {
                        selectedDate = day.date
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: AppTheme.ink.opacity(0.08), radius: 14, x: 0, y: 8)
        .accessibilityIdentifier("historyCalendar")
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

    private func sessionCount(on date: Date) -> Int {
        sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }.count
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

private struct CalendarDayButton: View {
    let day: CalendarDay
    let sessionCount: Int
    let isSelected: Bool
    let action: () -> Void

    private var dayNumber: Int {
        Calendar.current.component(.day, from: day.date)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(dayNumber)")
                    .font(.subheadline.weight(sessionCount > 0 ? .bold : .regular))

                Circle()
                    .fill(sessionCount > 0 ? AppTheme.accent : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isSelected ? AppTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("historyCalendarDay-\(accessibilityDateID)")
    }

    private var foregroundColor: Color {
        if isSelected {
            return AppTheme.ink
        }

        return day.isInDisplayedMonth ? AppTheme.ink : AppTheme.mutedInk.opacity(0.45)
    }
    private var accessibilityLabel: String {
        if sessionCount == 0 {
            return "\(dayNumber)日 記録なし"
        }

        return "\(dayNumber)日 \(sessionCount)件の記録"
    }

    private var accessibilityDateID: String {
        Self.identifierFormatter.string(from: day.date)
    }

    private static let identifierFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct HistoryRow: View {
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
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(AppFormatters.percent(session.achievementRate))
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.accent)
                }

                HStack(spacing: 10) {
                    Label(AppFormatters.volume(session.totalVolume), systemImage: "scalemass")
                    Label("\(session.exercises.count)種目", systemImage: "dumbbell")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(session.exercises.map { $0.exercise.name }.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    HistoryListView()
        .environmentObject(AppStore())
}
