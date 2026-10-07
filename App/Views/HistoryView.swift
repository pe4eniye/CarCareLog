import SwiftUI
import SwiftData
import CarCareCore

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ServiceEntry.date, order: .reverse),
                  SortDescriptor(\ServiceEntry.odometerKm, order: .reverse)])
    private var entries: [ServiceEntry]

    @State private var editor: EntryEditorTarget?

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Banner(icon: "plus.circle", text: L10n.t("history.empty"))
                }
                ForEach(entries) { entry in
                    Button {
                        editor = .edit(entry)
                    } label: {
                        EntryRow(entry: entry)
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(entries[i]) }
                    DataEvents.changed(context)
                }
            }
            .navigationTitle(L10n.t("tab.history"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .new
                    } label: {
                        Label(L10n.t("history.add"), systemImage: "plus").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    }
                }
            }
            .sheet(item: $editor) { target in
                EntryEditorView(target: target)
            }
        }
    }
}

enum EntryEditorTarget: Identifiable {
    case new
    case edit(ServiceEntry)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let e): return e.uuid.uuidString
        }
    }
}

struct EntryRow: View {
    let entry: ServiceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Fmt.date(entry.date)).font(.body.weight(.semibold))
                Spacer()
                Text(Fmt.km(entry.odometerKm)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(entry.sortedItems.map(\.name).joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct EntryEditorView: View {
    let target: EntryEditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var allItems: [Item]
    @Query private var readings: [OdometerReading]

    @State private var date = Date()
    @State private var odometer: Int?
    @State private var selected: [Item] = []
    @State private var showPicker = false
    @State private var loaded = false
    @State private var confirmDelete = false

    private var existing: ServiceEntry? {
        if case .edit(let e) = target { return e }
        return nil
    }

    private var problems: [ValidationRules.EntryProblem] {
        ValidationRules.validateEntry(date: date, odometerKm: odometer ?? -1, itemCount: selected.count,
                                      now: Date(), calendar: Fmt.calendar)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(L10n.t("entry.date"), selection: $date, in: ...Date(), displayedComponents: .date)
                        .frame(minHeight: 44)
                    LabeledField(label: L10n.t("entry.odometer")) {
                        NumberField(title: L10n.t("entry.km"), value: $odometer)
                    }
                }

                Section {
                    ForEach(selected) { item in
                        Text(item.name).frame(minHeight: 36)
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
                    if selected.isEmpty { Text(L10n.t("entry.needParts")) }
                }

                if existing != nil {
                    Section {
                        Button(L10n.t("entry.delete"), role: .destructive) { confirmDelete = true }
                            .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle(existing == nil ? L10n.t("entry.newTitle") : L10n.t("entry.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.save")) { save() }.disabled(!problems.isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                ItemPickerView(selected: $selected)
            }
            .confirmationDialog(L10n.t("entry.deleteConfirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L10n.t("common.delete"), role: .destructive) {
                    if let e = existing { context.delete(e) }
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
        if let e = existing {
            date = e.date
            odometer = e.odometerKm
            selected = e.sortedItems
        } else {
            odometer = OdometerRules.current(readings: readings.map(\.info))?.km
        }
    }

    private func save() {
        guard problems.isEmpty, let km = odometer else { return }
        let addReading = OdometerRules.serviceEntryShouldAddReading(entryKm: km, readings: readings.map(\.info))
        if let e = existing {
            e.date = date
            e.odometerKm = km
            e.items = selected
        } else {
            context.insert(ServiceEntry(date: date, odometerKm: km, items: selected))
        }
        if addReading {
            context.insert(OdometerReading(date: date, km: km))
        }
        DataEvents.changed(context)
        dismiss()
    }
}

/// Multi-select list of parts with search and inline creation of a new part.
struct ItemPickerView: View {
    @Binding var selected: [Item]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var items: [Item]
    @State private var search = ""

    private var filtered: [Item] {
        let q = search.trimmed
        guard !q.isEmpty else { return items }
        return items.filter { item in
            ([item.name] + item.aliases).contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    private var canCreate: Bool {
        let q = search.trimmed
        return !q.isEmpty && !items.contains { $0.name.compare(q, options: .caseInsensitive) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if canCreate {
                    Button {
                        let item = Item(name: search.trimmed)
                        context.insert(item)
                        DataEvents.changed(context)
                        selected.append(item)
                        search = ""
                    } label: {
                        Label(L10n.f("picker.create", search.trimmed), systemImage: "plus.circle.fill")
                            .frame(minHeight: 44)
                    }
                }
                ForEach(filtered) { item in
                    Button {
                        toggle(item)
                    } label: {
                        HStack {
                            Text(item.name).foregroundStyle(.primary)
                            Spacer()
                            if selected.contains(where: { $0.uuid == item.uuid }) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                }
                if items.isEmpty && search.isEmpty {
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
