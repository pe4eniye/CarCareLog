import SwiftUI
import SwiftData
import CarCareCore

/// "Add items": pick several catalog items and/or custom names, then set intervals and the last replacement
/// for all of them on one screen. Used from "+", the empty schedule and onboarding.
struct AddItemsFlow: View {
    /// Called after saving or skipping (onboarding continues with the next step).
    var onFinish: () -> Void = {}
    var skippable = false
    /// Onboarding: "Back" on the left, "Skip" on the right, "Step N of M" under the title, import link on top.
    var onBack: (() -> Void)?
    var stepLabel: String?

    @Environment(\.dismiss) private var dismiss
    @State private var picked: [ItemChoiceDraft] = []
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            CatalogPickerView(picked: $picked, showImport: onBack != nil)
                .navigationTitle(L10n.t("catalog.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let onBack {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(L10n.t("onb.back"), action: onBack)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.t("onb.skip")) { finish() }
                        }
                    } else {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(skippable ? L10n.t("onb.skip") : L10n.t("common.cancel")) { finish() }
                        }
                    }
                    if let stepLabel {
                        ToolbarItem(placement: .principal) {
                            StepTitle(title: L10n.t("catalog.title"), step: stepLabel)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !picked.isEmpty {
                        Button {
                            showSetup = true
                        } label: {
                            Text(L10n.f("catalog.next", picked.count)).frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("catalog.next")
                    }
                }
                .navigationDestination(isPresented: $showSetup) {
                    BulkSetupView(choices: picked) { finish() }
                }
        }
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}

/// Catalog by category with checkmarks and search, plus "Custom item" at the bottom.
struct CatalogPickerView: View {
    @Binding var picked: [ItemChoiceDraft]
    var showImport = false

    @Query(sort: \Item.createdAt) private var items: [Item]
    @State private var search = ""
    @State private var customName = ""
    @State private var customError: String?

    private var lang: AssistantLanguage { L10n.assistantLanguage }

    private func inUse(_ key: String) -> Item? { items.first { $0.catalogKey == key } }

