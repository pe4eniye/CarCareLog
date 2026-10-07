import Foundation
import SwiftData
import UserNotifications
import WidgetKit
import CarCareCore

/// Single place that reacts to data changes: saves, then refreshes reminders and the widget snapshot.
/// Called on launch, on every return to the foreground and after every edit.
@MainActor
enum DataEvents {
    static func changed(_ context: ModelContext) {
        do { try context.save() } catch { print("Save failed: \(error)") }
        refreshDerived(context)
    }

    static func appDidBecomeActive(_ context: ModelContext) {
        refreshDerived(context)
    }

    private static func refreshDerived(_ context: ModelContext) {
        let snapshot = SnapshotBuilder.fetch(context)
        ReminderService.reschedule(snapshot: snapshot, leadTime: AppSettings.shared.leadTime)
        WidgetOutput.write(snapshot: snapshot)
    }
}

/// Local notifications only. iOS keeps at most 64 pending ones, so we schedule the soonest 50 due days
/// plus 3 odometer nudges, and rebuild the whole set every time.
enum ReminderService {
    static let duePrefix = "due-"
    static let nudgePrefix = "odometer-"

    static func reschedule(snapshot: DataSnapshot, leadTime: ReminderLeadTime) {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let now = Date()
        let statuses = ForecastEngine.statuses(for: snapshot, today: now, calendar: calendar)
        let plan = ReminderPlanner.plan(statuses: statuses, items: snapshot.items, leadTime: leadTime,
                                        now: now, calendar: calendar)
        let nudges = OdometerRules.nudgeDates(readings: snapshot.odometerReadings, now: now, calendar: calendar)
        let names = Dictionary(snapshot.items.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        var requests: [UNNotificationRequest] = []
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = L10n.t("notif.dueTitle")
            content.body = L10n.f("notif.dueBody", Fmt.date(reminder.dueDay),
                                  reminder.itemIDs.compactMap { names[$0] }.joined(separator: ", "))
            content.sound = .default
            requests.append(request(id: reminder.identifier, content: content, date: reminder.fireDate, calendar: calendar))
        }
        for (index, date) in nudges.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = L10n.t("notif.odometerTitle")
            content.body = L10n.t("notif.odometerBody")
            content.sound = .default
            requests.append(request(id: "\(nudgePrefix)\(index)", content: content, date: date, calendar: calendar))
        }

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            center.removeAllPendingNotificationRequests()
            for r in requests { center.add(r) }
        }
    }

    private static func request(id: String, content: UNNotificationContent, date: Date,
                                calendar: Calendar) -> UNNotificationRequest {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}

/// Writes the widget's JSON snapshot into the App Group container and asks WidgetKit to reload.
enum WidgetOutput {
    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "CCAppGroup") as? String ?? "group.com.carcarelog.app"
    }

    static func write(snapshot: DataSnapshot) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return // No App Group (e.g. unsigned simulator build): nothing to share.
        }
        let summary = WidgetSummary.make(snapshot: snapshot, today: Date(), calendar: Calendar.current)
        let widget = WidgetSnapshot(
            generatedAt: Date(),
            dueDay: summary.dueDay,
            dueDayText: summary.dueDay.map(Fmt.shortDate) ?? "",
            itemsText: summary.itemNames.joined(separator: " + "),
            overdueText: summary.overdueNames.isEmpty ? "" : L10n.f("widget.overdue", summary.overdueNames.count),
            emptyText: L10n.t("widget.empty")
        )
        do {
            let data = try JSONEncoder().encode(widget)
            try data.write(to: dir.appendingPathComponent(WidgetSnapshot.fileName), options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Widget snapshot failed: \(error)")
        }
    }
}
