import SwiftUI
import SwiftData
import CarCareCore

/// "Schedule" tab: what the user maintains and how often, the most urgent on top.
/// Items without an interval and archived items are separate blocks at the bottom.
struct PartsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: Router
    @Query(sort: \Item.createdAt) private var items: [Item]
    @Query private var entries: [ServiceEntry]
    @Query private var readings: [OdometerReading]
    @Query private var cars: [Car]

    @State private var search = ""
    @State private var pendingDelete: Item?
    @State private var restoreBlocked: String?
    @State private var showArchive = false
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var confirmBulk = false

    private func matches(_ item: Item) -> Bool {
        let q = search.trimmed
        guard !q.isEmpty else { return true }
        return ([item.displayName] + item.aliases + [item.oemNumber ?? ""] + item.analogNumbers)
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            let now = Date()
            let snapshot = SnapshotBuilder.make(cars: cars, items: items, entries: entries, readings: readings)
            let statuses = ForecastEngine.statuses(for: snapshot, today: now, calendar: Fmt.calendar)
            let current = snapshot.currentOdometerKm
            let byID = Dictionary(items.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
            let active = ForecastEngine.urgencySorted(snapshot.activeItems, statuses: statuses)
                .compactMap { byID[$0.id] }.filter(matches)
            let scheduled = active.filter { $0.info.hasInterval }
            let noInterval = active.filter { !$0.info.hasInterval }
            let archived = items.filter { $0.isArchived && matches($0) }

            List {
                if items.isEmpty {
                    Banner(icon: "list.bullet.clipboard", text: L10n.t("parts.empty"),
                           actionTitle: L10n.t("add.item")) { router.open(.addItems) }
                }
                Section {
                    ForEach(scheduled) { item in
                        itemButton(item, snapshot: snapshot, status: statuses[item.uuid], now: now, current: current)
                    }
                }
                if !noInterval.isEmpty {
                    Section {
                        ForEach(noInterval) { item in
                            itemButton(item, snapshot: snapshot, status: nil, now: now, current: current)
                        }
                    } header: {
                        Text(L10n.t("parts.noIntervalTitle"))
                    } footer: {
                        Text(L10n.t("parts.noIntervalFooter"))
                    }
                }
                if !archived.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showArchive) {
                            ForEach(archived) { item in
                                itemButton(item, snapshot: snapshot, status: nil, now: now, current: current)
                            }
                        } label: {
                            Text(L10n.f("parts.archiveTitle", archived.count)).font(.headline)
                                .accessibilityIdentifier("parts.archive")
                        }
                    } footer: {
                        Text(L10n.t("parts.archiveFooter"))
                    }
                }
            }
            .searchable(text: $search, prompt: L10n.t("parts.search"))
            .navigationTitle(L10n.t("tab.parts"))
            .toolbar {
                if !items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selecting ? L10n.t("common.done") : L10n.t("select.start")) {
                            selecting.toggle()
                            selection = []
                        }
                        .accessibilityIdentifier("parts.select")
                    }
                }
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .primaryAction) { AddMenuButton() }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    SelectionBar(count: selection.count, allSelected: selection.count == items.count,
                                 actionTitle: L10n.f("select.archiveOrDelete", selection.count)) {
                        selection = selection.count == items.count ? [] : Set(items.map(\.uuid))
                    } action: {
                        confirmBulk = true
                    }
                }
            }
            .confirmationDialog(bulkTitle, isPresented: $confirmBulk, titleVisibility: .visible) {
                Button(L10n.t("select.confirm"), role: .destructive) { applyBulk() }
            }
            .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil },
                                                                  set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button(L10n.t("common.delete"), role: .destructive) {
                    if let item = pendingDelete { context.delete(item) }
                    pendingDelete = nil
                    DataEvents.changed(context)
                }
            }
            .alert(restoreBlocked ?? "", isPresented: Binding(get: { restoreBlocked != nil },
                                                             set: { if !$0 { restoreBlocked = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func itemButton(_ item: Item, snapshot: DataSnapshot, status: ItemStatus?, now: Date, current: Int?) -> some View {
        Button {
            if selecting { toggle(item.uuid) } else { router.open(.item(item)) }
        } label: {
            HStack(spacing: 12) {
                if selecting { SelectionMark(selected: selection.contains(item.uuid)) }
                ItemRow(item: item, snapshot: snapshot, status: status, today: now, currentKm: current)
            }
        }
        .foregroundStyle(item.isArchived ? .secondary : .primary)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            if !selecting { selecting = true; selection = [item.uuid] }
        })
        .swipeActions {
            if !selecting {
                if item.isArchived {
                    Button(L10n.t("common.delete"), role: .destructive) { pendingDelete = item }
                    Button(L10n.t("parts.restore")) { restore(item) }.tint(.green)
                } else if ItemActions.hasHistory(item) {
                    Button(L10n.t("parts.archive")) {
                        item.isArchived = true
                        DataEvents.changed(context)
                    }
                    .tint(.orange)
                } else {
                    Button(L10n.t("common.delete"), role: .destructive) { pendingDelete = item }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// Items with history go to the archive (history stays), the rest is deleted. Archived items are deleted.
    private var bulkSplit: (archive: [Item], delete: [Item]) {
        let chosen = items.filter { selection.contains($0.uuid) }
        let archive = chosen.filter { !$0.isArchived && ItemActions.hasHistory($0) }
        let archiveIDs = Set(archive.map(\.uuid))
        return (archive, chosen.filter { !archiveIDs.contains($0.uuid) })
    }

    private var bulkTitle: String {
        let s = bulkSplit
        return L10n.f("select.archiveDeleteSummary", s.archive.count, s.delete.count)
    }

    private func applyBulk() {
        let s = bulkSplit
        for item in s.archive { item.isArchived = true }
        for item in s.delete { context.delete(item) }
        selection = []
        selecting = false
        DataEvents.changed(context)
    }

    private var deleteTitle: String {
        guard let item = pendingDelete else { return "" }
        return ItemActions.hasHistory(item) ? L10n.f("parts.deleteKeepsHistory", item.displayName)
                                            : L10n.f("parts.deleteConfirm", item.displayName)
    }

    private func restore(_ item: Item) {
        if case .active(let other) = ItemNameRules.conflict(for: item.displayName, editingItemID: item.uuid,
                                                             items: items.map(\.info)) {
            restoreBlocked = L10n.f("parts.restoreBlocked", other.name)
            return
        }
        item.isArchived = false
        DataEvents.changed(context)
    }
}

/// Schedule row: wear ring, name, interval, last replacement, next one.
struct ItemRow: View {
    let item: Item
    let snapshot: DataSnapshot
    let status: ItemStatus?
    let today: Date
    let currentKm: Int?

    var body: some View {
        let forecast = status?.forecast
        let urgency = forecast?.urgency(today: today, calendar: Fmt.calendar, currentOdometerKm: currentKm)
        let wear = forecast.flatMap {
            ForecastEngine.wear(item: item.info, forecast: $0, entries: snapshot.entries, currentOdometerKm: currentKm,
                                today: today)
        }
        HStack(alignment: .center, spacing: 12) {
            WearRing(fraction: wear, urgency: urgency, overdue: forecast?.isOverdue == true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                let interval = Self.scheduleText(item)
                if !interval.isEmpty {
                    Text(interval).font(.subheadline)
                }
                if let last = ForecastEngine.lastEntry(for: item.uuid, entries: snapshot.entries) {
                    Text(L10n.f("parts.lastLine", Fmt.km(last.odometerKm), Fmt.date(last.date))).font(.subheadline)
                }
                if let f = forecast {
                    Text(ForecastText.detail(kind: item.kind, forecast: f, currentKm: currentKm, today: today))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(f.isOverdue ? Color.red : (urgency ?? .ok).textColor)
                }
            }
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// "every 10 000 km · 12 mo" / "valid until 15 Nov 2026" / "season: Apr, Oct".
    static func scheduleText(_ item: Item) -> String {
        switch item.kind {
        case .interval:
            return intervalText(km: item.intervalKm, months: item.intervalMonths)
        case .expiry:
            return item.validUntil.map { L10n.f("text.validUntil", Fmt.date($0)) } ?? L10n.t("parts.noValidUntil")
        case .seasonal:
            return L10n.f("parts.seasonMonths", item.seasonMonths.sorted().map(Fmt.shortMonth).joined(separator: ", "))
        }
    }

    static func intervalText(km: Int?, months: Int?) -> String {
        var parts: [String] = []
        if let km, km > 0 { parts.append(L10n.f("parts.everyKm", Fmt.km(km))) }
        if let m = months, m > 0 { parts.append(L10n.f("parts.everyMonths", m)) }
        return parts.joined(separator: " · ")
    }
}

/// Ring showing how much of the interval is used; "!" when overdue, empty gray ring when unknown.
struct WearRing: View {
    let fraction: Double?
    let urgency: Urgency?
    let overdue: Bool

    var body: some View {
        let color = urgency?.color ?? Color.secondary
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 5)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: fraction)
                Text(overdue ? "!" : "\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: overdue ? 15 : 10, weight: .bold, design: .rounded))
                    .foregroundStyle(urgency?.textColor ?? .secondary)
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

/// Item card. Catalog items have a fixed (translated) name; custom names can be edited. A new item (only for
/// "It's a different part") needs its last replacement. Shows the item's full replacement history.
struct ItemEditorView: View {
    let item: Item?
    let draft: Router.ItemDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: Router
    @Query(sort: \Item.createdAt) private var allItems: [Item]
    @Query private var entries: [ServiceEntry]
    @Query private var readings: [OdometerReading]

    @State private var name = ""
    @State private var aliases = ""
    @State private var intervalKm: Int?
    @State private var intervalMonths: Int?
    @State private var kind: ItemKind = .interval
    @State private var seasonMonths: Set<Int> = []
    @State private var validUntil: Date?
    @State private var oem = ""
    @State private var analogs = ""
    @State private var lastDate: Date?
    @State private var lastKm: Int?
    @State private var showMore = false
    @State private var loaded = false
    @State private var triedSave = false

    // Save flow, step by step.
    @State private var askArchivedDuplicate: ItemInfo?
    @State private var askRename = false
    @State private var askReplaceOEM = false
    @State private var keepOldOEM = false
    @State private var conflictText = ""
    @State private var askConflict = false

    private var isNew: Bool { item == nil }
    private var isCatalog: Bool { item?.isFromCatalog == true }
    private var catalogItem: CatalogItem? { Catalog.item(item?.catalogKey) }

    private var currentOdometer: OdometerReadingInfo? {
        OdometerRules.current(readings: readings.map(\.info), entries: entries.map(\.info), calendar: Fmt.calendar)
    }

    private var nameConflict: ItemNameRules.Conflict {
        isCatalog ? .none : ItemNameRules.conflict(for: name, editingItemID: item?.uuid, items: allItems.map(\.info))
    }

    private var nameError: FieldError? {
        if isCatalog { return nil }
        if let e = ValidationRules.text(name, required: true, max: Limits.itemName) { return e }
        if case .active(let other) = nameConflict { return .duplicate(name: other.name) }
        return nil
    }
    private var kmError: FieldError? { ValidationRules.number(intervalKm, required: false, range: Limits.intervalKm) }
    private var monthsError: FieldError? {
        ValidationRules.number(intervalMonths, required: false, range: Limits.intervalMonths)
    }
    /// Only interval items need a last replacement to count from.
    private var needsLast: Bool { isNew && kind == .interval }
    private var lastDateError: FieldError? {
        needsLast ? ValidationRules.pastOrToday(lastDate, now: Date(), calendar: Fmt.calendar) : nil
    }
    private var lastKmError: FieldError? {
        needsLast ? ValidationRules.number(lastKm, required: true, range: Limits.odometer) : nil
    }
    /// Interval items need km or months; seasonal items at least one month.
    private var scheduleMissing: Bool {
        switch kind {
        case .interval: return intervalKm == nil && intervalMonths == nil
        case .seasonal: return seasonMonths.isEmpty
        case .expiry: return false
        }
    }
    private var isValid: Bool {
        [nameError, kmError, monthsError, lastDateError, lastKmError].allSatisfy { $0 == nil } && !scheduleMissing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isCatalog {
                        LabeledField(label: L10n.t("item.nameLabel")) {
                            Text(item?.displayName ?? "").foregroundStyle(.secondary)
                        }
                    } else {
                        TextField(L10n.t("item.name"), text: $name)
                            .limitLength($name, Limits.itemName)
                            .frame(minHeight: 44)
                        FieldErrorText(error: nameError, show: triedSave || nameError != .required)
                        if case .catalog(let c) = nameConflict {
                            Text(L10n.f("item.inCatalog", c.name(L10n.assistantLanguage)))
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                } footer: {
                    if isCatalog { Text(L10n.t("item.catalogNameFooter")) }
                }

                Section {
                    Picker("", selection: $kind) {
                        Text(L10n.t("kind.interval")).tag(ItemKind.interval)
                        Text(L10n.t("kind.expiry")).tag(ItemKind.expiry)
                        Text(L10n.t("kind.seasonal")).tag(ItemKind.seasonal)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    switch kind {
                    case .interval:
                        LabeledField(label: L10n.t("item.intervalKm")) {
                            NumberField(title: hintKm, value: $intervalKm).frame(maxWidth: 140)
                        }
                        FieldErrorText(error: kmError)
                        LabeledField(label: L10n.t("item.intervalMonths")) {
                            NumberField(title: hintMonths, value: $intervalMonths).frame(maxWidth: 140)
                        }
                        FieldErrorText(error: monthsError)
                    case .expiry:
                        OptionalFutureDateRow(title: L10n.t("item.validUntil"), date: $validUntil)
                    case .seasonal:
                        SeasonMonthsGrid(selected: $seasonMonths)
                    }
                    if scheduleMissing && triedSave {
                        Text(L10n.t(kind == .seasonal ? "item.needMonths" : "item.needInterval"))
                            .font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text(L10n.t("item.interval"))
                } footer: {
                    Text(L10n.t(kind == .interval ? "item.intervalFooter" : (kind == .expiry ? "item.expiryFooter"
                                                                                            : "item.seasonFooter")))
                }

                lastReplacementSection

                if let item, !isNew {
                    Section {
                        ItemHistoryList(item: item)
                    } header: {
                        Text(L10n.f("history.count", (item.entries ?? []).count))
                    }
                }

                Section {
                    DisclosureGroup(L10n.t("item.more"), isExpanded: $showMore) {
                        TextField(L10n.t("item.oem"), text: $oem)
                            .limitLength($oem, Limits.partNumber)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .frame(minHeight: 44)
                        TextField(L10n.t("item.analogs"), text: $analogs, axis: .vertical)
                            .limitLength($analogs, 300)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .frame(minHeight: 44)
                        TextField(L10n.t("item.aliases"), text: $aliases, axis: .vertical)
                            .limitLength($aliases, 200)
                            .frame(minHeight: 44)
                        Text(L10n.t("item.moreFooter")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isNew ? L10n.t("item.newTitle") : L10n.t("item.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.save")) { startSave() }.accessibilityIdentifier("item.save")
                }
            }
            .alert(L10n.f("item.archivedDuplicateTitle", askArchivedDuplicate?.name ?? ""),
                   isPresented: Binding(get: { askArchivedDuplicate != nil },
                                        set: { if !$0 { askArchivedDuplicate = nil } })) {
                Button(L10n.t("item.restoreFromArchive")) { restoreArchived() }
                Button(L10n.t("item.createNew")) { afterArchivedCheck() }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("item.archivedDuplicateText"))
            }
            .confirmationDialog(L10n.t("item.renameTitle"), isPresented: $askRename, titleVisibility: .visible) {
                Button(L10n.t("item.renameTypo")) { afterRenameCheck(typo: true) }
                Button(L10n.t("item.renameOther")) { differentPart() }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.f("item.renameText", item?.name ?? "", name.trimmed))
            }
            .confirmationDialog(L10n.t("item.replaceOEMTitle"), isPresented: $askReplaceOEM, titleVisibility: .visible) {
                Button(L10n.t("item.replace")) { keepOldOEM = false; checkNumberConflicts() }
                Button(L10n.t("item.keep")) { keepOldOEM = true; checkNumberConflicts() }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.f("item.replaceOEMText", item?.oemNumber ?? "", oem.trimmed))
            }
            .alert(L10n.t("item.duplicateTitle"), isPresented: $askConflict) {
                Button(L10n.t("common.saveAnyway")) { commit() }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(conflictText)
            }
            .onAppear(perform: load)
        }
    }

    private var hintKm: String {
        catalogItem?.hintKm.map { L10n.f("hint.usually", AssistantFormat.groupDigits($0, separator: "\u{00A0}")) }
            ?? L10n.t("item.optional")
    }

    private var hintMonths: String {
        catalogItem?.hintMonths.map { L10n.f("hint.usually", String($0)) } ?? L10n.t("item.optional")
    }

    @ViewBuilder
    private var lastReplacementSection: some View {
        if needsLast {
            Section {
                RequiredDateField(title: L10n.t("entry.date"), date: $lastDate)
                FieldErrorText(error: lastDateError, show: triedSave)
                LabeledField(label: L10n.t("entry.odometer")) {
                    NumberField(title: L10n.t("entry.km"), value: $lastKm).frame(maxWidth: 140)
                }
                FieldErrorText(error: lastKmError, show: triedSave)
                if let cur = currentOdometer {
                    Button {
                        lastDate = Date()
                        lastKm = cur.km
                    } label: {
                        Text(L10n.t("item.dontKnow")).frame(minHeight: 44)
                    }
                }
            } header: {
                Text(L10n.t("item.lastSection"))
            } footer: {
                Text(L10n.t("item.lastFooterNew"))
            }
        } else if let item {
            Section {
                if let last = ForecastEngine.lastEntry(for: item.uuid, entries: entries.map(\.info)) {
                    LabeledField(label: L10n.t("entry.date")) { Text(Fmt.date(last.date)).foregroundStyle(.secondary) }
                    LabeledField(label: L10n.t("entry.odometer")) {
                        Text(Fmt.km(last.odometerKm)).foregroundStyle(.secondary)
                    }
                } else {
                    Text(L10n.t("item.noRecords")).foregroundStyle(.secondary)
                }
                if let price = Expenses.lastPrice(of: item.uuid, in: DataSnapshot(entries: entries.map(\.info))) {
                    LabeledField(label: L10n.t("item.lastPrice")) {
                        Text(AssistantFormat.money(price.amount, price.currency, L10n.assistantLanguage)
                             + " · " + Fmt.date(price.date))
                            .foregroundStyle(.secondary)
                    }
                }
                if !item.isArchived {
                    Button {
                        router.open(.logService([item.uuid]))
                    } label: {
                        Label(L10n.t("add.logService"), systemImage: "checkmark.circle").frame(minHeight: 44)
                    }
                }
            } header: {
                Text(L10n.t("item.lastSection"))
            } footer: {
                Text(item.isArchived ? L10n.t("item.archivedFooter") : L10n.t("item.lastFooter"))
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let i = item else {
            name = draft.name
            intervalKm = draft.intervalKm
            intervalMonths = draft.intervalMonths
            kind = draft.kind
            return
        }
        name = i.name
        aliases = i.aliases.joined(separator: ", ")
        intervalKm = i.intervalKm
        intervalMonths = i.intervalMonths
        kind = i.kind
        seasonMonths = Set(i.seasonMonths)
        validUntil = i.validUntil
        oem = i.oemNumber ?? ""
        analogs = i.analogNumbers.joined(separator: ", ")
        showMore = !oem.isEmpty || !analogs.isEmpty || !aliases.isEmpty
    }

    private var finalOEM: String {
        keepOldOEM ? (item?.oemNumber ?? "") : oem.trimmed
    }

    // Step 1: validation, then an archived item with the same name.
    private func startSave() {
        triedSave = true
        keepOldOEM = false
        guard isValid else { return }
        let renamed = !isCatalog && (item.map { ItemNameRules.key($0.name) != ItemNameRules.key(name) } ?? true)
        if renamed, case .archived(let other) = nameConflict {
            askArchivedDuplicate = other
        } else {
            afterArchivedCheck()
        }
    }

    // Step 2: renaming a custom item that has history.
    private func afterArchivedCheck() {
        if !isCatalog, let i = item, ItemNameRules.key(i.name) != ItemNameRules.key(name), ItemActions.hasHistory(i) {
            askRename = true
        } else {
            afterRenameCheck(typo: false)
        }
    }

    private func afterRenameCheck(typo: Bool) {
        if typo, let i = item { ItemActions.renameEverywhere(i, to: name.trimmed) }
        // Step 3: OEM replacement question.
        if case .different = PartNumbers.oemChange(existing: item?.oemNumber, new: oem) {
            askReplaceOEM = true
        } else {
            checkNumberConflicts()
        }
    }

    // Step 4: part numbers already used by other items.
    private func checkNumberConflicts() {
        let numbers = [finalOEM] + PartNumbers.cleanList(analogs.listItems)
        let conflicts = PartNumbers.conflicts(numbers: numbers, editingItemID: item?.uuid,
                                              items: allItems.map(\.info))
        if conflicts.isEmpty {
            commit()
        } else {
            conflictText = conflicts.map { L10n.f("item.duplicateLine", $0.number, $0.itemName) }.joined(separator: "\n")
            askConflict = true
        }
    }

    private func commit() {
        let target: Item
        if let i = item {
            target = i
        } else {
            target = Item(name: name.trimmed)
            context.insert(target)
        }
        if !isCatalog { target.name = name.trimmed }
        target.aliases = aliases.listItems.map { String($0.prefix(Limits.alias)) }
        target.intervalKm = intervalKm
        target.intervalMonths = intervalMonths
        target.kind = kind
        target.seasonMonths = seasonMonths.sorted()
        target.validUntil = kind == .expiry ? validUntil : target.validUntil
        target.oemNumber = finalOEM.isEmpty ? nil : finalOEM
        target.analogNumbers = PartNumbers.cleanList(analogs.listItems).map { String($0.prefix(Limits.partNumber)) }
        if needsLast, let d = lastDate, let km = lastKm {
            context.insert(ServiceEntry(date: d, odometerKm: km, items: [target]))
        }
        DataEvents.changed(context)
        dismiss()
    }

    private func restoreArchived() {
        guard let info = askArchivedDuplicate,
              let archived = allItems.first(where: { $0.uuid == info.id }) else { return }
        archived.isArchived = false
        DataEvents.changed(context)
        dismiss()
    }

    /// "This is a different part": archive the old item with its history, start a new one with the new name.
    private func differentPart() {
        guard let i = item else { return }
        i.isArchived = true
        DataEvents.changed(context)
        router.open(.newItem(Router.ItemDraft(name: name.trimmed, intervalKm: intervalKm, intervalMonths: intervalMonths,
                                              kind: kind)))
    }
}
