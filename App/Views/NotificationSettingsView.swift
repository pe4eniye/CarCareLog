import SwiftUI
import SwiftData
import UserNotifications
import CarCareCore

/// Settings → Notifications: master switch, what to notify about, time (wheel, minutes), how early, and how often
/// to ask for the odometer (wheel, 1-day steps, or off).
struct NotificationSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context
    @State private var denied = false

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings.notifyHour, minute: settings.notifyMinute, second: 0,
                                      of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.notifyHour = c.hour ?? ReminderPlanner.fireHour
                settings.notifyMinute = c.minute ?? 0
                refresh()
            }
        )
    }

    var body: some View {
        Form {
            if denied {
                Section {
                    Banner(icon: "bell.slash", text: L10n.t("notify.denied"), style: .warning,
                           actionTitle: L10n.t("notify.openSettings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            Section {
                Toggle(L10n.t("notify.all"), isOn: binding(\.notificationsEnabled)).frame(minHeight: 44)
                    .fontWeight(.semibold)
                if settings.notificationsEnabled {
                    Toggle(L10n.t("notify.service"), isOn: binding(\.notifyService)).frame(minHeight: 44)
                    Toggle(L10n.t("notify.odometer"), isOn: binding(\.notifyOdometer)).frame(minHeight: 44)
                    Toggle(L10n.t("notify.backup"), isOn: binding(\.notifyBackup)).frame(minHeight: 44)
                }
            } footer: {
                Text(L10n.t(settings.notificationsEnabled ? "notify.footer" : "notify.offFooter"))
            }

            if settings.notificationsEnabled {
                Section(L10n.t("notify.time")) {
                    DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                if settings.notifyService {
                    Section(L10n.t("notify.leadTime")) {
                        Picker(L10n.t("settings.leadTime"), selection: binding(\.leadTimeDays)) {
                            ForEach(ReminderLeadTime.allCases) { lead in
                                Text(SettingsView.leadTimeTitle(lead)).tag(lead.rawValue)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }

            Section {
                Picker(L10n.t("notify.odometerEvery"), selection: binding(\.odometerDays)) {
                    Text(L10n.t("notify.odometerOff")).tag(0)
                    ForEach(1...60, id: \.self) { d in
                        Text(d == 1 ? L10n.t("notify.everyDay") : L10n.f("notify.everyDays", d)).tag(d)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 130)
            } header: {
                Text(L10n.t("notify.odometerEvery"))
            } footer: {
                Text(L10n.t("notify.odometerFooter"))
            }
        }
        .navigationTitle(L10n.t("settings.notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            denied = status == .denied
            if status == .notDetermined {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }

    /// Binding to a setting that reschedules notifications when changed.
    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0; refresh() })
    }

    private func refresh() {
        DataEvents.changed(context)
    }
}
