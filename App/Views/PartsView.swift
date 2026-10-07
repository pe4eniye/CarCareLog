import SwiftUI
import SwiftData
import CarCareCore

/// "Schedule" tab: what the user maintains and how often. Archived items are collapsed at the bottom.
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

    private func matches(_ item: Item) -> Bool {
        let q = search.trimmed
        guard !q.isEmpty else { return true }
        return ([item.name] + item.aliases + [item.oemNumber ?? ""] + item.analogNumbers)
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            let snapshot = SnapshotBuilder.make(cars: cars, items: items, entries: entries, readings: readings)
            let statuses = ForecastEngine.statuses(for: snapshot, today: Date(), calendar: Fmt.calendar)
            let active = items.filter { !$0.isArchived && matches($0) }
            let archived = items.filter { $0.isArchived && matches($0) }

            List {
                if items.isEmpty {
                    Banner(icon: "list.bullet.clipboard", text: L10n.t("parts.empty"),
                           actionTitle: L10n.t("add.item")) { router.open(.newItem(Router.ItemDraft())) }
                }
                ForEach(active) { item in
                    Button {
                        router.open(.item(item))
                    } label: {
                        ItemRow(item: item, snapshot: snapshot, status: statuses[item.uuid])
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        if ItemActions.hasHistory(item) {
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

                if !archived.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showArchive) {
                            ForEach(archived) { item in
                                Button {
                                    router.open(.item(item))
                                } label: {
                                    ItemRow(item: item, snapshot: snapshot, status: nil)
                                }
                                .foregroundStyle(.secondary)
                                .swipeActions {
                                    Button(L10n.t("common.delete"), role: .destructive) { pendingDelete = item }
                                    Button(L10n.t("parts.restore")) { restore(item) }.tint(.green)
                                }
                            }
                        } label: {
                            Text(L10n.f("parts.archiveTitle", archived.count)).font(.headline)
                        }
                    } footer: {
                        Text(L10n.t("parts.archiveFooter"))
                    }
                }
            }
            .searchable(text: $search, prompt: L10n.t("parts.search"))
            .navigationTitle(L10n.t("tab.parts"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) { AddMenuButton() }
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

    private var deleteTitle: String {
        guard let item = pendingDelete else { return "" }
        return ItemActions.hasHistory(item) ? L10n.f("parts.deleteKeepsHistory", item.name)
                                            : L10n.f("parts.deleteConfirm", item.name)
    }

    private func restore(_ item: Item) {
        if case .active(let other) = ItemNameRules.conflict(for: item.name, editingItemID: item.uuid,
                                                             items: items.map(\.info)) {
            restoreBlocked = L10n.f("parts.restoreBlocked", other.name)
            return
        }
        item.isArchived = false
        DataEvents.changed(context)
    }
}

/// Schedule row: name, interval, last replacement, next one.
struct ItemRow: View {
    let item: Item
    let snapshot: DataSnapshot
    let status: ItemStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
            let interval = Self.intervalText(km: item.intervalKm, months: item.intervalMonths)
            if !interval.isEmpty {
                Label(interval, systemImage: "arrow.triangle.2.circlepath").font(.subheadline)
            }
            if let last = ForecastEngine.lastEntry(for: item.uuid, entries: snapshot.entries) {
                Label(L10n.f("parts.lastLine", Fmt.km(last.odometerKm), Fmt.date(last.date)),
                      systemImage: "checkmark.circle")
                    .font(.subheadline)
            }
            if let f = status?.forecast {
                Label(nextText(f), systemImage: f.isOverdue ? "exclamationmark.triangle" : "calendar")
                    .font(.subheadline)
                    .foregroundStyle(f.isOverdue ? Color.red : Color.secondary)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func nextText(_ f: ItemForecast) -> String {
        if f.isOverdue { return L10n.t("home.overdue") }
        if let d = f.dueDate { return L10n.f("parts.nextLine", Fmt.km(f.predictedOdometerKm), Fmt.date(d)) }
        return L10n.f("parts.nextKmOnly", Fmt.km(f.dueKm ?? f.predictedOdometerKm))
    }

    static func intervalText(km: Int?, months: Int?) -> String {
        var parts: [String] = []
        if let km, km > 0 { parts.append(L10n.f("parts.everyKm", Fmt.km(km))) }
        if let m = months, m > 0 { parts.append(L10n.f("parts.everyMonths", m)) }
        return parts.joined(separator: " · ")
    }
}

/// New item or item card. A new item needs its last replacement (it becomes a History entry).
/// An existing item shows its last replacement read-only, with "Log service".
struct ItemEditorView: View {
    let item: Item?
    let draft: Router.ItemDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: Router
    @Query(sort: \Item.createdAt) private var allItems: [Item]
    @Query private var entries: [ServiceEntry]
    @Query private var readings: [OdometerReading]
    @Query private var cars: [Car]

    @State private var name = ""
    @State private var aliases = ""
    @State private var intervalKm: Int?
    @State private var intervalMonths: Int?
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

    private var currentOdometer: OdometerReadingInfo? {
        OdometerRules.current(readings: readings.map(\.info), entries: entries.map(\.info), calendar: Fmt.calendar)
    }

    private var nameConflict: ItemNameRules.Conflict {
        ItemNameRules.conflict(for: name, editingItemID: item?.uuid, items: allItems.map(\.info))
    }

    private var nameError: FieldError? {
        if let e = ValidationRules.text(name, required: true, max: Limits.itemName) { return e }
        if case .active(let other) = nameConflict { return .duplicate(name: other.name) }
        return nil
    }
    private var kmError: FieldError? { ValidationRules.number(intervalKm, required: false, range: Limits.intervalKm) }
    private var monthsError: FieldError? {
        ValidationRules.number(intervalMonths, required: false, range: Limits.intervalMonths)
    }
    private var lastDateError: FieldError? {
        isNew ? ValidationRules.pastOrToday(lastDate, now: Date(), calendar: Fmt.calendar) : nil
    }
    private var lastKmError: FieldError? {
        isNew ? ValidationRules.number(lastKm, required: true, range: Limits.odometer) : nil
    }
    private var isValid: Bool {
        [nameError, kmError, monthsError, lastDateError, lastKmError].allSatisfy { $0 == nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.t("item.name"), text: $name)
                        .limitLength($name, Limits.itemName)
                        .frame(minHeight: 44)
                    FieldErrorText(error: nameError, show: triedSave || nameError != .required)
                }

                Section {
                    LabeledField(label: L10n.t("item.intervalKm")) {
                        NumberField(title: L10n.t("item.optional"), value: $intervalKm).frame(maxWidth: 120)
                    }
                    FieldErrorText(error: kmError)
                    LabeledField(label: L10n.t("item.intervalMonths")) {
                        NumberField(title: L10n.t("item.optional"), value: $intervalMonths).frame(maxWidth: 120)
                    }
                    FieldErrorText(error: monthsError)
                } header: {
                    Text(L10n.t("item.interval"))
                } footer: {
                    Text(L10n.t("item.intervalFooter"))
                }

                lastReplacementSection

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
                    Button(L10n.t("common.save")) { startSave() }
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

    @ViewBuilder
    private var lastReplacementSection: some View {
        if isNew {
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
            return
        }
        name = i.name
        aliases = i.aliases.joined(separator: ", ")
        intervalKm = i.intervalKm
        intervalMonths = i.intervalMonths
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
        let renamed = item.map { ItemNameRules.key($0.name) != ItemNameRules.key(name) } ?? true
        if renamed, case .archived(let other) = nameConflict {
            askArchivedDuplicate = other
        } else {
            afterArchivedCheck()
        }
    }

    // Step 2: renaming an item that has history.
    private func afterArchivedCheck() {
        if let i = item, ItemNameRules.key(i.name) != ItemNameRules.key(name), ItemActions.hasHistory(i) {
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
        target.name = name.trimmed
        target.aliases = aliases.listItems.map { String($0.prefix(Limits.alias)) }
        target.intervalKm = intervalKm
        target.intervalMonths = intervalMonths
        target.oemNumber = finalOEM.isEmpty ? nil : finalOEM
        target.analogNumbers = PartNumbers.cleanList(analogs.listItems).map { String($0.prefix(Limits.partNumber)) }
        if isNew, let d = lastDate, let km = lastKm {
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
        router.open(.newItem(Router.ItemDraft(name: name.trimmed, intervalKm: intervalKm, intervalMonths: intervalMonths)))
    }
}
