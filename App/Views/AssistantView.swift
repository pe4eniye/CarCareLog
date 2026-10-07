import SwiftUI
import SwiftData
import CarCareCore

/// Offline, rule-based assistant. Works with keyboard dictation (the microphone key on the iOS keyboard).
struct AssistantView: View {
    @Environment(\.modelContext) private var context

    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        let reply: AssistantReply
    }

    @State private var question = ""
    @State private var history: [Exchange] = []
    @FocusState private var focused: Bool

    private var exampleChips: [String] {
        Assistant.examples(L10n.assistantLanguage)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if history.isEmpty {
                            Text(L10n.t("assistant.intro")).font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(history) { ex in
                            ExchangeView(exchange: ex) { choice in
                                ask(ex.question, chosen: choice)
                            } onExample: { example in
                                ask(example)
                            }
                            .id(ex.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: history.count) { _, _ in
                    if let last = history.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle(L10n.t("tab.assistant"))
            .onAppear {
                if history.isEmpty, let q = DemoMode.question { ask(q) }
            }
            .toolbar {
                if !history.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L10n.t("assistant.clear")) { history.removeAll() }
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(exampleChips, id: \.self) { chip in
                        Button(chip) { ask(chip) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal)
            }
            HStack(spacing: 8) {
                TextField(L10n.t("assistant.placeholder"), text: $question, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { ask(question) }
                Button {
                    ask(question)
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                }
                .disabled(question.trimmed.isEmpty)
                .accessibilityLabel(L10n.t("assistant.send"))
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func ask(_ text: String, chosen: UUID? = nil) {
        let q = text.trimmed
        guard !q.isEmpty else { return }
        let ctx = AssistantContext(snapshot: SnapshotBuilder.fetch(context), today: Date(), calendar: Fmt.calendar,
                                   fallbackLanguage: L10n.assistantLanguage)
        let reply = Assistant.answer(q, context: ctx, chosenItemID: chosen)
        history.append(Exchange(question: q, reply: reply))
        if chosen == nil { question = "" }
    }
}

private struct ExchangeView: View {
    let exchange: AssistantView.Exchange
    let onChoice: (UUID) -> Void
    let onExample: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 40)
                Text(exchange.question)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.15)))
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(exchange.reply.lines.enumerated()), id: \.offset) { _, line in
                    ReplyLineView(line: line)
                }
                ForEach(exchange.reply.choices) { choice in
                    Button(choice.name) { onChoice(choice.id) }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                }
                ForEach(exchange.reply.examples, id: \.self) { example in
                    Button(example) { onExample(example) }
                        .font(.callout)
                        .frame(minHeight: 36)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
    }
}

private struct ReplyLineView: View {
    let line: ReplyLine
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line.text).textSelection(.enabled)
            if !line.copyValues.isEmpty {
                HStack {
                    ForEach(line.copyValues, id: \.self) { value in
                        Button {
                            UIPasteboard.general.string = value
                            copied = value
                        } label: {
                            Label(copied == value ? L10n.t("assistant.copied") : value,
                                  systemImage: copied == value ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}
