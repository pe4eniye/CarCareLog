import SwiftUI
import SwiftData
import CarCareCore

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: Router
    @Query(sort: [SortDescriptor(\ServiceEntry.date, order: .reverse),
                  SortDescriptor(\ServiceEntry.odometerKm, order: .reverse)])
    private var entries: [ServiceEntry]

    @State private var pendingDelete: ServiceEntry?

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Banner(icon: "plus.circle", text: L10n.t("history.empty"))
                }
                ForEach(entries) { entry in
                    Button {
                        router.open(.editEntry(entry))
                    } label: {
                        EntryRow(entry: entry)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button(L10n.t("common.delete"), role: .destructive) { pendingDelete = entry }
                    }
                }
            }
            .navigationTitle(L10n.t("tab.history"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) { AddMenuButton() }
            }
            .confirmationDialog(L10n.t("entry.deleteConfirm"),
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button(L10n.t("common.delete"), role: .destructive) {
                    if let e = pendingDelete { context.delete(e) }
                    pendingDelete = nil
                    DataEvents.changed(context)
                }
            }
        }
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

/// "Log service": date and odometer are required and start empty, so nothing is recorded "by default".
struct EntryEditorView: View {
    let entry: ServiceEntry?
    let preselected: [UUID]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var allItems: [Item]
    @Query private var readings: [OdometerReading]
    @Query private var entries: [ServiceEntry]

    @State private var date: Date?
    @State private var odometer: Int?
    @State private var selected: [Item] = []
    @State private var showPicker = false
    @State private var loaded = false
    @State private var triedSave = false
    @State private var confirmLower = false
    @State private var confirmDelete = false

    private var dateError: FieldError? { ValidationRules.pastOrToday(date, now: Date(), calendar: Fmt.calendar) }
    private var kmError: FieldError? { ValidationRules.number(odometer, required: true, range: Limits.odometer) }
    private var isValid: Bool { dateError == nil && kmError == nil && !selected.isEmpty }

    /// Current odometer without this entry (so editing it doesn't compare with itself).
    private var currentOther: OdometerReadingInfo? {
        OdometerRules.current(readings: readings.map(\.info),
                              entries: entries.filter { $0.uuid != entry?.uuid }.map(\.info), calendar: Fmt.calendar)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RequiredDateField(title: L10n.t("entry.date"), date: $date)
                    FieldErrorText(error: dateError, show: triedSave)
                    LabeledField(label: L10n.t("entry.odometer")) {
                        NumberField(title: L10n.t("entry.km"), value: $odometer).frame(maxWidth: 140)
                    }
                    FieldErrorText(error: kmError, show: triedSave)
                } footer: {
                    if let cur = currentOther {
                        Text(L10n.f("odometer.current", Fmt.km(cur.km), Fmt.date(cur.date)))
                    }
                }

                Section {
                    ForEach(selected) { item in
                        Text(item.name).lineLimit(2).frame(minHeight: 36)
                    }
                    .onDelete { selected.remove(atOffsets: $0) }
                    Button {
                        showPicker = true
                    } label: {
                        Label(L10n.t("entry.pickParts"), systemImage: "plus.circle").frame(minHeight: 44)
                    }
                } header: {
                    Text(L10n.t("entry.parts"))
                } footer: {
                    if selected.isEmpty && triedSave {
                        Text(L10n.t("entry.needParts")).foregroundStyle(.red)
                    }
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
                    Button(L10n.t("common.save")) { trySave() }
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
        if let e = entry {
            date = e.date
            odometer = e.odometerKm
            selected = e.sortedItems
        } else {
            selected = preselected.compactMap { id in allItems.first { $0.uuid == id } }
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
        if let e = entry {
            e.date = d
            e.odometerKm = km
            e.setItems(selected)
        } else {
            context.insert(ServiceEntry(date: d, odometerKm: km, items: selected))
        }
        DataEvents.changed(context)
        dismiss()
    }
}

/// Multi-select list of active items with search.
struct ItemPickerView: View {
    @Binding var selected: [Item]

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Item> { !$0.isArchived }, sort: \Item.createdAt) private var items: [Item]
    @State private var search = ""

    private var filtered: [Item] {
        let q = search.trimmed
        guard !q.isEmpty else { return items }
        return items.filter { item in
            ([item.name] + item.aliases).contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { item in
                    Button {
                        toggle(item)
                    } label: {
                        HStack {
                            Text(item.name).foregroundStyle(.primary).lineLimit(2)
                            Spacer()
                            if selected.contains(where: { $0.uuid == item.uuid }) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                }
                if items.isEmpty {
                    Text(L10n.t("picker.empty")).foregroundStyle(.secondary)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: L10n.t("picker.search"))
            .navigationTitle(L10n.t("entry.parts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
    }

    private func toggle(_ item: Item) {
        if let i = selected.firstIndex(where: { $0.uuid == item.uuid }) {
            selected.remove(at: i)
        } else {
            selected.append(item)
        }
    }
}
