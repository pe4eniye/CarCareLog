import SwiftUI
import SwiftData
import CarCareCore

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var persistence: Persistence
    @Environment(\.modelContext) private var context
    @Query private var cars: [Car]
    @Query private var entries: [ServiceEntry]
    @Query private var readings: [OdometerReading]
    @Query private var items: [Item]

    @State private var avgKm: Int?
    @State private var faceIDError = false
    @State private var confirmWipe = false
    @State private var confirmWipeAgain = false
    @State private var pdfURL: URL?

    private var car: Car? { SnapshotBuilder.primaryCar(cars) }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("settings.appearance")) {
                    Picker(L10n.t("settings.language"), selection: $settings.language) {
                        ForEach(L10n.choices, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    .frame(minHeight: 44)
                    Picker(L10n.t("settings.theme"), selection: $settings.theme) {
                        Text(L10n.t("settings.themeLight")).tag("light")
                        Text(L10n.t("settings.themeDark")).tag("dark")
                        Text(L10n.t("settings.themeSystem")).tag("system")
                    }
                    .frame(minHeight: 44)
                }

                Section {
                    NavigationLink {
                        CarEditorView()
                    } label: {
                        LabeledField(label: L10n.t("settings.car")) {
                            Text(car?.name.isEmpty == false ? car!.name : "—")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    LabeledField(label: L10n.t("settings.avgKm")) {
                        NumberField(title: "1000", value: $avgKm)
                            .frame(maxWidth: 120)
                    }
                    FieldErrorText(error: ValidationRules.number(avgKm, required: true, range: Limits.avgKmPerMonth))
                } header: {
                    Text(L10n.t("settings.carSection"))
                } footer: {
                    Text(avgFooter)
                }

                Section(L10n.t("settings.reminders")) {
                    Picker(L10n.t("settings.leadTime"), selection: $settings.leadTimeDays) {
                        ForEach(ReminderLeadTime.allCases) { lead in
                            Text(Self.leadTimeTitle(lead)).tag(lead.rawValue)
                        }
                    }
                    .frame(minHeight: 44)
                }

                Section(L10n.t("settings.security")) {
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

                Section {
                    LabeledField(label: "iCloud") {
                        Text(iCloudStatusText).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(L10n.t("settings.icloudFooter"))
                }

                BackupSection()

                Section {
                    Button {
                        pdfURL = ServiceBookPDF.make(context: context)
                    } label: {
                        Label(L10n.t("pdf.export"), systemImage: "doc.richtext").frame(minHeight: 44)
                    }
                    .disabled(entries.isEmpty && items.isEmpty)
                } footer: {
                    Text(L10n.t("pdf.footer"))
                }

                Section {
                    Button(L10n.t("wipe.button"), role: .destructive) { confirmWipe = true }
                        .frame(minHeight: 44)
                } footer: {
                    Text(L10n.t("wipe.footer"))
                }

                Section {
                    LabeledField(label: L10n.t("settings.version")) {
                        Text(Self.versionString).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t("tab.settings"))
            .onAppear { avgKm = car.map { Int($0.avgKmPerMonth) } }
            .onChange(of: avgKm) { _, newValue in
                guard let car, let v = newValue, Limits.avgKmPerMonth.contains(v), Double(v) != car.avgKmPerMonth else { return }
                car.avgKmPerMonth = Double(v)
                DataEvents.changed(context)
            }
            .onChange(of: settings.leadTimeDays) { _, _ in DataEvents.changed(context) }
            .alert(L10n.t("settings.faceIDUnavailable"), isPresented: $faceIDError) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: Binding(get: { pdfURL != nil }, set: { if !$0 { pdfURL = nil } })) {
                if let pdfURL { ShareSheet(items: [pdfURL]) }
            }
            .confirmationDialog(L10n.t("wipe.title"), isPresented: $confirmWipe, titleVisibility: .visible) {
                Button(L10n.t("wipe.continue"), role: .destructive) { confirmWipeAgain = true }
            } message: {
                Text(L10n.t("wipe.text"))
            }
            .alert(L10n.t("wipe.finalTitle"), isPresented: $confirmWipeAgain) {
                Button(L10n.t("wipe.finalButton"), role: .destructive) { wipe() }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("wipe.finalText"))
            }
        }
    }

    /// Which km/month the forecast uses right now: computed from the user's data or the manual value.
    private var avgFooter: String {
        let snap = SnapshotBuilder.make(cars: cars, items: items, entries: entries, readings: readings)
        let e = MileageEstimator.estimate(snapshot: snap, today: Date(), calendar: Fmt.calendar)
        if e.isAutomatic {
            return L10n.f("settings.avgAuto", AssistantFormat.groupDigits(Int(e.value), separator: "\u{00A0}"),
                          max(1, e.spanDays / 30))
        }
        return L10n.t("settings.avgManual")
    }

    private func wipe() {
        try? SnapshotBuilder.deleteAll(in: context)
        settings.onboardingDone = false
        DataEvents.changed(context)
    }

    static func leadTimeTitle(_ lead: ReminderLeadTime) -> String {
        switch lead {
        case .sameDay: return L10n.t("lead.sameDay")
        case .oneWeek: return L10n.t("lead.oneWeek")
        case .twoWeeks: return L10n.t("lead.twoWeeks")
        case .threeWeeks: return L10n.t("lead.threeWeeks")
        case .oneMonth: return L10n.t("lead.oneMonth")
        }
    }

    private var iCloudStatusText: String {
        switch persistence.iCloudState {
        case .disabledInBuild: return L10n.t("icloud.off")
        case .checking: return L10n.t("icloud.checking")
        case .active: return L10n.t("icloud.on")
        case .noAccount: return L10n.t("icloud.noAccountShort")
        case .quotaFull: return L10n.t("icloud.fullShort")
        case .syncError: return L10n.t("icloud.errorShort")
        case .localFallback: return L10n.t("icloud.unavailableShort")
        }
    }

    static var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

/// Car profile form, used in Settings and in onboarding.
struct CarFormFields: View {
    @Binding var name: String
    @Binding var vin: String
    var showErrors: Bool

    var body: some View {
        Section {
            TextField(L10n.t("car.name"), text: $name)
                .limitLength($name, Limits.carName)
                .frame(minHeight: 44)
            FieldErrorText(error: ValidationRules.text(name, required: true, max: Limits.carName), show: showErrors)
            TextField(L10n.t("car.vin"), text: $vin)
                .limitLength($vin, Limits.vin)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
        } footer: {
            if ValidationRules.vinLooksWrong(vin) {
                Text(L10n.f("car.vinWarning", vin.trimmed.count)).foregroundStyle(.orange)
            } else {
                Text(L10n.t("car.nameFooter"))
            }
        }
    }
}

struct CarEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var cars: [Car]
    @Query private var entries: [ServiceEntry]
    @Query private var readings: [OdometerReading]
    @Query private var items: [Item]

    @State private var name = ""
    @State private var vin = ""
    @State private var loaded = false
    @State private var triedSave = false

    var body: some View {
        Form {
            CarFormFields(name: $name, vin: $vin, showErrors: triedSave)
        }
        .navigationTitle(L10n.t("settings.car"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.t("common.save")) { save() }
            }
        }
        .onAppear {
            guard !loaded, let car = SnapshotBuilder.primaryCar(cars) else { return }
            loaded = true
            name = car.name
            vin = car.vin ?? ""
        }
    }

    private func save() {
        triedSave = true
        guard ValidationRules.text(name, required: true, max: Limits.carName) == nil else { return }
        let car = SnapshotBuilder.primaryCar(cars) ?? {
            let c = Car()
            context.insert(c)
            return c
        }()
        car.name = name.trimmed
        car.vin = vin.trimmed.isEmpty ? nil : vin.trimmed.uppercased()
        DataEvents.changed(context)
        dismiss()
    }
}
