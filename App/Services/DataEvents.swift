import Foundation
import UIKit
import SwiftData
import UserNotifications
import WidgetKit
import CarCareCore

/// Single place that reacts to data changes: saves, then refreshes reminders, the app icon badge and the widget.
/// Called on launch, on every return to the foreground and after every edit.
@MainActor
enum DataEvents {
    static func changed(_ context: ModelContext) {
        do { try context.save() } catch { print("Save failed: \(error)") }
        refreshDerived(context)
    }

    static func appDidBecomeActive(_ context: ModelContext) {
        AutoBackup.runIfNeeded(context)
        refreshDerived(context)
    }

    private static func refreshDerived(_ context: ModelContext) {
        let snapshot = SnapshotBuilder.fetch(context)
        NotificationActions.registerCategories()
        ReminderService.reschedule(snapshot: snapshot, options: .init(settings: AppSettings.shared))
        WidgetOutput.write(snapshot: snapshot)
    }
}

/// Local notifications only. iOS keeps at most 64 pending ones, so we schedule the soonest 50 reminders,
/// up to 3 odometer nudges and 1 backup reminder, and rebuild them every time. "Remind tomorrow" copies
/// (snooze-…) are kept.
enum ReminderService {
    static let duePrefix = "due-"
    static let nudgePrefix = "odometer-"
    static let backupID = "backup-reminder"

    /// What the user turned on in Settings → Notifications.
    struct Options {
        var enabled = true
        var service = true
        var odometerDays = OdometerRules.nudgeIntervalDays
        var backup = true
        var hour = ReminderPlanner.fireHour
        var minute = 0
        var leadTime: ReminderLeadTime = .oneWeek
        var lastBackup: Date?

        init() {}

        init(settings s: AppSettings) {
            enabled = s.notificationsEnabled
            service = s.notifyService
            odometerDays = s.notifyOdometer ? s.odometerDays : 0
            backup = s.notifyBackup
            hour = s.notifyHour
            minute = s.notifyMinute
            leadTime = s.leadTime
            lastBackup = s.lastBackup
        }
    }

    static func reschedule(snapshot: DataSnapshot, options o: Options) {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let now = Date()
        let statuses = ForecastEngine.statuses(for: snapshot, today: now, calendar: calendar)
        let overdueCount = statuses.values.filter { $0.forecast?.isOverdue == true }.count
        let names = Dictionary(snapshot.items.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        var requests: [UNNotificationRequest] = []
        if o.enabled && o.service {
            let plan = ReminderPlanner.plan(statuses: statuses, items: snapshot.items, leadTime: o.leadTime,
                                            now: now, calendar: calendar, hour: o.hour, minute: o.minute)
            for reminder in plan {
                let content = UNMutableNotificationContent()
                let list = reminder.itemIDs.compactMap { names[$0] }.joined(separator: ", ")
                if reminder.isAdvance {
                    content.title = L10n.t("notif.dueTitle")
                    content.body = L10n.f("notif.dueBody", Fmt.date(reminder.dueDay), list)
                } else {
                    content.title = L10n.t("notif.todayTitle")
                    content.body = list
                }
                content.sound = .default
                content.categoryIdentifier = NotificationActions.dueCategory
                content.userInfo = ["items": reminder.itemIDs.map(\.uuidString)]
                requests.append(request(id: reminder.identifier, content: content, date: reminder.fireDate,
                                        calendar: calendar))
            }
        }
        if o.enabled {
            let nudges = OdometerRules.nudgeDates(readings: snapshot.odometerReadings, entries: snapshot.entries,
                                                  now: now, calendar: calendar, hour: o.hour, minute: o.minute,
                                                  intervalDays: o.odometerDays)
            for (index, date) in nudges.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = L10n.t("notif.odometerTitle")
                content.body = L10n.t("notif.odometerBody")
                content.sound = .default
                content.categoryIdentifier = NotificationActions.odometerCategory
                requests.append(request(id: "\(nudgePrefix)\(index)", content: content, date: date, calendar: calendar))
            }
        }
        if o.enabled && o.backup && !snapshot.entries.isEmpty,
           let fire = backupReminderDate(lastBackup: o.lastBackup, now: now, hour: o.hour, minute: o.minute,
                                         calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = L10n.t("notif.backupTitle")
            content.body = L10n.t("notif.backupBody")
            content.sound = .default
            requests.append(request(id: backupID, content: content, date: fire, calendar: calendar))
        }

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            center.setBadgeCount(o.enabled ? overdueCount : 0) { _ in }
            center.getPendingNotificationRequests { pending in
                let ours = pending.map(\.identifier).filter {
                    $0.hasPrefix(duePrefix) || $0.hasPrefix(nudgePrefix) || $0 == backupID
                        || (!o.enabled && $0.hasPrefix("snooze-"))
                }
                center.removePendingNotificationRequests(withIdentifiers: ours)
                for r in requests { center.add(r) }
            }
        }
    }

    /// 14 days after the last backup (or tomorrow if that already passed), at the notification time.
    static func backupReminderDate(lastBackup: Date?, now: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        let base = lastBackup.flatMap { calendar.date(byAdding: .day, value: AutoBackupDays.remind, to: $0) } ?? now
        var day = calendar.startOfDay(for: base)
        if let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), fire > now { return fire }
        day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}

