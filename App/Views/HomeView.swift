import SwiftUI
import SwiftData
import CarCareCore

/// Home: compact car card, summary chips (also filters), then one card per month with a single status dot and
/// word in its title; overdue first, "Later" collapsed at the bottom.
struct HomeView: View {
    @Query private var cars: [Car]
    @Query(sort: \Item.createdAt) private var items: [Item]
    @Query private var entries: [ServiceEntry]
    @Query private var readings: [OdometerReading]
    @EnvironmentObject private var persistence: Persistence
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var settings: AppSettings

    @State private var showLater = false
    @State private var filter: Urgency?

    struct Card: Identifiable {
        let id: String
        let title: String
        let rows: [ItemForecast]
        let urgency: Urgency
    }

    var body: some View {
        NavigationStack {
            let cal = Fmt.calendar
            let now = Date()
            let snapshot = SnapshotBuilder.make(cars: cars, items: items, entries: entries, readings: readings)
            let current = OdometerRules.current(readings: snapshot.odometerReadings, entries: snapshot.entries,
                                                calendar: cal)
            let statuses = ForecastEngine.statuses(for: snapshot, today: now, calendar: cal)
            let groups = ForecastGroups.make(from: statuses, calendar: cal, today: now, currentOdometerKm: current?.km)
            let urgencyOf: (ItemForecast) -> Urgency = { $0.urgency(today: now, calendar: cal, currentOdometerKm: current?.km) }
            let all = statuses.values.compactMap(\.forecast)
            let counts = Dictionary(grouping: all, by: urgencyOf).mapValues(\.count)
            let stale = OdometerRules.needsNudge(readings: snapshot.odometerReadings, entries: snapshot.entries,
                                                 now: now, calendar: cal, intervalDays: settings.odometerDays)
            let cards = makeCards(groups, urgencyOf: urgencyOf)
            let activeItems = items.filter { !$0.isArchived }

            List {
                Section {
                    carCard(current: current, now: now, stale: stale)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if !all.isEmpty {
                    Section {
                        chips(counts)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                if persistence.iCloudState.showsWarning {
                    Section {
                        Banner(icon: "icloud.slash", text: iCloudWarningText, style: .warning)
                    }
                }
                if AutoBackup.isOverdue(hasData: !entries.isEmpty, settings: settings) {
                    Section {
                        Banner(icon: "externaldrive.badge.exclamationmark", text: L10n.t("backup.overdue"),
                               style: .warning, actionTitle: L10n.t("backup.now")) {
                            AutoBackup.runNow(force: true)
                        }
                    }
                }

                if activeItems.isEmpty {
                    Section { emptyState }
                }

                ForEach(cards) { card in
                    let rows = card.rows.filter { filter == nil || urgencyOf($0) == filter }
                    if !rows.isEmpty {
                        Section {
                            CardTitle(title: card.title, urgency: card.urgency)
                            ForEach(rows, id: \.itemID) { f in row(f, card: card, current: current?.km, now: now) }
                        }
                        .listRowBackground(card.urgency.tint)
                    }
                }

                if !groups.later.isEmpty && filter == nil {
                    Section {
                        DisclosureGroup(isExpanded: $showLater) {
                            ForEach(groups.later, id: \.month) { group in
                                Text(Fmt.monthYear(group.month)).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(group.forecasts, id: \.itemID) { f in
                                    row(f, card: Card(id: "later", title: "", rows: group.forecasts, urgency: .ok),
                                        current: current?.km, now: now)
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
            }
            .listSectionSpacing(12)
            .animation(.snappy, value: filter)
            .navigationTitle(L10n.t("tab.home"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        router.open(.settings)
                    } label: {
                        Image(systemName: "gearshape").font(.title3).frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(L10n.t("tab.settings"))
                    .accessibilityIdentifier("home.settings")
                }
                ToolbarItem(placement: .primaryAction) { AddMenuButton() }
            }
        }
    }

    private func makeCards(_ g: ForecastGroups, urgencyOf: (ItemForecast) -> Urgency) -> [Card] {
        var cards: [Card] = []
        if !g.overdue.isEmpty {
            cards.append(Card(id: "overdue", title: L10n.t("home.overdue"), rows: g.overdue, urgency: .overdue))
        }
        for m in g.upcoming {
            let u = m.forecasts.map(urgencyOf).max() ?? .ok
            cards.append(Card(id: "m\(m.month.timeIntervalSince1970)", title: Fmt.monthYear(m.month), rows: m.forecasts,
                              urgency: u))
        }
        if !g.undated.isEmpty {
            let u = g.undated.map(urgencyOf).max() ?? .ok
            cards.append(Card(id: "undated", title: L10n.t("home.undated"), rows: g.undated, urgency: u))
        }
        return cards
    }

    /// Tap: item card. Swipe right: "Log service" with the items due that same day preselected.
    @ViewBuilder
    private func row(_ f: ItemForecast, card: Card, current: Int?, now: Date) -> some View {
        let item = items.first { $0.uuid == f.itemID }
        let sameDay = card.rows
            .filter { Fmt.calendar.isDate($0.dueDate ?? .distantPast, inSameDayAs: f.dueDate ?? .distantFuture) }
            .map(\.itemID)
        Button {
            if let item { router.open(.item(item)) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.displayName ?? "").font(.body.weight(.medium)).lineLimit(2)
                Text(ForecastText.detail(kind: item?.kind ?? .interval, forecast: f, currentKm: current, today: now))
                    .font(.subheadline)
                    .foregroundStyle(f.isOverdue ? Color.red : Color.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                router.open(.logService(sameDay.isEmpty ? [f.itemID] : sameDay))
            } label: {
                Label(L10n.t("home.done"), systemImage: "checkmark")
            }
            .tint(.green)
        }
    }

    /// Compact: car name and odometer on the left, "Update" on the right, one status line.
    private func carCard(current: OdometerReadingInfo?, now: Date, stale: Bool) -> some View {
        let background = stale ? Color.orange : settings.accent.color
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(SnapshotBuilder.primaryCar(cars)?.name ?? L10n.t("home.odometer"))
                        .font(.footnote.weight(.medium)).opacity(0.85).lineLimit(1)
                    Text(current.map { Fmt.km($0.km) } ?? "—")
                        .font(.title2.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("home.odometerValue")
                }
                Spacer(minLength: 8)
                Button {
                    router.open(.odometer)
                } label: {
                    Text(L10n.t("home.update")).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .background(Capsule().fill(.white))
                        .foregroundStyle(background)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.update")
            }
            Text(statusLine(current: current, now: now, stale: stale))
                .font(.caption).opacity(0.9).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(background.gradient))
    }

    private func statusLine(current: OdometerReadingInfo?, now: Date, stale: Bool) -> String {
        let today = L10n.f("home.today", Fmt.date(now))
        guard let current else { return today }
        let days = OdometerRules.daysSince(current.date, now: now, calendar: Fmt.calendar)
        if stale { return today + " · " + L10n.f("home.staleDays", days) }
        let updated = days == 0 ? L10n.t("home.updatedToday") : L10n.f("home.updatedDaysAgo", days)
        return today + " · " + updated
    }

    /// "1 overdue · 2 soon · 6 fine": tap to show only those, tap again to show all.
    private func chips(_ counts: [Urgency: Int]) -> some View {
        HStack(spacing: 8) {
            ForEach([Urgency.overdue, .soon, .ok], id: \.self) { u in
                let n = counts[u] ?? 0
                if n > 0 {
                    Button {
                        filter = filter == u ? nil : u
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(u.color).frame(width: 7, height: 7)
                            Text(L10n.f(u.countKey, n)).font(.footnote.weight(.medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(filter == u ? u.tint : Color(.secondarySystemGroupedBackground)))
                        .overlay(Capsule().strokeBorder(filter == u ? u.color : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chip.\(u.rawValue)")
                }
            }
            Spacer(minLength: 0)
        }
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

/// First row of a month card: status dot, month, status word (so color is never the only signal).
struct CardTitle: View {
    let title: String
    let urgency: Urgency

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(urgency.color).frame(width: 9, height: 9)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(urgency.textColor)
            Spacer()
            Text(L10n.t(urgency.wordKey))
                .font(.caption.weight(.semibold))
                .foregroundStyle(urgency.textColor)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(urgency.color.opacity(0.18)))
        }
        .accessibilityElement(children: .combine)
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
