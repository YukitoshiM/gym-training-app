import SwiftUI
import WidgetKit

private struct GymWidgetEntry: TimelineEntry {
    let date: Date
}

private struct GymWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> GymWidgetEntry {
        GymWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (GymWidgetEntry) -> Void) {
        completion(GymWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GymWidgetEntry>) -> Void) {
        let entry = GymWidgetEntry(date: Date())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: entry.date)
            ?? entry.date.addingTimeInterval(3_600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private struct GymTrainingWatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GymWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 1) {
                    Image(systemName: "dumbbell.fill")
                        .font(.headline)
                    Text("READY")
                        .font(.system(size: 8, weight: .bold))
                }
            case .accessoryInline:
                Label("Gym: 次のセッションへ", systemImage: "dumbbell.fill")
            default:
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.title3)
                        .foregroundStyle(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("GYM READY")
                            .font(.caption.bold())
                        Text(entry.date, format: .dateTime.month().day().weekday(.abbreviated))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .containerBackground(.black, for: .widget)
    }
}

@main
struct GymTrainingWatchWidget: Widget {
    let kind = "GymTrainingWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GymWidgetProvider()) { entry in
            GymTrainingWatchWidgetView(entry: entry)
        }
        .configurationDisplayName("BodyMode Session")
        .description("次のトレーニングへすぐ戻れます。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
