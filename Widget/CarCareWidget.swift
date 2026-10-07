import WidgetKit
import SwiftUI
import CarCareCore

@main
struct CarCareWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextDueWidget()
    }
}

struct NextDueEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct NextDueProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextDueEntry {
        NextDueEntry(date: Date(), snapshot: WidgetSnapshot(generatedAt: Date(), dueDay: Date(),
                                                            dueDayText: "20 листопада", itemsText: "Масло + фільтр",
                                                            overdueText: "", emptyText: ""))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextDueEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : NextDueEntry(date: Date(), snapshot: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextDueEntry>) -> Void) {
        let entry = NextDueEntry(date: Date(), snapshot: load())
        // The app reloads timelines on every data change; also refresh after midnight.
        let tomorrow = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }

    private func load() -> WidgetSnapshot? {
        let group = Bundle.main.object(forInfoDictionaryKey: "CCAppGroup") as? String ?? "group.com.carcarelog.app"
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: dir.appendingPathComponent(WidgetSnapshot.fileName)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

struct NextDueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextDue", provider: NextDueProvider()) { entry in
            NextDueView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Self.url(for: entry))
        }
        .configurationDisplayName("CarCare Log")
        .description("Найближче обслуговування · Next service")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    /// Opens "Log service" with the items of the nearest due day, or just Home.
    static func url(for entry: NextDueEntry) -> URL? {
        guard let ids = entry.snapshot?.itemIDs, !ids.isEmpty else { return URL(string: "carcarelog://upcoming") }
        return URL(string: "carcarelog://log?items=" + ids.map(\.uuidString).joined(separator: ","))
    }
}

struct NextDueView: View {
    let entry: NextDueEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver.fill")
                Text("CarCare Log")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            if let s = entry.snapshot, s.dueDay != nil || !s.overdueText.isEmpty {
                if !s.overdueText.isEmpty {
                    Text(s.overdueText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                if s.dueDay != nil {
                    Text(s.dueDayText)
                        .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(s.itemsText)
                        .font(.subheadline)
                        .lineLimit(family == .systemSmall ? 3 : 2)
                }
            } else {
                Text(entry.snapshot?.emptyText ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
