import SwiftUI
import SwiftData
import CarCareCore

struct PartsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var items: [Item]

    @State private var editor: ItemEditorTarget?
    @State private var search = ""
    @State private var pendingDelete: Item?

    private var filtered: [Item] {
        let q = search.trimmed
        guard !q.isEmpty else { return items }
        return items.filter { item in
            ([item.name] + item.aliases + [item.oemNumber ?? ""] + item.analogNumbers)
                .contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Banner(icon: "wrench.and.screwdriver", text: L10n.t("parts.empty"))
                }
                ForEach(filtered) { item in
                    Button {
                        editor = .edit(item)
                    } label: {
                        ItemRow(item: item)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button(L10n.t("common.delete"), role: .destructive) { pendingDelete = item }
                    }
                }
            }
            .searchable(text: $search, prompt: L10n.t("parts.search"))
            .navigationTitle(L10n.t("tab.parts"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .new
                    } label: {
                        Label(L10n.t("parts.add"), systemImage: "plus").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    }
                }
            }
            .sheet(item: $editor) { target in
                ItemEditorView(target: target)
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
        }
    }

    private var deleteTitle: String {
        guard let item = pendingDelete else { return "" }
        let count = item.entries?.count ?? 0
        return count > 0 ? L10n.f("parts.deleteUsed", item.name, count) : L10n.f("parts.deleteConfirm", item.name)
    }
}

struct ItemRow: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name).font(.body.weight(.medium))
            let summary = intervalSummary
            if !summary.isEmpty {
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
            }
            if let oem = item.oemNumber, !oem.isEmpty {
                Text("OEM: \(oem)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var intervalSummary: String {
        var parts: [String] = []
        if let km = item.intervalKm, km > 0 { parts.append(L10n.f("parts.everyKm", Fmt.km(km))) }
        if let m = item.intervalMonths, m > 0 { parts.append(L10n.f("parts.everyMonths", m)) }
        return parts.joined(separator: " · ")
    }
}

enum ItemEditorTarget: Identifiable {
    case new
    case edit(Item)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let i): return i.uuid.uuidString
        }
    }
}

struct ItemEditorView: View {
    let target: ItemEditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var allItems: [Item]

    @State private var name = ""
    @State private var aliases = ""
    @State private var intervalKm: Int?
    @State private var intervalMonths: Int?
    @State private var oem = ""
    @State private var analogs = ""
    @State private var loaded = false

    // Save flow: OEM replace question first, then duplicate-number warning.
    @State private var askReplaceOEM = false
    @State private var keepOldOEM = false
    @State private var conflictText = ""
    @State private var askConflict = false

    private var existing: Item? {
        if case .edit(let i) = target { return i }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.t("item.name"), text: $name).frame(minHeight: 44)
                    TextField(L10n.t("item.aliases"), text: $aliases, axis: .vertical).frame(minHeight: 44)
                } footer: {
                    Text(L10n.t("item.aliasesFooter"))
                }

                Section(L10n.t("item.interval")) {
                    LabeledField(label: L10n.t("item.intervalKm")) {
                        NumberField(title: L10n.t("item.optional"), value: $intervalKm)
                    }
                    LabeledField(label: L10n.t("item.intervalMonths")) {
                        NumberField(title: L10n.t("item.optional"), value: $intervalMonths)
                    }
                }

                Section {
                    TextField(L10n.t("item.oem"), text: $oem)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(minHeight: 44)
                    TextField(L10n.t("item.analogs"), text: $analogs, axis: .vertical)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(minHeight: 44)
                } header: {
                    Text(L10n.t("item.numbers"))
                } footer: {
                    Text(L10n.t("item.analogsFooter"))
                }
            }
            .navigationTitle(existing == nil ? L10n.t("item.newTitle") : L10n.t("item.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.save")) { startSave() }.disabled(name.trimmed.isEmpty)
                }
            }
            .confirmationDialog(L10n.t("item.replaceOEMTitle"), isPresented: $askReplaceOEM, titleVisibility: .visible) {
                Button(L10n.t("item.replace")) { keepOldOEM = false; checkConflicts() }
                Button(L10n.t("item.keep")) { keepOldOEM = true; checkConflicts() }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.f("item.replaceOEMText", existing?.oemNumber ?? "", oem.trimmed))
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

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let i = existing else { return }
        name = i.name
        aliases = i.aliases.joined(separator: ", ")
        intervalKm = i.intervalKm
        intervalMonths = i.intervalMonths
        oem = i.oemNumber ?? ""
        analogs = i.analogNumbers.joined(separator: ", ")
    }

    private var finalOEM: String {
        keepOldOEM ? (existing?.oemNumber ?? "") : oem.trimmed
    }

    private func startSave() {
        keepOldOEM = false
        if case .different = PartNumbers.oemChange(existing: existing?.oemNumber, new: oem) {
            askReplaceOEM = true
        } else {
            checkConflicts()
        }
    }

    private func checkConflicts() {
        let numbers = [finalOEM] + PartNumbers.cleanList(analogs.listItems)
        let conflicts = PartNumbers.conflicts(numbers: numbers, editingItemID: existing?.uuid,
                                              items: allItems.map(\.info))
        if conflicts.isEmpty {
            commit()
        } else {
            conflictText = conflicts
                .map { L10n.f("item.duplicateLine", $0.number, $0.itemName) }
                .joined(separator: "\n")
            askConflict = true
        }
    }

    private func commit() {
        let item: Item
        if let e = existing {
            item = e
        } else {
            item = Item(name: name.trimmed)
            context.insert(item)
        }
        item.name = name.trimmed
        item.aliases = aliases.listItems
        item.intervalKm = (intervalKm ?? 0) > 0 ? intervalKm : nil
        item.intervalMonths = (intervalMonths ?? 0) > 0 ? intervalMonths : nil
        item.oemNumber = finalOEM.isEmpty ? nil : finalOEM
        item.analogNumbers = PartNumbers.cleanList(analogs.listItems)
        DataEvents.changed(context)
        dismiss()
    }
}