/// Shared with AutoBackup (kept outside the main actor for the reminder planner).
enum AutoBackupDays {
    static let remind = 14
}

extension ReminderService {
    static func request(id: String, content: UNNotificationContent, date: Date,
                        calendar: Calendar) -> UNNotificationRequest {
        // Date components without a time zone fire at 11:00 in whatever time zone the phone is in.
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}

/// Buttons on notifications: "Mark done" and "Remind tomorrow" on service reminders, "Enter odometer" on nudges.
/// Dismissing a notification changes nothing: the next reminder comes as planned and Home keeps showing it.
enum NotificationActions {
    static let dueCategory = "DUE"
    static let odometerCategory = "ODOMETER"
    static let markDone = "MARK_DONE"
    static let snooze = "SNOOZE"
    static let enterOdometer = "ENTER_ODOMETER"

    static func registerCategories() {
        let done = UNNotificationAction(identifier: markDone, title: L10n.t("notif.actionDone"), options: [.foreground])
        let later = UNNotificationAction(identifier: snooze, title: L10n.t("notif.actionSnooze"), options: [])
        let odometer = UNNotificationAction(identifier: enterOdometer, title: L10n.t("notif.actionOdometer"),
                                            options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: dueCategory, actions: [done, later], intentIdentifiers: []),
            UNNotificationCategory(identifier: odometerCategory, actions: [odometer], intentIdentifiers: [])
        ])
    }

    @MainActor
    static func handle(_ response: UNNotificationResponse) {
        let content = response.notification.request.content
        let ids = (content.userInfo["items"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
        let router = Router.shared
        switch (content.categoryIdentifier, response.actionIdentifier) {
        case (dueCategory, markDone):
            router.tab = .home
            router.open(.logService(ids))
        case (dueCategory, snooze):
            scheduleTomorrow(content)
        case (odometerCategory, enterOdometer), (odometerCategory, UNNotificationDefaultActionIdentifier):
            router.tab = .home
            router.open(.odometer)
        default:
            router.tab = .home
        }
    }

    /// "Remind tomorrow": the same notification tomorrow at 11:00 local time.
    private static func scheduleTomorrow(_ original: UNNotificationContent) {
        let calendar = Calendar.current
        guard let content = original.mutableCopy() as? UNMutableNotificationContent,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())),
              let fire = calendar.date(bySettingHour: AppSettings.shared.notifyHour,
                                       minute: AppSettings.shared.notifyMinute, second: 0, of: tomorrow)
        else { return }
        UNUserNotificationCenter.current().add(
            ReminderService.request(id: "snooze-" + UUID().uuidString, content: content, date: fire, calendar: calendar))
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationActions.registerCategories()
        return true
    }

    /// Show reminders even when the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            NotificationActions.handle(response)
            completionHandler()
        }
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
        // Lock screen: the single most urgent item.
        let now = Date()
        let statuses = ForecastEngine.statuses(for: snapshot, today: now, calendar: Fmt.calendar)
        let current = snapshot.currentOdometerKm
        var nextTitle = "", nextValue = "", nextFraction = 0.0
        if let top = ForecastEngine.urgencySorted(snapshot.activeItems, statuses: statuses).first,
           let f = statuses[top.id]?.forecast {
            nextTitle = top.name
            nextValue = ForecastText.short(kind: top.kind, forecast: f, currentKm: current, today: now)
            nextFraction = ForecastEngine.wear(item: top, forecast: f, entries: snapshot.entries,
                                               currentOdometerKm: current, today: now) ?? 0
        }
        let widget = WidgetSnapshot(
            generatedAt: Date(),
            dueDay: summary.dueDay,
            dueDayText: summary.dueDay.map { Fmt.monthYear($0) } ?? "",
            itemsText: summary.itemNames.joined(separator: " + "),
            overdueText: summary.overdueNames.isEmpty ? "" : L10n.f("widget.overdue", summary.overdueNames.count),
            emptyText: L10n.t("widget.empty"),
            itemIDs: summary.itemIDs,
            nextTitle: nextTitle,
            nextValue: nextValue,
            nextFraction: nextFraction
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
