import SwiftUI
import SwiftData
import UserNotifications
import CarCareCore

/// Language, theme, theme color and currency: the same controls in Settings and in onboarding.
struct AppearanceFields: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Picker(L10n.t("settings.language"), selection: $settings.language) {
            ForEach(L10n.choices, id: \.code) { Text($0.name).tag($0.code) }
        }
        .frame(minHeight: 44)
        Picker(L10n.t("settings.currency"), selection: $settings.currencyRaw) {
            Text("₴ " + L10n.t("currency.uah")).tag(Currency.uah.rawValue)
            Text("$ " + L10n.t("currency.usd")).tag(Currency.usd.rawValue)
            Text("€ " + L10n.t("currency.eur")).tag(Currency.eur.rawValue)
        }
        .frame(minHeight: 44)
        Picker(L10n.t("settings.theme"), selection: $settings.theme) {
            Text(L10n.t("settings.themeLight")).tag("light")
            Text(L10n.t("settings.themeDark")).tag("dark")
            Text(L10n.t("settings.themeSystem")).tag("system")
        }
        .frame(minHeight: 44)
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("settings.accent"))
            HStack(spacing: 14) {
                ForEach(AccentTheme.allCases) { theme in
                    Button {
                        settings.accentRaw = theme.rawValue
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Circle().fill(theme.color).frame(width: 32, height: 32)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2).padding(2)
                                .opacity(settings.accent == theme ? 1 : 0))
                            .overlay(Circle().strokeBorder(theme.color, lineWidth: 2).padding(-3)
                                .opacity(settings.accent == theme ? 1 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t(theme.titleKey))
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// What to notify about, when, how early, and how often to ask for the odometer: the same sections in
/// Settings → Notifications and in onboarding.
struct NotificationFields: View {
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
        Group {
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
        .task {
            denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
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
