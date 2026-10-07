import SwiftUI
import SwiftData
import UserNotifications
import CarCareCore

/// First launch: car profile → offer Face ID → notification permission → main screen (empty state guides further).
struct OnboardingView: View {
    enum Step { case car, faceID, notifications }

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context
    @Query private var cars: [Car]

    @State private var step: Step = .car
    @State private var name = ""
    @State private var vin = ""
    @State private var odometer: Int?
    @State private var avgKm: Int?
    @State private var triedSave = false

    private var odometerError: FieldError? { ValidationRules.number(odometer, required: true, range: Limits.odometer) }
    private var avgError: FieldError? { ValidationRules.number(avgKm, required: true, range: Limits.avgKmPerMonth) }
    private var isValid: Bool {
        ValidationRules.text(name, required: true, max: Limits.carName) == nil && odometerError == nil && avgError == nil
    }

    var body: some View {
        NavigationStack {
            switch step {
            case .car: carStep
            case .faceID: faceIDStep
            case .notifications: notificationsStep
            }
        }
    }

    private var carStep: some View {
        Form {
            Section {
                Text(L10n.t("onb.welcome")).font(.callout)
            }
            Section {
                Picker(L10n.t("settings.language"), selection: $settings.language) {
                    ForEach(L10n.choices, id: \.code) { Text($0.name).tag($0.code) }
                }
                .frame(minHeight: 44)
            }
            CarFormFields(name: $name, vin: $vin, showErrors: triedSave)
            Section {
                LabeledField(label: L10n.t("onb.odometer")) {
                    NumberField(title: L10n.t("entry.km"), value: $odometer).frame(maxWidth: 140)
                }
                FieldErrorText(error: odometerError, show: triedSave)
                LabeledField(label: L10n.t("settings.avgKm")) {
                    NumberField(title: "1000", value: $avgKm).frame(maxWidth: 120)
                }
                FieldErrorText(error: avgError, show: triedSave)
            } footer: {
                Text(L10n.t("settings.avgKmFooter"))
            }
            Section {
                Button {
                    saveCar()
                } label: {
                    Text(L10n.t("onb.next")).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(L10n.t("onb.carTitle"))
    }

    private var faceIDStep: some View {
        OnboardingPage(icon: "faceid", title: L10n.t("onb.faceIDTitle"), text: L10n.t("onb.faceIDText"),
                       primary: L10n.t("onb.enable"), secondary: L10n.t("onb.skip")) {
            AppLock.confirm { ok in
                settings.faceIDEnabled = ok
                step = .notifications
            }
        } secondaryAction: {
            step = .notifications
        }
    }

    private var notificationsStep: some View {
        OnboardingPage(icon: "bell.badge", title: L10n.t("onb.notifTitle"), text: L10n.t("onb.notifText"),
                       primary: L10n.t("onb.allow"), secondary: L10n.t("onb.skip")) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                DispatchQueue.main.async { finish() }
            }
        } secondaryAction: {
            finish()
        }
    }

    private func saveCar() {
        triedSave = true
        guard isValid, let km = odometer, let avg = avgKm else { return }
        let car = SnapshotBuilder.primaryCar(cars) ?? {
            let c = Car()
            context.insert(c)
            return c
        }()
        car.name = name.trimmed
        car.vin = vin.trimmed.isEmpty ? nil : vin.trimmed.uppercased()
        car.avgKmPerMonth = Double(avg)
        context.insert(OdometerReading(date: Date(), km: km))
        DataEvents.changed(context)
        step = AppLock.biometryAvailable ? .faceID : .notifications
    }

    private func finish() {
        settings.onboardingDone = true
        DataEvents.changed(context)
    }
}

struct OnboardingPage: View {
    let icon: String
    let title: String
    let text: String
    let primary: String
    let secondary: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon).font(.system(size: 64)).foregroundStyle(Color.accentColor)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button(action: primaryAction) {
                Text(primary).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            Button(action: secondaryAction) {
                Text(secondary).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(24)
    }
}
