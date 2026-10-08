import SwiftUI
import SwiftData
import CarCareCore

/// Settings → "Import history from notes": paste text, check the preview (✓ sure, ⚠ needs a look, tap to fix
/// date or odometer), import everything selected in one go. Missing items are created (catalog or custom).
struct ImportHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.createdAt) private var items: [Item]

    @State private var text = ""
    @State private var rows: [ImportedRow] = []
    @State private var included = Set<UUID>()
    @State private var editing: ImportedRow?
    @State private var imported: Int?

    var body: some View {
        Form {
            if rows.isEmpty {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .font(.callout.monospaced())
                        .accessibilityIdentifier("import.text")
                } header: {
                    Text(L10n.t("import.pasteHeader"))
                } footer: {
                    Text(L10n.t("import.example"))
                }
                Section {
                    Button {
                        if let pasted = UIPasteboard.general.string { text = pasted }
                    } label: {
                        Label(L10n.t("import.paste"), systemImage: "doc.on.clipboard").frame(minHeight: 44)
                    }
                    Button {
                        parse()
                    } label: {
                        Label(L10n.t("import.parse"), systemImage: "wand.and.stars").frame(minHeight: 44)
                    }
                    .disabled(text.trimmed.isEmpty)
                    .accessibilityIdentifier("import.parse")
                }
            } else {
                Section {
                    ForEach(rows) { row in
                        Button {
                            if row.isUsable { toggle(row.id) } else { editing = row }
                        } label: {
                            ImportRowView(row: row, included: included.contains(row.id), names: names(row))
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button(L10n.t("import.fix")) { editing = row }.tint(.orange)
                        }
                    }
                } header: {
                    Text(L10n.f("import.previewHeader", rows.filter(\.isUsable).count, rows.count))
                } footer: {
                    Text(L10n.t("import.previewFooter"))
                }
                Section {
                    Button {
                        importSelected()
                    } label: {
                        Text(L10n.f("import.button", included.count)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(included.isEmpty)
                    .listRowBackground(Color.clear)
                    Button(L10n.t("import.again")) { rows = []; included = [] }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(L10n.t("import.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { row in
            ImportRowEditor(row: row) { fixed in
                if let i = rows.firstIndex(where: { $0.id == fixed.id }) { rows[i] = fixed }
                if fixed.isUsable { included.insert(fixed.id) }
            }
        }
        .alert(L10n.f("import.done", imported ?? 0), isPresented: Binding(get: { imported != nil },
                                                                         set: { if !$0 { imported = nil; dismiss() } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func parse() {
        rows = HistoryImporter.parse(text, items: items.map(\.info), today: Date(), calendar: Fmt.calendar)
        included = Set(rows.filter(\.isUsable).map(\.id))
    }

    private func toggle(_ id: UUID) {
        if included.contains(id) { included.remove(id) } else { included.insert(id) }
    }

    private func names(_ row: ImportedRow) -> [String] {
        row.items.map { item in
            switch item {
            case .existing(let id): return items.first { $0.uuid == id }?.displayName ?? "?"
            case .catalog(let key): return (Catalog.name(key, L10n.assistantLanguage) ?? key) + " ✦"
            case .custom(let name): return name + " ✦"
            }
        }
    }

    private func importSelected() {
        var created: [String: Item] = [:]
        var count = 0
        for row in rows where included.contains(row.id) {
            guard let date = row.date, let km = row.odometerKm else { continue }
            var list: [Item] = []
            for (index, item) in row.items.enumerated() {
                switch item {
                case .existing(let id):
                    if let i = items.first(where: { $0.uuid == id }) { list.append(i) }
                case .catalog(let key):
                    let i = created["c:" + key] ?? ItemActions.makeItem(.catalog(key), order: index, context: context)
                    created["c:" + key] = i
                    list.append(i)
                case .custom(let name):
                    let k = "n:" + ItemNameRules.key(name)
                    let i = created[k] ?? ItemActions.makeItem(.custom(name), order: index, context: context)
                    created[k] = i
                    list.append(i)
                }
            }
            guard !list.isEmpty else { continue }
            let entry = ServiceEntry(date: date, odometerKm: km, items: list)
            entry.currency = AppSettings.shared.currency
            context.insert(entry)
            count += 1
        }
        DataEvents.changed(context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        imported = count
    }
}

private struct ImportRowView: View {
    let row: ImportedRow
    let included: Bool
    let names: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: !row.isUsable ? "exclamationmark.triangle.fill"
                  : (included ? "checkmark.circle.fill" : "circle"))
                .foregroundStyle(!row.isUsable || row.needsReview ? Color.orange : Color.accentColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(row.date.map(Fmt.date) ?? L10n.t("import.noDate"))
                        .fontWeight(.semibold).foregroundStyle(row.date == nil ? Color.orange : Color.primary)
                    Text(row.odometerKm.map(Fmt.km) ?? L10n.t("import.noKm"))
                        .foregroundStyle(row.odometerKm == nil ? Color.orange : Color.secondary).monospacedDigit()
                }
                .font(.subheadline)
                Text(names.isEmpty ? L10n.t("import.noItems") : names.joined(separator: ", "))
                    .font(.subheadline).lineLimit(3)
                Text(row.line).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// Fix the date or odometer of one imported line.
private struct ImportRowEditor: View {
    let row: ImportedRow
    let onSave: (ImportedRow) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date?
    @State private var km: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(row.line).font(.callout.monospaced())
                }
                Section {
                    RequiredDateField(title: L10n.t("entry.date"), date: $date)
                    LabeledField(label: L10n.t("entry.odometer")) {
                        NumberField(title: L10n.t("entry.km"), value: $km).frame(maxWidth: 140)
                    }
                }
            }
            .navigationTitle(L10n.t("import.fix"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.save")) {
                        var fixed = row
                        fixed.date = date
                        fixed.odometerKm = km
                        fixed.needsReview = false
                        onSave(fixed)
                        dismiss()
                    }
                    .disabled(date == nil || km == nil)
                }
            }
            .onAppear {
                date = row.date
                km = row.odometerKm
            }
        }
        .presentationDetents([.medium, .large])
    }
}
