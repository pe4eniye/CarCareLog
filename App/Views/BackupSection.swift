import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CarCareCore

/// Settings section: export all data to one JSON file via the share sheet, and import it back.
struct BackupSection: View {
    @Environment(\.modelContext) private var context

    @State private var shareURL: URL?
    @State private var showImporter = false
    @State private var pendingImport: BackupFile?
    @State private var message: String?

    var body: some View {
        Section {
            Button {
                export()
            } label: {
                Label(L10n.t("backup.export"), systemImage: "square.and.arrow.up").frame(minHeight: 44)
            }
            Button {
                showImporter = true
            } label: {
                Label(L10n.t("backup.import"), systemImage: "square.and.arrow.down").frame(minHeight: 44)
            }
        } header: {
            Text(L10n.t("backup.section"))
        } footer: {
            Text(L10n.t("backup.footer"))
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .data]) { result in
            handlePicked(result)
        }
        .alert(L10n.t("backup.confirmTitle"),
               isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button(L10n.t("backup.replace"), role: .destructive) { restore() }
            Button(L10n.t("common.cancel"), role: .cancel) { pendingImport = nil }
        } message: {
            if let file = pendingImport {
                Text(L10n.f("backup.confirmText", Fmt.date(file.exportedAt), file.items.count, file.entries.count))
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func export() {
        do {
            let snapshot = SnapshotBuilder.fetch(context)
            let data = try BackupCodec.encode(snapshot, exportedAt: Date())
            let name = BackupCodec.suggestedFileName(date: Date(), calendar: Fmt.calendar)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            message = L10n.t("backup.exportFailed")
        }
    }

    private func handlePicked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pendingImport = try BackupCodec.decode(data)
        } catch BackupError.newerFormat {
            message = L10n.t("backup.newerFormat")
        } catch {
            message = L10n.t("backup.invalid")
        }
    }

    private func restore() {
        guard let file = pendingImport else { return }
        pendingImport = nil
        do {
            try SnapshotBuilder.restore(file.snapshot, into: context)
            DataEvents.changed(context)
            message = L10n.t("backup.restored")
        } catch {
            message = L10n.t("backup.restoreFailed")
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