    private func matches(_ c: CatalogItem) -> Bool {
        let q = search.trimmed
        guard !q.isEmpty else { return true }
        return (c.allNames + c.synonyms).contains { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            if showImport && search.isEmpty {
                Section {
                    NavigationLink {
                        ImportHistoryView()
                    } label: {
                        Label(L10n.t("onb.import"), systemImage: "doc.on.clipboard").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("onb.import")
                } footer: {
                    Text(L10n.t("onb.importFooter"))
                }
            }
            let customs = picked.compactMap { choice -> String? in
                if case .custom(let n) = choice { return n }
                return nil
            }
            if !customs.isEmpty {
                Section(L10n.t("catalog.yourCustom")) {
                    ForEach(customs, id: \.self) { name in
                        CheckRow(title: name, checked: true) { picked.removeAll { $0 == .custom(name) } }
                    }
                }
            }
            ForEach(CatalogItem.Category.allCases, id: \.self) { category in
                let list = Catalog.items.filter { $0.category == category && matches($0) }
                if !list.isEmpty {
                    Section(Catalog.categoryName(category, lang)) {
                        ForEach(list) { c in
                            if let existing = inUse(c.key) {
                                HStack {
                                    Text(c.name(lang)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(existing.isArchived ? L10n.t("catalog.inArchive") : L10n.t("catalog.added"))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 44)
                            } else {
                                CheckRow(title: c.name(lang), checked: picked.contains(.catalog(c.key))) {
                                    toggle(.catalog(c.key))
                                }
                            }
                        }
                    }
                }
            }
            Section {
                HStack {
                    TextField(L10n.t("catalog.customPlaceholder"), text: $customName)
                        .limitLength($customName, Limits.itemName)
                        .onSubmit(addCustom)
                        .accessibilityIdentifier("catalog.customName")
                    Button(L10n.t("catalog.addCustom"), action: addCustom)
                        .disabled(customName.trimmed.isEmpty)
                }
                .frame(minHeight: 44)
                if let customError {
                    Text(customError).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text(L10n.t("catalog.custom"))
            } footer: {
                Text(L10n.t("catalog.customFooter"))
            }
        }
        .searchable(text: $search, prompt: L10n.t("catalog.search"))
        .onChange(of: customName) { _, _ in customError = nil }
    }

    private func toggle(_ choice: ItemChoiceDraft) {
        if let i = picked.firstIndex(of: choice) { picked.remove(at: i) } else { picked.append(choice) }
    }

    private func addCustom() {
        let name = customName.trimmed
        guard !name.isEmpty else { return }
        if picked.contains(where: { ItemNameRules.key($0.displayName) == ItemNameRules.key(name) }) {
            customError = L10n.f("error.duplicate", name)
            return
        }
        switch ItemNameRules.conflict(for: name, editingItemID: nil, items: items.map(\.info)) {
        case .active(let other), .archived(let other):
            customError = L10n.f("error.duplicate", other.name)
        case .catalog(let c):
            // It's in the catalog: tick that one instead, so it gets translations.
            if !picked.contains(.catalog(c.key)) { picked.append(.catalog(c.key)) }
            customError = L10n.f("catalog.usedCatalog", c.name(lang))
            customName = ""
        case .none:
            picked.append(.custom(name))
            customName = ""
        }
    }
}

struct CheckRow: View {
    let title: String
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary).lineLimit(2)
                Spacer()
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("check.\(title)")
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// Second step: schedule settings and last replacement for every picked item.
/// Interval items: km/months (+ last replacement). Expiry items: "valid until". Seasonal items: months.
struct BulkSetupView: View {
    let choices: [ItemChoiceDraft]
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var readings: [OdometerReading]
    @Query private var entries: [ServiceEntry]

    struct Row {
        var kind: ItemKind = .interval
        var km: Int?
        var months: Int?
        var date: Date?
        var odometer: Int?
        var validUntil: Date?
        var season: Set<Int> = []
    }

    @State private var rows: [Row] = []
    @State private var sameForAll = true
    @State private var dontKnow = false
    @State private var commonDate: Date?
    @State private var commonOdometer: Int?
    @State private var triedSave = false

    private var current: OdometerReadingInfo? {
        OdometerRules.current(readings: readings.map(\.info), entries: entries.map(\.info), calendar: Fmt.calendar)
    }

    private var hasIntervalItems: Bool { rows.contains { $0.kind == .interval } }

    var body: some View {
        Form {
            if hasIntervalItems {
                Section {
                    if current != nil {
                        Toggle(L10n.t("bulk.dontKnow"), isOn: $dontKnow).frame(minHeight: 44)
                    }
                    if !dontKnow {
                        Toggle(L10n.t("bulk.sameForAll"), isOn: $sameForAll).frame(minHeight: 44)
                        if sameForAll {
                            RequiredDateField(title: L10n.t("entry.date"), date: $commonDate)
                            FieldErrorText(error: ValidationRules.pastOrToday(commonDate, now: Date(), calendar: Fmt.calendar),
                                           show: triedSave)
                            LabeledField(label: L10n.t("entry.odometer")) {
                                NumberField(title: L10n.t("entry.km"), value: $commonOdometer).frame(maxWidth: 140)
                            }
                            FieldErrorText(error: ValidationRules.number(commonOdometer, required: true, range: Limits.odometer),
                                           show: triedSave)
                        }
                    }
                } header: {
                    Text(L10n.t("item.lastSection"))
                } footer: {
                    Text(dontKnow ? L10n.t("bulk.dontKnowFooter") : L10n.t("bulk.lastFooter"))
                }
            }

            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                if index < rows.count {
                    Section(choice.displayName) {
                        rowContent(index: index, choice: choice)
                    }
                }
            }
        }
        .navigationTitle(L10n.t("bulk.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.t("bulk.saveAll"), action: save).accessibilityIdentifier("bulk.save")
            }
        }
        .onAppear {
            guard rows.count != choices.count else { return }
            rows = choices.map { choice in
                var row = Row()
                if case .catalog(let key) = choice, let c = Catalog.item(key) {
                    row.kind = c.kind
                    row.season = Set(c.seasonMonths)
                }
                return row
            }
        }
    }

    @ViewBuilder
    private func rowContent(index: Int, choice: ItemChoiceDraft) -> some View {
        switch rows[index].kind {
        case .interval:
            LabeledField(label: L10n.t("item.intervalKm")) {
                NumberField(title: hint(km: choice), value: $rows[index].km).frame(maxWidth: 140)
            }
            FieldErrorText(error: ValidationRules.number(rows[index].km, required: false, range: Limits.intervalKm))
            LabeledField(label: L10n.t("item.intervalMonths")) {
                NumberField(title: hint(months: choice), value: $rows[index].months).frame(maxWidth: 140)
            }
            FieldErrorText(error: ValidationRules.number(rows[index].months, required: false, range: Limits.intervalMonths))
            if triedSave && rows[index].km == nil && rows[index].months == nil {
                Text(L10n.t("item.needInterval")).font(.footnote).foregroundStyle(.red)
            }
            if !dontKnow && !sameForAll {
                RequiredDateField(title: L10n.t("item.lastSection"), date: $rows[index].date)
                FieldErrorText(error: ValidationRules.pastOrToday(rows[index].date, now: Date(), calendar: Fmt.calendar),
                               show: triedSave)
                LabeledField(label: L10n.t("entry.odometer")) {
                    NumberField(title: L10n.t("entry.km"), value: $rows[index].odometer).frame(maxWidth: 140)
                }
                FieldErrorText(error: ValidationRules.number(rows[index].odometer, required: true, range: Limits.odometer),
                               show: triedSave)
            }
        case .expiry:
            OptionalFutureDateRow(title: L10n.t("item.validUntil"), date: $rows[index].validUntil)
        case .seasonal:
            SeasonMonthsGrid(selected: $rows[index].season)
            if triedSave && rows[index].season.isEmpty {
                Text(L10n.t("item.needMonths")).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func hint(km choice: ItemChoiceDraft) -> String {
        guard case .catalog(let key) = choice, let v = Catalog.item(key)?.hintKm else { return L10n.t("item.optional") }
        return L10n.f("hint.usually", AssistantFormat.groupDigits(v, separator: "\u{00A0}"))
    }

    private func hint(months choice: ItemChoiceDraft) -> String {
        guard case .catalog(let key) = choice, let v = Catalog.item(key)?.hintMonths else { return L10n.t("item.optional") }
        return L10n.f("hint.usually", String(v))
    }

    private var isValid: Bool {
        let now = Date(), cal = Fmt.calendar
        for r in rows {
            switch r.kind {
            case .interval:
                if r.km == nil && r.months == nil { return false }
                if ValidationRules.number(r.km, required: false, range: Limits.intervalKm) != nil { return false }
                if ValidationRules.number(r.months, required: false, range: Limits.intervalMonths) != nil { return false }
                if !dontKnow && !sameForAll {
                    if ValidationRules.pastOrToday(r.date, now: now, calendar: cal) != nil { return false }
                    if ValidationRules.number(r.odometer, required: true, range: Limits.odometer) != nil { return false }
                }
            case .seasonal:
                if r.season.isEmpty { return false }
            case .expiry:
                break
            }
        }
        if hasIntervalItems && !dontKnow && sameForAll {
            if ValidationRules.pastOrToday(commonDate, now: now, calendar: cal) != nil { return false }
            if ValidationRules.number(commonOdometer, required: true, range: Limits.odometer) != nil { return false }
        }
        return true
    }

    private func save() {
        triedSave = true
        guard isValid else { return }
        var created: [(Item, Row)] = []
        for (index, choice) in choices.enumerated() {
            let row = rows[index]
            let item = ItemActions.makeItem(choice, order: index, context: context)
            item.kind = row.kind
            item.intervalKm = row.kind == .interval ? row.km : nil
            item.intervalMonths = row.kind == .interval ? row.months : nil
            item.seasonMonths = row.season.sorted()
            item.validUntil = row.kind == .expiry ? row.validUntil : nil
            created.append((item, row))
        }
        let intervalItems = created.filter { $0.1.kind == .interval }.map(\.0)
        if !intervalItems.isEmpty {
            if dontKnow, let cur = current {
                context.insert(ServiceEntry(date: Date(), odometerKm: cur.km, items: intervalItems))
            } else if sameForAll, let d = commonDate, let km = commonOdometer {
                context.insert(ServiceEntry(date: d, odometerKm: km, items: intervalItems))
            } else {
                for (item, row) in created where row.kind == .interval {
                    if let d = row.date, let km = row.odometer {
                        context.insert(ServiceEntry(date: d, odometerKm: km, items: [item]))
                    }
                }
            }
        }
        DataEvents.changed(context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSaved()
    }
}
