import SwiftUI
import SwiftData
import CarCareCore

struct HomeView: View {
    @Query private var cars: [Car]
    @Query(sort: \Item.createdAt) private var items: [Item]
    @Query private var entries: [ServiceEntry]
    @Query private var readings: [OdometerReading]
    @EnvironmentObject private var persistence: Persistence
    @EnvironmentObject private var router: Router

    @State private var showOdometer = false

    var body: some View {
        NavigationStack {
            let calendar = Fmt.calendar
            let now = Date()
            let snapshot = SnapshotBuilder.make(cars: cars, items: items, entries: entries, readings: readings)
            let statuses = ForecastEngine.statuses(for: snapshot, today: now, calendar: calendar)
            let groups = ForecastGroups.make(from: statuses, calendar: calendar)
            let names = Dictionary(snapshot.items.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            let noHistoryCount = statuses.values.filter { $0 == .noHistory }.count

            List {
                Section {
                    odometerCard(current: snapshot.currentOdometerKm)
                }

                if OdometerRules.needsNudge(readings: snapshot.odometerReadings, now: now, calendar: calendar) {
                    Section {
                        Banner(icon: "speedometer", text: L10n.t("home.nudge"), style: .warning,
                               actionTitle: L10n.t("home.updateOdometer")) { showOdometer = true }
                    }
                }

                if persistence.iCloudState.showsWarning {
                    Section {
                        Banner(icon: "icloud.slash", text: iCloudWarningText, style: .warning)
                    }
                }

                if items.isEmpty {
                    Section {
                        emptyState
                    }
                } else if entries.isEmpty {
                    Section {
                        Banner(icon: "clock.arrow.circlepath", text: L10n.t("home.noHistory"),
                               actionTitle: L10n.t("home.openHistory")) { router.tab = .history }
                    }
                }

                if !groups.overdue.isEmpty {
                    Section {
                        ForEach(groups.overdue, id: \.itemID) { f in
                            ForecastRow(name: names[f.itemID] ?? "", forecast: f)
                        }
                    } header: {
                        Label(L10n.t("home.overdue"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                ForEach(groups.upcoming, id: \.day) { group in
                    Section(Fmt.date(group.day)) {
                        ForEach(group.forecasts, id: \.itemID) { f in
                            ForecastRow(name: names[f.itemID] ?? "", forecast: f)
                        }
                    }
                }

                if !groups.undated.isEmpty {
                    Section {
                        ForEach(groups.undated, id: \.itemID) { f in
                            ForecastRow(name: names[f.itemID] ?? "", forecast: f)
                        }
                    } header: {
                        Text(L10n.t("home.undated"))
                    } footer: {
                        Text(L10n.t("home.undatedFooter"))
                    }
                }

                if noHistoryCount > 0 && !entries.isEmpty {
                    Section {
                        Text(L10n.f("home.noRecordsCount", noHistoryCount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t("tab.home"))
            .sheet(isPresented: $showOdometer) {
                OdometerUpdateView()
            }
        }
    }

    private func odometerCard(current: Int?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("home.odometer")).font(.subheadline).foregroundStyle(.secondary)
                Text(current.map(Fmt.km) ?? "—").font(.title.bold()).monospacedDigit()
                if let car = SnapshotBuilder.primaryCar(cars), !car.displayName.isEmpty {
                    Text(car.displayName).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                showOdometer = true
            } label: {
                Text(L10n.t("home.update")).frame(minWidth: 90, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("home.emptyTitle")).font(.headline)
            Text(L10n.t("home.emptyText")).font(.callout).foregroundStyle(.secondary)
            Button {
                router.tab = .parts
            } label: {
                Label(L10n.t("home.addParts"), systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
    }

    private var iCloudWarningText: String {
        switch persistence.iCloudState {
        case .noAccount: return L10n.t("icloud.noAccount")
        case .quotaFull: return L10n.t("icloud.full")
        case .localFallback: return L10n.t("icloud.unavailable")
        default: return L10n.t("icloud.syncError")
        }
    }
}

struct OdometerUpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var readings: [OdometerReading]

    @State private var km: Int?
    @State private var confirmLower = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField(title: L10n.t("odometer.placeholder"), value: $km)
                        .font(.title2)
                } footer: {
                    if let current = OdometerRules.current(readings: readings.map(\.info)) {
                        Text(L10n.f("odometer.current", Fmt.km(current.km), Fmt.date(current.date)))
                    }
                }
            }
            .navigationTitle(L10n.t("odometer.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.save")) { trySave() }.disabled(km == nil)
                }
            }
            .alert(L10n.t("odometer.lowerTitle"), isPresented: $confirmLower) {
                Button(L10n.t("common.saveAnyway")) { save() }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("odometer.lowerText"))
            }
        }
        .presentationDetents([.medium])
    }

    private func trySave() {
        guard let km else { return }
        if OdometerRules.isLowerThanCurrent(km, readings: readings.map(\.info)) {
            confirmLower = true
        } else {
            save()
        }
    }

    private func save() {
        guard let km else { return }
        context.insert(OdometerReading(date: Date(), km: km))
        DataEvents.changed(context)
        dismiss()
    }
}
