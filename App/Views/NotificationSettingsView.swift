import SwiftUI
import UserNotifications

/// Settings → Notifications: master switch, what to notify about, time (wheel, minutes), how early, and how often
/// to ask for the odometer (wheel, 1-day steps, or off).
struct NotificationSettingsView: View {
    var body: some View {
        Form {
            NotificationFields()
        }
        .navigationTitle(L10n.t("settings.notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }
}
