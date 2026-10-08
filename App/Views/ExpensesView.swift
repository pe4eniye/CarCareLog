import SwiftUI
import SwiftData
import Charts
import CarCareCore

/// "Expenses": totals for a month, a year or all time, in the app currency (other currencies are listed below and
/// can be switched to), bars by month (or by year), a donut by category and the list of paid services.
struct ExpensesView: View {
    enum Mode: Hashable { case month, year, all }

    @Query private var cars: [Car]
    @Query(sort: \Item.createdAt) private var items: [Item]
    @Query private var entries: [ServiceEntry]
    @Query private var readings: [OdometerReading]
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: Router

    @State private var mode: Mode = .year
    @State private var offset = 0
    @State private var shownCurrency: Currency?

    private var cal: Calendar { Fmt.calendar }
    private var lang: AssistantLanguage { L10n.assistantLanguage }

    private var period: DateInterval? {
        let now = Date()
        switch mode {
        case .month:
            let start = cal.date(byAdding: .month, value: offset, to: Expenses.month(of: now, calendar: cal).start)!
            return Expenses.month(of: start, calendar: cal)
        case .year:
            return Expenses.year(cal.component(.year, from: now) + offset, calendar: cal)
        case .all:
            return nil
        }
    }

    private var periodTitle: String {
        guard let p = period else { return L10n.t("expenses.allTime") }
        return mode == .month ? Fmt.monthYear(p.start) : String(cal.component(.year, from: p.start))
    }

    var body: some View {
        NavigationStack {
            let snap = SnapshotBuilder.make(cars: cars, items: items, entries: entries, readings: readings)
            let currency = shownCurrency ?? settings.currency
            let total = Expenses.total(snap, currency: currency, in: period)
            let others = Expenses.totalsByCurrency(snap, in: period).filter { $0.0 != currency }
            let lines = Expenses.lines(snap, currency: currency, in: period)
            let categories = Expenses.byCategory(snap, currency: currency, in: period)

            List {
                Section {
                    Picker("", selection: $mode) {
                        Text(L10n.t("expenses.month")).tag(Mode.month)
                        Text(L10n.t("expenses.year")).tag(Mode.year)
                        Text(L10n.t("expenses.all")).tag(Mode.all)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .onChange(of: mode) { _, _ in offset = 0 }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if mode != .all {
                                Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                                    .buttonStyle(.borderless)
                            }
                            Text(periodTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            if mode != .all {
                                Button { offset += 1 } label: { Image(systemName: "chevron.right") }
                                    .buttonStyle(.borderless)
                                    .disabled(offset >= 0)
                            }
                        }
                        Text(AssistantFormat.money(total, currency, lang))
                            .font(.largeTitle.weight(.bold)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(L10n.f("expenses.summary", lines.count))
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(others.map { Amount(currency: $0.0, value: $0.1) }) { other in
                            Button {
                                shownCurrency = other.currency
                            } label: {
                                Text(L10n.f("expenses.otherCurrency", AssistantFormat.money(other.value, other.currency, lang)))
                                    .font(.footnote)
                            }
                            .buttonStyle(.borderless)
                        }
                        if shownCurrency != nil && shownCurrency != settings.currency {
                            Button(L10n.f("expenses.backTo", settings.currency.symbol)) { shownCurrency = nil }
                                .font(.footnote).buttonStyle(.borderless)
                        }
                        chart(snap, currency: currency)
                            .frame(height: 150)
                            .padding(.top, 6)
                    }
                    .padding(.vertical, 6)
                }

                if !categories.isEmpty {
                    Section(L10n.t("expenses.byCategory")) {
                        let slices = categories.enumerated().map { Slice(id: $0.offset, name: categoryName($0.element.0),
                                                                         value: $0.element.1) }
                        let sum = slices.reduce(0) { $0 + $1.value }
                        HStack(spacing: 16) {
                            Chart(slices) { s in
                                SectorMark(angle: .value("", s.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                                    .foregroundStyle(by: .value("", s.name))
                                    .cornerRadius(3)
                            }
                            .chartLegend(.hidden)
                            .frame(width: 110, height: 110)
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(slices.prefix(6))) { s in
                                    HStack {
                                        Text(s.name).font(.footnote).lineLimit(1)
                                        Spacer()
                                        Text("\(Int((s.value / sum * 100).rounded()))%").font(.footnote.weight(.semibold))
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section(L10n.t("expenses.list")) {
                    if lines.isEmpty {
                        Text(L10n.t("expenses.empty")).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(lines) { line in
                        Button {
                            if let e = entries.first(where: { $0.uuid == line.id }) { router.open(.editEntry(e)) }
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.names.joined(separator: ", ")).font(.body.weight(.medium)).lineLimit(2)
                                    Text(Fmt.date(line.date) + " · " + Fmt.km(line.odometerKm))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(AssistantFormat.money(line.amount, line.currency, lang))
                                    .font(.body.weight(.semibold)).monospacedDigit()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle(L10n.t("tab.expenses"))
        }
    }

    private func categoryName(_ c: CatalogItem.Category?) -> String {
        c.map { Catalog.categoryName($0, lang) } ?? L10n.t("expenses.other")
    }

    /// Year: 12 monthly bars. All time: one bar per year. Month: bars per entry date.
    @ViewBuilder
    private func chart(_ snap: DataSnapshot, currency: Currency) -> some View {
        switch mode {
        case .year:
            let year = cal.component(.year, from: period!.start)
            let values = Expenses.byMonth(snap, currency: currency, year: year, calendar: cal)
            let bars = values.enumerated().map { Slice(id: $0.offset, name: shortMonth($0.offset + 1), value: $0.element) }
            Chart(bars) { bar in
                BarMark(x: .value("", bar.name), y: .value("", bar.value))
                    .foregroundStyle(settings.accent.color.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis(.hidden)
        case .all:
            let years = Set(Expenses.lines(snap, currency: currency).map { cal.component(.year, from: $0.date) }).sorted()
            Chart(years, id: \.self) { y in
                BarMark(x: .value("", String(y)),
                        y: .value("", Expenses.total(snap, currency: currency, in: Expenses.year(y, calendar: cal))))
                    .foregroundStyle(settings.accent.color.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis(.hidden)
        case .month:
            let lines = Expenses.lines(snap, currency: currency, in: period)
            Chart(lines) { line in
                BarMark(x: .value("", line.date, unit: .day), y: .value("", line.amount))
                    .foregroundStyle(settings.accent.color.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis(.hidden)
        }
    }

    private func shortMonth(_ m: Int) -> String {
        let f = DateFormatter()
        f.locale = L10n.locale
        return String(f.shortStandaloneMonthSymbols[m - 1].prefix(3))
    }
}

/// Chart data point (category share, month bar).
private struct Slice: Identifiable {
    let id: Int
    let name: String
    let value: Double
}

private struct Amount: Identifiable {
    let currency: Currency
    let value: Double
    var id: String { currency.rawValue }
}
