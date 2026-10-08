import SwiftUI
import SwiftData
import CarCareCore

struct HistoryView: View {
    enum Mode: Hashable { case byDate, byItem }

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: Router
    @Query(sort: [SortDescriptor(\ServiceEntry.date, order: .reverse),
                  SortDescriptor(\ServiceEntry.odometerKm, order: .reverse)])
    private var entries: [ServiceEntry]
    @Query(sort: \Item.createdAt) private var items: [Item]

    @State private var mode: Mode = .byDate
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                if !entries.isEmpty {
                    Picker("", selection: $mode) {
                        Text(L10n.t("history.byDate")).tag(Mode.byDate)
                        Text(L10n.t("history.byItem")).tag(Mode.byItem)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .disabled(selecting)
                }
                if entries.isEmpty {
                    Banner(icon: "plus.circle", text: L10n.t("history.empty"),
                           actionTitle: L10n.t("add.logService")) { router.open(.logService([])) }
                }
                if mode == .byDate {
                    ForEach(entries) { entry in
                        Button {
                            if selecting { toggle(entry.uuid) } else { router.open(.editEntry(entry)) }
                        } label: {
                            HStack(spacing: 12) {
                                if selecting { SelectionMark(selected: selection.contains(entry.uuid)) }
                                EntryRow(entry: entry)
                            }
                        }
                        .foregroundStyle(.primary)
                        // Long press → menu with "Select". A long-press gesture on the row itself blocks
                        // scrolling and taps (iOS 18).
                        .contextMenu {
                            if !selecting {
                                Button(L10n.t("select.start"), systemImage: "checkmark.circle") {
                                    startSelecting(with: entry.uuid)
                                }
                            }
                        }
                        .swipeActions {
                            if !selecting {
                                Button(L10n.t("common.delete"), role: .destructive) {
                                    selection = [entry.uuid]
                                    confirmDelete = true
                                }
                            }
                        }
                    }
                } else {
                    ForEach(itemsWithHistory) { item in
                        NavigationLink {
                            ItemHistoryView(item: item)
                        } label: {
                            ItemHistorySummaryRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("tab.history"))
            .toolbar {
                if mode == .byDate && !entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selecting ? L10n.t("common.done") : L10n.t("select.start")) {
                            selecting.toggle()
                            selection = []
                        }
                        .accessibilityIdentifier("history.select")
                    }
                }
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .primaryAction) { AddMenuButton() }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    SelectionBar(count: selection.count, allSelected: selection.count == entries.count,
                                 actionTitle: L10n.f("select.delete", selection.count)) {
                        selection = selection.count == entries.count ? [] : Set(entries.map(\.uuid))
                    } action: {
                        confirmDelete = true
                    }
                }
            }
            .confirmationDialog(L10n.f("history.deleteMany", selection.count), isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button(L10n.t("common.delete"), role: .destructive) {
                    for e in entries where selection.contains(e.uuid) { context.delete(e) }
                    selection = []
                    selecting = false
                    DataEvents.changed(context)
                }
            }
        }
    }

    private var itemsWithHistory: [Item] {
        items.filter { ItemActions.hasHistory($0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func startSelecting(with id: UUID) {
        guard !selecting else { return }
        selecting = true
        selection = [id]
    }
}

struct SelectionMark: View {
    let selected: Bool

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
    }
}

/// Bottom bar in selection mode: "Select all / Deselect all" and a destructive action.
struct SelectionBar: View {
    let count: Int
    let allSelected: Bool
    let actionTitle: String
    let toggleAll: () -> Void
    let action: () -> Void

    var body: some View {
        HStack {
            Button(allSelected ? L10n.t("select.none") : L10n.t("select.all"), action: toggleAll)
                .frame(minHeight: 44)
            Spacer()
            Button(actionTitle, role: .destructive, action: action)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(count == 0)
                .accessibilityIdentifier("select.action")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// History row: what was replaced (names as recorded), with date and odometer labeled by icons.
struct EntryRow: View {
    let entry: ServiceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.displayNames.joined(separator: ", "))
                .font(.body.weight(.medium))
                .lineLimit(3)
            HStack(spacing: 14) {
                Label(Fmt.date(entry.date), systemImage: "calendar")
                Label(Fmt.km(entry.odometerKm), systemImage: "gauge.with.dots.needle.33percent")
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// "By item" row: name, number of replacements, the last one.
struct ItemHistorySummaryRow: View {
    let item: Item

    var body: some View {
        let list = (item.entries ?? []).sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.displayName).font(.body.weight(.medium)).lineLimit(2)
                if item.isArchived {
                    Text(L10n.t("parts.archivedBadge")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let last = list.first {
                Text(L10n.f("history.itemSummary", list.count, Fmt.date(last.date), Fmt.km(last.odometerKm)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// All replacements of one item, newest first, with the distance between them.
struct ItemHistoryList: View {
    let item: Item

    var body: some View {
        let list = (item.entries ?? []).sorted { a, b in a.date != b.date ? a.date > b.date : a.odometerKm > b.odometerKm }
        if list.isEmpty {
            Text(L10n.t("item.noRecords")).foregroundStyle(.secondary)
        }
        ForEach(Array(list.enumerated()), id: \.element.uuid) { index, entry in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 14) {
                    Label(Fmt.date(entry.date), systemImage: "calendar")
                    Label(Fmt.km(entry.odometerKm), systemImage: "gauge.with.dots.needle.33percent").monospacedDigit()
                }
                .font(.subheadline)
                if index + 1 < list.count {
                    let prev = list[index + 1]
                    let km = entry.odometerKm - prev.odometerKm
                    let months = Fmt.calendar.dateComponents([.month], from: prev.date, to: entry.date).month ?? 0
                    Text(L10n.f("history.sincePrevious", Fmt.km(max(km, 0)), months))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct ItemHistoryView: View {
    let item: Item
    @EnvironmentObject private var router: Router

    var body: some View {
        List {
            Section {
                ItemHistoryList(item: item)
            } header: {
                Text(L10n.f("history.count", (item.entries ?? []).count))
            }
            if !item.isArchived {
                Section {
                    Button {
                        router.open(.logService([item.uuid]))
                    } label: {
                        Label(L10n.t("add.logService"), systemImage: "checkmark.circle").frame(minHeight: 44)
                    }
                }
            }
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A position chosen in "Log service": an existing item, or a catalog/custom one created on save.
struct PickedItem: Hashable, Identifiable {
    enum Kind: Hashable {
        case existing(UUID)
        case draft(ItemChoiceDraft)
    }

    let kind: Kind
    let name: String
    var id: Kind { kind }
}

/// "Log service": date and odometer are required and start empty, so nothing is recorded "by default".
/// Optional: total cost or a price per item, a note, and "valid until" for insurance-like items.
struct EntryEditorView: View {
    let entry: ServiceEntry?
    let preselected: [UUID]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: AppSettings
    @Query(sort: \Item.createdAt) private var allItems: [Item]
    @Query private var readings: [OdometerReading]
    @Query private var entries: [ServiceEntry]

    @State private var date: Date?
    @State private var odometer: Int?
    @State private var selected: [PickedItem] = []
    @State private var splitCosts = false
    @State private var total: Double?
    @State private var itemCosts: [PickedItem.Kind: Double] = [:]
    @State private var validUntil: [PickedItem.Kind: Date] = [:]
    @State private var note = ""
    @State private var showPicker = false
    @State private var loaded = false
    @State private var triedSave = false
    @State private var confirmLower = false
    @State private var confirmDelete = false

    private var currency: Currency { entry?.currency ?? settings.currency }
    private var dateError: FieldError? { ValidationRules.pastOrToday(date, now: Date(), calendar: Fmt.calendar) }
    private var kmError: FieldError? { ValidationRules.number(odometer, required: true, range: Limits.odometer) }
    private var isValid: Bool { dateError == nil && kmError == nil && !selected.isEmpty }

    /// Current odometer without this entry (so editing it doesn't compare with itself).
    private var currentOther: OdometerReadingInfo? {
        OdometerRules.current(readings: readings.map(\.info),
                              entries: entries.filter { $0.uuid != entry?.uuid }.map(\.info), calendar: Fmt.calendar)
    }

    private func kind(of p: PickedItem) -> ItemKind {
        switch p.kind {
        case .existing(let id): return allItems.first { $0.uuid == id }?.kind ?? .interval
        case .draft(.catalog(let key)): return Catalog.item(key)?.kind ?? .interval
        case .draft(.custom(_)): return .interval
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RequiredDateField(title: L10n.t("entry.date"), date: $date)
                    FieldErrorText(error: dateError, show: triedSave)
                    LabeledField(label: L10n.t("entry.odometer")) {
                        NumberField(title: L10n.t("entry.km"), value: $odometer).frame(maxWidth: 140)
                            .accessibilityIdentifier("entry.odometer")
                    }
                    FieldErrorText(error: kmError, show: triedSave)
                } footer: {
                    if let cur = currentOther {
                        Text(L10n.f("odometer.current", Fmt.km(cur.km), Fmt.date(cur.date)))
                    }
                }

                Section {
                    ForEach(selected) { p in
                        HStack {
                            Text(p.name).lineLimit(2)
                            Spacer()
                            if splitCosts {
                                MoneyField(currency: currency, value: Binding(
                                    get: { itemCosts[p.kind] },
                                    set: { itemCosts[p.kind] = $0 }))
                                    .frame(maxWidth: 110)
                            } else if case .draft = p.kind {
                                Text(L10n.t("entry.newItemBadge")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 36)
                    }
                    .onDelete { selected.remove(atOffsets: $0) }
                    Button {
                        showPicker = true
                    } label: {
                        Label(L10n.t("entry.pickParts"), systemImage: "plus.circle").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("entry.pick")
                } header: {
                    Text(L10n.t("entry.parts"))
                } footer: {
                    if selected.isEmpty && triedSave {
                        Text(L10n.t("entry.needParts")).foregroundStyle(.red)
                    } else if selected.contains(where: { if case .draft = $0.kind { return true } else { return false } }) {
                        Text(L10n.t("entry.newItemsFooter"))
                    }
                }

                let expiring = selected.filter { kind(of: $0) == .expiry }
                if !expiring.isEmpty {
                    Section {
                        ForEach(expiring) { p in
                            OptionalFutureDateRow(title: p.name, date: Binding(
                                get: { validUntil[p.kind] },
                                set: { validUntil[p.kind] = $0 }))
                        }
                    } header: {
                        Text(L10n.t("entry.validUntil"))
                    } footer: {
                        Text(L10n.t("entry.validUntilFooter"))
                    }
                }

                Section {
                    if selected.count > 1 {
                        Toggle(L10n.t("entry.splitCosts"), isOn: $splitCosts).frame(minHeight: 44)
                    }
                    if splitCosts && selected.count > 1 {
                        LabeledField(label: L10n.t("entry.total")) {
                            Text(AssistantFormat.money(itemCosts.values.reduce(0, +), currency, L10n.assistantLanguage))
                                .fontWeight(.semibold)
                        }
                    } else {
                        LabeledField(label: L10n.t("entry.total")) {
                            MoneyField(currency: currency, value: $total).frame(maxWidth: 140)
                        }
                    }
                } header: {
                    Text(L10n.t("entry.cost"))
                }

                Section {
                    TextField(L10n.t("entry.notePlaceholder"), text: $note, axis: .vertical)
                        .limitLength($note, 500)
                        .lineLimit(2...6)
                } header: {
                    Text(L10n.t("entry.note"))
                }

                if entry != nil {
                    Section {
                        Button(L10n.t("entry.delete"), role: .destructive) { confirmDelete = true }
                            .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle(entry == nil ? L10n.t("entry.newTitle") : L10n.t("entry.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.save")) { trySave() }.accessibilityIdentifier("entry.save")
                }
            }
            .sheet(isPresented: $showPicker) {
                ItemPickerView(selected: $selected)
            }
            .alert(L10n.t("odometer.lowerTitle"), isPresented: $confirmLower) {
                Button(L10n.t("common.saveAnyway")) { save() }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("entry.lowerText"))
            }
            .confirmationDialog(L10n.t("entry.deleteConfirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L10n.t("common.delete"), role: .destructive) {
                    if let e = entry { context.delete(e) }
                    DataEvents.changed(context)
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let source: [Item]
        if let e = entry {
            date = e.date
            odometer = e.odometerKm
            source = e.sortedItems
            note = e.note
            total = e.costTotal
            splitCosts = e.hasSplitCosts
            for s in e.snapshot { if let c = s.cost { itemCosts[.existing(s.itemID)] = c } }
        } else {
            source = preselected.compactMap { id in allItems.first { $0.uuid == id } }
        }
        selected = source.map { PickedItem(kind: .existing($0.uuid), name: $0.displayName) }
        for item in source where item.kind == .expiry {
            if let until = item.validUntil { validUntil[.existing(item.uuid)] = until }
        }
    }

    private func trySave() {
        triedSave = true
        guard isValid, let km = odometer, let d = date else { return }
        // Lower than the current odometer while being the newest record: probably a typo.
        if let cur = currentOther, km < cur.km,
           Fmt.calendar.startOfDay(for: d) >= Fmt.calendar.startOfDay(for: cur.date) {
            confirmLower = true
        } else {
            save()
        }
    }

    private func save() {
        guard let km = odometer, let d = date else { return }
        var resolved: [Item] = []
        var costs: [UUID: Double] = [:]
        for (index, p) in selected.enumerated() {
            let item: Item?
            switch p.kind {
            case .existing(let id):
                item = allItems.first { $0.uuid == id }
            case .draft(let draft):
                item = ItemActions.makeItem(draft, order: index, context: context)
            }
            guard let item else { continue }
            resolved.append(item)
            if let until = validUntil[p.kind] { item.validUntil = until }
            if splitCosts, let c = itemCosts[p.kind] { costs[item.uuid] = c }
        }
        let target: ServiceEntry
        if let e = entry {
            target = e
            e.date = d
            e.odometerKm = km
            e.setItems(resolved)
        } else {
            target = ServiceEntry(date: d, odometerKm: km, items: resolved)
            target.currency = settings.currency
            context.insert(target)
        }
        target.note = note.trimmed
        if splitCosts && resolved.count > 1 {
            target.setItemCosts(costs)
            if costs.isEmpty { target.costTotal = nil }
        } else {
            target.setItemCosts([:])
            target.costTotal = (total ?? 0) > 0 ? total : nil
        }
        DataEvents.changed(context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// Multi-select: your schedule, then the catalog, then "Custom item «…»" for a search with no match.
/// A "Done · N selected" bar stays visible even while searching.
struct ItemPickerView: View {
    @Binding var selected: [PickedItem]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            PickerList(selected: $selected, search: search)
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: L10n.t("picker.search"))
                .navigationTitle(L10n.t("entry.parts"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.t("common.done")) { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !selected.isEmpty {
                        Button {
                            dismiss()
                        } label: {
                            Text(L10n.f("picker.doneCount", selected.count)).frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("picker.done")
                    }
                }
        }
    }
}

private struct PickerList: View {
    @Binding var selected: [PickedItem]
    let search: String

    @Environment(\.dismissSearch) private var dismissSearch
    @Query(sort: \Item.createdAt) private var items: [Item]
    @State private var showCatalog = false
    @State private var customHint: String?

    private var lang: AssistantLanguage { L10n.assistantLanguage }
    private var query: String { search.trimmed }

    private func matches(_ names: [String]) -> Bool {
        query.isEmpty || names.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let active = items.filter { !$0.isArchived && matches([$0.displayName] + $0.aliases) }
        let usedKeys = Set(items.compactMap(\.catalogKey))
        let catalog = Catalog.items.filter { !usedKeys.contains($0.key) && matches($0.allNames + $0.synonyms) }
            .sorted { $0.name(lang).localizedCaseInsensitiveCompare($1.name(lang)) == .orderedAscending }
        let drafts = selected.filter { if case .draft(.custom(_)) = $0.kind { return true } else { return false } }

        List {
            if !drafts.isEmpty {
                Section(L10n.t("catalog.yourCustom")) {
                    ForEach(drafts) { p in
                        CheckRow(title: p.name, checked: true) { selected.removeAll { $0.id == p.id } }
                    }
                }
            }
            Section(L10n.t("picker.yourSchedule")) {
                if items.allSatisfy(\.isArchived) {
                    Text(L10n.t("picker.emptySchedule")).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(active) { item in
                    let p = PickedItem(kind: .existing(item.uuid), name: item.displayName)
                    CheckRow(title: item.displayName, checked: selected.contains(p)) { toggle(p) }
                }
            }
            if !query.isEmpty && !hasExactMatch(active: active, catalog: catalog) {
                Section {
                    Button {
                        addCustom()
                    } label: {
                        Label(L10n.f("picker.createCustom", query), systemImage: "plus.circle.fill").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("picker.createCustom")
                    if let customHint {
                        Text(customHint).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if !catalog.isEmpty {
                Section {
                    if query.isEmpty {
                        DisclosureGroup(L10n.f("picker.catalog", catalog.count), isExpanded: $showCatalog) {
                            catalogRows(catalog)
                        }
                    } else {
                        catalogRows(catalog)
                    }
                } header: {
                    if !query.isEmpty { Text(L10n.t("picker.catalogHeader")) }
                } footer: {
                    Text(L10n.t("picker.catalogFooter"))
                }
            }
        }
    }

    @ViewBuilder
    private func catalogRows(_ list: [CatalogItem]) -> some View {
        ForEach(list) { c in
            let p = PickedItem(kind: .draft(.catalog(c.key)), name: c.name(lang))
            CheckRow(title: c.name(lang), checked: selected.contains(p)) { toggle(p) }
        }
    }

    private func hasExactMatch(active: [Item], catalog: [CatalogItem]) -> Bool {
        let k = ItemNameRules.key(query)
        return active.contains { ItemNameRules.key($0.displayName) == k }
            || catalog.contains { $0.allNames.contains { ItemNameRules.key($0) == k } }
            || selected.contains { ItemNameRules.key($0.name) == k }
    }

    private func toggle(_ p: PickedItem) {
        if let i = selected.firstIndex(of: p) { selected.remove(at: i) } else { selected.append(p) }
        dismissSearch()
    }

    private func addCustom() {
        let name = String(query.prefix(Limits.itemName))
        switch ItemNameRules.conflict(for: name, editingItemID: nil, items: items.map(\.info)) {
        case .active(let other):
            let p = PickedItem(kind: .existing(other.id), name: other.name)
            if !selected.contains(p) { selected.append(p) }
        case .archived(let other):
            customHint = L10n.f("picker.inArchive", other.name)
            return
        case .catalog(let c):
            let p = PickedItem(kind: .draft(.catalog(c.key)), name: c.name(lang))
            if !selected.contains(p) { selected.append(p) }
        case .none:
            selected.append(PickedItem(kind: .draft(.custom(name)), name: name))
        }
        customHint = nil
        dismissSearch()
    }
}
