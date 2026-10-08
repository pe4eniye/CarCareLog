import SwiftUI
import SwiftData
import CarCareCore

/// Home: odometer card, then overdue items, then one card per month (traffic-light colors), then "Later".
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
            let withoutForecast = activeItems.filter { statuses[$0.uuid]?.forecast == nil }.count
            let stale = OdometerRules.needsNudge(readings: snapshot.odometerReadings, entries: snapshot.entries,
                                                 now: now, calendar: calendar)
            let ctx = RowContext(today: now, calendar: calendar, currentKm: current?.km)

            List {
                Section {
                    odometerCard(current: current, now: now, stale: stale)
                }
                .listRowBackground(stale ? Color.orange.opacity(0.14) : nil)

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
                        ForEach(groups.overdue, id: \.itemID) { f in
                            row(f, ctx: ctx, sameDay: [f.itemID])
                        }
                        .listRowBackground(Urgency.overdue.tint)
                    } header: {
                        CardHeader(title: L10n.t("home.overdue"), urgency: .overdue)
                    }
                }

                ForEach(groups.upcoming, id: \.month) { group in
                    monthSection(group, ctx: ctx)
                }

                if !groups.undated.isEmpty {
                    Section {
                        ForEach(groups.undated, id: \.itemID) { f in row(f, ctx: ctx, sameDay: [f.itemID]) }
                    } header: {
                        Text(L10n.t("home.undated"))
                    } footer: {
                        Text(L10n.t("home.undatedFooter"))
                    }
                }

                if !groups.later.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showLater) {
                            ForEach(groups.later, id: \.month) { group in
                                Text(Fmt.monthYear(group.month)).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(group.forecasts, id: \.itemID) { f in
                                    row(f, ctx: ctx, sameDay: [f.itemID])
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

                if withoutForecast > 0 {
                    Section {
                        Button {
                            router.tab = .parts
                        } label: {
                            Label(L10n.f("home.noForecastCount", withoutForecast), systemImage: "info.circle")
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("tab.home"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) { AddMenuButton() }
            }
        }
    }

    struct RowContext {
        let today: Date
        let calendar: Calendar
        let currentKm: Int?
    }

    @ViewBuilder
    private func monthSection(_ group: ForecastGroups.MonthGroup, ctx: RowContext) -> some View {
        let urgency = group.forecasts.map { $0.urgency(today: ctx.today, calendar: ctx.calendar,
                                                      currentOdometerKm: ctx.currentKm) }.max() ?? .ok
        Section {
            ForEach(group.forecasts, id: \.itemID) { f in
                let sameDay = group.forecasts
                    .filter { ctx.calendar.isDate($0.dueDate ?? .distantPast, inSameDayAs: f.dueDate ?? .distantFuture) }
                    .map(\.itemID)
                row(f, ctx: ctx, sameDay: sameDay)
            }
            .listRowBackground(urgency.tint)
        } header: {
            CardHeader(title: Fmt.monthYear(group.month), urgency: urgency)
        }
    }

    /// Tap: item card. Swipe right: "Log service" with the items due that same day preselected.
    @ViewBuilder
    private func row(_ f: ItemForecast, ctx: RowContext, sameDay: [UUID]) -> some View {
        let item = items.first { $0.uuid == f.itemID }
        Button {
            if let item { router.open(.item(item)) }
        } label: {
            HomeRow(name: item?.displayName ?? "", forecast: f,
                    urgency: f.urgency(today: ctx.today, calendar: ctx.calendar, currentOdometerKm: ctx.currentKm),
                    currentKm: ctx.currentKm)
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

    private func odometerCard(current: OdometerReadingInfo?, now: Date, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    let carName = SnapshotBuilder.primaryCar(cars)?.name ?? ""
                    Text(carName.isEmpty ? L10n.t("home.odometer") : L10n.t("home.odometer") + " · " + carName)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Text(current.map { Fmt.km($0.km) } ?? "—")
                        .font(.title.bold())
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityIdentifier("home.odometerValue")
                }
                Spacer(minLength: 8)
                Button {
                    router.open(.odometer)
                } label: {
                    Text(L10n.t("home.update")).frame(minWidth: 90, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home.update")
            }
            Label(statusLine(current: current, now: now), systemImage: stale ? "exclamationmark.circle" : "calendar")
                .font(.footnote)
                .foregroundStyle(stale ? Color.orange : Color.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
    }

    private func statusLine(current: OdometerReadingInfo?, now: Date) -> String {
        let today = L10n.f("home.today", Fmt.date(now))
        guard let current else { return today }
        let days = OdometerRules.daysSince(current.date, now: now, calendar: Fmt.calendar)
        let updated = days == 0 ? L10n.t("home.updatedToday") : L10n.f("home.updatedDaysAgo", days)
        return today + " · " + updated
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("home.emptyTitle")).font(.headline)
            Text(L10n.t("home.emptyText")).font(.callout).foregroundStyle(.secondary)
            Button {
                router.open(.addItems)
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

/// Month card header: colored dot + title.
struct CardHeader: View {
    let title: String
    let urgency: Urgency

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(urgency.color).frame(width: 9, height: 9)
            Text(title).foregroundStyle(urgency.color)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }
}

/// One item on Home: dot, name, "≈ 236 000 km · in 7 900 km" (or how far past the limit for overdue items).
struct HomeRow: View {
    let name: String
    let forecast: ItemForecast
    let urgency: Urgency
    let currentKm: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(urgency.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.body.weight(.medium)).lineLimit(2)
                Label(detail, systemImage: forecast.reason == .mileage ? "gauge.with.dots.needle.33percent" : "clock")
                    .font(.subheadline)
                    .foregroundStyle(urgency == .overdue ? Color.red : Color.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var detail: String {
        if forecast.isOverdue {
            let limits = forecast.overdueLimits
            var parts: [String] = []
            if let km = limits.km {
                parts.append(L10n.f("home.overdueKm", Fmt.km(km)))
                if let cur = currentKm, cur > km { parts.append(L10n.f("home.overBy", Fmt.km(cur - km))) }
            }
            if let d = limits.date { parts.append(L10n.f("home.overdueDate", Fmt.date(d))) }
            return parts.joined(separator: " · ")
        }
        if forecast.dueDate == nil, let km = forecast.dueKm {
            return L10n.f("home.atKm", Fmt.km(km))
        }
        var text = "≈ " + Fmt.km(forecast.predictedOdometerKm)
        if let left = forecast.kmLeft(currentOdometerKm: currentKm), left > 0 {
            text += " · " + L10n.f("home.inKm", Fmt.km(left))
        }
        return text
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
                        .accessibilityIdentifier("odometer.field")
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
                    Button(L10n.t("common.save")) { trySave() }.accessibilityIdentifier("odometer.save")
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
