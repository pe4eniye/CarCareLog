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

    @State private var showLater = false

    var body: some View {
        NavigationStack {
            let calendar = Fmt.calendar
            let now = Date()
            let snapshot = SnapshotBuilder.make(cars: cars, items: items, entries: entries, readings: readings)
            let current = OdometerRules.current(readings: snapshot.odometerReadings, entries: snapshot.entries,
                                                calendar: calendar)
            let statuses = ForecastEngine.statuses(for: snapshot, today: now, calendar: calendar)
            let groups = ForecastGroups.make(from: statuses, calendar: calendar, today: now,
                                             currentOdometerKm: current?.km)
            let activeItems = items.filter { !$0.isArchived }
            let noHistoryCount = statuses.values.filter { $0 == .noHistory }.count

            List {
                Section {
                    odometerCard(current: current, now: now)
                }

                if OdometerRules.needsNudge(readings: snapshot.odometerReadings, entries: snapshot.entries,
                                            now: now, calendar: calendar) {
                    Section {
                        Banner(icon: "speedometer", text: L10n.t("home.nudge"), style: .warning,
                               actionTitle: L10n.t("home.updateOdometer")) { router.open(.odometer) }
                    }
                }

                if persistence.iCloudState.showsWarning {
                    Section {
                        Banner(icon: "icloud.slash", text: iCloudWarningText, style: .warning)
                    }
                }

                if activeItems.isEmpty {
                    Section { emptyState }
                }

                if !groups.overdue.isEmpty {
                    Section {
                        ForEach(groups.overdue, id: \.itemID) { f in row(f, sameDay: [f.itemID]) }
                    } header: {
                        Label(L10n.t("home.overdue"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                ForEach(groups.upcoming, id: \.day) { group in
                    Section(Fmt.date(group.day)) {
                        ForEach(group.forecasts, id: \.itemID) { f in
                            row(f, sameDay: group.forecasts.map(\.itemID))
                        }
                    }
                }

                if !groups.undated.isEmpty {
                    Section {
                        ForEach(groups.undated, id: \.itemID) { f in row(f, sameDay: [f.itemID]) }
                    } header: {
                        Text(L10n.t("home.undated"))
                    } footer: {
                        Text(L10n.t("home.undatedFooter"))
                    }
                }

                if !groups.later.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showLater) {
                            ForEach(groups.later, id: \.day) { group in
                                ForEach(group.forecasts, id: \.itemID) { f in
                                    row(f, sameDay: group.forecasts.map(\.itemID), showDate: true)
                                }
                            }
                        } label: {
                            Text(L10n.f("home.later", groups.later.reduce(0) { $0 + $1.forecasts.count }))
                                .font(.headline)
                        }
                    } footer: {
                        Text(L10n.t("home.laterFooter"))
                    }
                }

                if noHistoryCount > 0 {
                    Section {
                        Text(L10n.f("home.noRecordsCount", noHistoryCount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t("tab.home"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) { AddMenuButton() }
            }
        }
    }

    /// Tap: item card. Swipe right: "Log service" with all items due that day preselected.
    @ViewBuilder
    private func row(_ f: ItemForecast, sameDay: [UUID], showDate: Bool = false) -> some View {
        let item = items.first { $0.uuid == f.itemID }
        Button {
            if let item { router.open(.item(item)) }
        } label: {
            ForecastRow(name: item?.name ?? "", forecast: f, showDate: showDate)
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                router.open(.logService(sameDay))
            } label: {
                Label(L10n.t("home.done"), systemImage: "checkmark")
            }
            .tint(.green)
        }
    }

    private func odometerCard(current: OdometerReadingInfo?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("home.odometer")).font(.subheadline).foregroundStyle(.secondary)
                    Text(current.map { Fmt.km($0.km) } ?? "—")
                        .font(.title.bold())
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    if let car = SnapshotBuilder.primaryCar(cars), !car.name.isEmpty {
                        Text(car.name).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    router.open(.odometer)
                } label: {
                    Text(L10n.t("home.update")).frame(minWidth: 90, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            Divider()
            // One text, so it wraps naturally on narrow screens.
            Label(L10n.f("home.today", Fmt.date(now)) + (current.map { " · " + updatedText($0.date, now: now) } ?? ""),
                  systemImage: "calendar")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
    }

    private func updatedText(_ date: Date, now: Date) -> String {
        let days = OdometerRules.daysSince(date, now: now, calendar: Fmt.calendar)
        return days == 0 ? L10n.t("home.updatedToday") : L10n.f("home.updatedDaysAgo", days)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("home.emptyTitle")).font(.headline)
            Text(L10n.t("home.emptyText")).font(.callout).foregroundStyle(.secondary)
            Button {
                router.open(.newItem(Router.ItemDraft()))
            } label: {
                Label(L10n.t("add.item"), systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
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
    @Query private var entries: [ServiceEntry]

    @State private var km: Int?
    @State private var confirmLower = false
    @State private var triedSave = false

    private var current: OdometerReadingInfo? {
        OdometerRules.current(readings: readings.map(\.info), entries: entries.map(\.info), calendar: Fmt.calendar)
    }
    private var error: FieldError? { ValidationRules.number(km, required: true, range: Limits.odometer) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField(title: L10n.t("odometer.placeholder"), value: $km)
                        .font(.title2)
                    FieldErrorText(error: error, show: triedSave)
                } footer: {
                    if let current {
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
                    Button(L10n.t("common.save")) { trySave() }
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
        triedSave = true
        guard error == nil, let km else { return }
        if let current, km < current.km {
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
