import SwiftUI
import SwiftData
import UserNotifications
import CarCareCore

/// First launch, five short steps: welcome + appearance and currency → car → what you maintain → reminders →
/// privacy and backups. Everything except the car has defaults, and every control is the same one as in Settings.
struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome = 1, car, items, reminders, security }

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context
    @Query private var cars: [Car]

    @State private var step: Step = .welcome
    @State private var name = ""
    @State private var vin = ""
    @State private var odometer: Int?
    @State private var avgKm: Int?
    @State private var triedSave = false
    /// The reading created on the car step, updated (not duplicated) when the user goes back and changes it.
    @State private var reading: OdometerReading?
    @State private var faceIDError = false

    private var odometerError: FieldError? { ValidationRules.number(odometer, required: true, range: Limits.odometer) }
    private var avgError: FieldError? { ValidationRules.number(avgKm, required: true, range: Limits.avgKmPerMonth) }
    private var isValid: Bool {
        ValidationRules.text(name, required: true, max: Limits.carName) == nil && odometerError == nil && avgError == nil
    }

    private func label(_ s: Step) -> String { L10n.f("onb.step", s.rawValue, Step.allCases.count) }

    var body: some View {
        switch step {
        case .welcome:
            NavigationStack { welcomeStep }
        case .car:
            NavigationStack { carStep }
        case .items:
            // The same multi-select catalog as "+" → "Add items"; can be skipped.
            AddItemsFlow(onFinish: { step = .reminders }, skippable: true,
                         onBack: { step = .car }, stepLabel: label(.items))
        case .reminders:
            NavigationStack { remindersStep }
        case .security:
            NavigationStack { securityStep }
        }
    }

    // MARK: Steps

    private var welcomeStep: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "car.side")
                        .font(.system(size: 40))
                        .foregroundStyle(settings.accent.color)
                    Text(L10n.t("onb.welcome").replacingOccurrences(of: "\\n", with: "\n"))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
            Section {
                AppearanceFields()
            } header: {
                Text(L10n.t("settings.appearance"))
            } footer: {
                Text(L10n.t("onb.appearanceFooter"))
            }
            nextButton { step = .car }
        }
        .stepHeader(title: L10n.t("onb.welcomeTitle"), step: label(.welcome), back: nil)
    }

    private var carStep: some View {
        Form {
            CarFormFields(name: $name, vin: $vin, showErrors: triedSave)
            Section {
                LabeledField(label: L10n.t("onb.odometer")) {
                    NumberField(title: L10n.t("entry.km"), value: $odometer).frame(maxWidth: 140)
                }
                FieldErrorText(error: odometerError, show: triedSave)
            } footer: {
                Text(L10n.t("onb.odometerFooter"))
            }
            Section {
                LabeledField(label: L10n.t("settings.avgKm")) {
                    NumberField(title: "1000", value: $avgKm).frame(maxWidth: 120)
                }
                FieldErrorText(error: avgError, show: triedSave)
            } footer: {
                Text(L10n.t("settings.avgKmFooter"))
            }
            nextButton(saveCar)
        }
        .stepHeader(title: L10n.t("onb.carTitle"), step: label(.car), back: { step = .welcome })
    }

    private var remindersStep: some View {
        Form {
            Section {
                Text(L10n.t("onb.notifText")).font(.callout)
            }
            NotificationFields()
            nextButton(footer: settings.notificationsEnabled ? L10n.t("onb.notifFooter") : nil) {
                guard settings.notificationsEnabled else { step = .security; return }
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    DispatchQueue.main.async {
                        DataEvents.changed(context)
                        step = .security
                    }
                }
            }
        }
        .stepHeader(title: L10n.t("onb.notifTitle"), step: label(.reminders), back: { step = .items })
    }

    private var securityStep: some View {
        Form {
            Section {
                if AppLock.biometryAvailable {
                    Toggle(L10n.t("settings.faceID"), isOn: Binding(
                        get: { settings.faceIDEnabled },
                        set: { newValue in
                            if newValue {
                                AppLock.confirm { ok in
                                    if ok { settings.faceIDEnabled = true } else { faceIDError = true }
                                }
                            } else {
                                settings.faceIDEnabled = false
                            }
                        }
                    ))
                    .frame(minHeight: 44)
                }
            } header: {
                Text(L10n.t("settings.security"))
            } footer: {
                Text(L10n.t(AppLock.biometryAvailable ? "onb.faceIDText" : "onb.faceIDUnavailable"))
            }
            Section {
                Label(L10n.t("onb.backupText"), systemImage: "arrow.triangle.2.circlepath.icloud")
                    .font(.callout)
                    .padding(.vertical, 4)
            } header: {
                Text(L10n.t("autobackup.section"))
            }
            nextButton(title: L10n.t("onb.start"), finish)
        }
        .stepHeader(title: L10n.t("onb.securityTitle"), step: label(.security), back: { step = .reminders })
        .alert(L10n.t("settings.faceIDUnavailable"), isPresented: $faceIDError) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Parts

    private func nextButton(title: String? = nil, footer: String? = nil,
                            _ action: @escaping () -> Void) -> some View {
        Section {
            Button(action: action) {
                Text(title ?? L10n.t("onb.next")).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .accessibilityIdentifier("onb.next")
        } footer: {
            if let footer { Text(footer).frame(maxWidth: .infinity) }
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
        if let reading {
            reading.km = km
        } else {
            let r = OdometerReading(date: Date(), km: km)
            context.insert(r)
            reading = r
        }
        DataEvents.changed(context)
        step = .items
    }

    private func finish() {
        settings.onboardingDone = true
        DataEvents.changed(context)
    }
}

/// Title with "Step N of M" under it, and "Back" on the left.
struct StepTitle: View {
    let title: String
    let step: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.headline)
            Text(step).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func stepHeader(title: String, step: String, back: (() -> Void)?) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .principal) { StepTitle(title: title, step: step) }
                if let back {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: back) {
                            Label(L10n.t("onb.back"), systemImage: "chevron.left").labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
    }
}
