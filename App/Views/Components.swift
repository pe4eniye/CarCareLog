import SwiftUI
import CarCareCore

struct Banner: View {
    enum Style { case info, warning }
    let icon: String
    let text: String
    var style: Style = .info
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(style == .warning ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

struct ReasonChip: View {
    let reason: DueReason

    var body: some View {
        Text(reason == .mileage ? L10n.t("reason.mileage") : L10n.t("reason.time"))
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

/// One row on Home: item name, reason chip and predicted odometer.
struct ForecastRow: View {
    let name: String
    let forecast: ItemForecast
    /// For rows outside a date section ("Later"), show the due date in the row.
    var showDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.body.weight(.medium)).lineLimit(2)
            HStack(spacing: 8) {
                ReasonChip(reason: forecast.reason)
                Text(detail).font(.subheadline).foregroundStyle(forecast.isOverdue ? Color.red : Color.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        if forecast.isOverdue {
            var parts: [String] = []
            let limits = forecast.overdueLimits
            if let d = limits.date { parts.append(Fmt.date(d)) }
            if let km = limits.km { parts.append(Fmt.km(km)) }
            return L10n.f("home.overdueSince", parts.joined(separator: " · "))
        }
        if forecast.dueDate == nil, let km = forecast.dueKm {
            return L10n.f("home.atKm", Fmt.km(km))
        }
        let km = "≈ " + Fmt.km(forecast.predictedOdometerKm)
        if showDate, let d = forecast.dueDate { return Fmt.date(d) + " · " + km }
        return km
    }
}

/// Numeric text field bound to an optional Int.
struct NumberField: View {
    let title: String
    @Binding var value: Int?

    @State private var text = ""

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.numberPad)
            .onAppear { text = value.map(String.init) ?? "" }
            .onChange(of: text) { _, newValue in
                // At most 7 digits: no field needs more than 2 000 000.
                if newValue.filter(\.isNumber).count > 7 { text = String(newValue.filter(\.isNumber).prefix(7)) }
                let parsed = Fmt.parseInt(text)
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                // Value set from outside (e.g. "Don't know — count from today").
                if Fmt.parseInt(text) != newValue { text = newValue.map(String.init) ?? "" }
            }
    }
}

/// Labeled row used in forms: label on the left, field on the right.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            content.multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Splits "a, b; c\nd" into ["a", "b", "c", "d"].
    var listItems: [String] {
        components(separatedBy: CharacterSet(charactersIn: ",;\n")).map(\.trimmed).filter { !$0.isEmpty }
    }
}

// MARK: - Form validation helpers

extension FieldError {
    var message: String {
        switch self {
        case .required: return L10n.t("error.required")
        case .tooLong(let max): return L10n.f("error.tooLong", max)
        case .outOfRange(let min, let max):
            return L10n.f("error.range", AssistantFormat.groupDigits(min, separator: "\u{00A0}"),
                          AssistantFormat.groupDigits(max, separator: "\u{00A0}"))
        case .dateInFuture: return L10n.t("error.future")
        case .duplicate(let name): return L10n.f("error.duplicate", name)
        }
    }
}

/// Red hint under a field. Shown only after the user touched the form (`show`).
struct FieldErrorText: View {
    let error: FieldError?
    var show = true

    var body: some View {
        if show, let error {
            Text(error.message).font(.footnote).foregroundStyle(.red)
        }
    }
}

extension View {
    /// Cuts typed or pasted text to `max` characters.
    func limitLength(_ text: Binding<String>, _ max: Int) -> some View {
        onChange(of: text.wrappedValue) { _, newValue in
            if newValue.count > max { text.wrappedValue = String(newValue.prefix(max)) }
        }
    }
}

/// A date that must be chosen explicitly (no default), not in the future.
struct RequiredDateField: View {
    let title: String
    @Binding var date: Date?

    @State private var editing = false
    @State private var temp = Date()

    var body: some View {
        Button {
            temp = date ?? Date()
            withAnimation { editing.toggle() }
        } label: {
            LabeledField(label: title) {
                Text(date.map(Fmt.date) ?? L10n.t("field.chooseDate"))
                    .foregroundStyle(date == nil ? Color.accentColor : Color.secondary)
            }
        }
        .foregroundStyle(.primary)
        if editing {
            DatePicker("", selection: $temp, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            Button {
                date = temp
                withAnimation { editing = false }
            } label: {
                Text(L10n.t("field.useDate")).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Urgency colors (red overdue, yellow ≤ 2 months, green otherwise)

extension Urgency {
    var color: Color {
        switch self {
        case .overdue: return .red
        case .soon: return .orange
        case .ok: return .green
        }
    }

    /// Card background: a light wash of the color, readable in light and dark mode.
    var tint: Color { color.opacity(0.13) }
}

extension Urgency {
    /// Darker shade for text on the tinted card background.
    var textColor: Color {
        switch self {
        case .overdue: return Color(red: 0.71, green: 0.14, blue: 0.10)
        case .soon: return Color(red: 0.62, green: 0.38, blue: 0.0)
        case .ok: return Color(red: 0.12, green: 0.45, blue: 0.27)
        }
    }

    /// One word next to the month: "Overdue" / "Soon" / "Fine".
    var wordKey: String {
        switch self {
        case .overdue: return "status.overdue"
        case .soon: return "status.soon"
        case .ok: return "status.ok"
        }
    }

    /// Summary chips: "1 overdue" / "2 soon" / "6 fine".
    var countKey: String {
        switch self {
        case .overdue: return "chip.overdue"
        case .soon: return "chip.soon"
        case .ok: return "chip.ok"
        }
    }
}

/// Amount input with the currency symbol, accepting "1 200,50" or "1200.5".
struct MoneyField: View {
    let currency: Currency
    @Binding var value: Double?

    @State private var text = ""

    var body: some View {
        HStack(spacing: 4) {
            if currency == .usd { Text(currency.symbol).foregroundStyle(.secondary) }
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onAppear { text = value.map(Self.format) ?? "" }
                .onChange(of: text) { _, newValue in
                    let parsed = Self.parse(newValue)
                    if parsed != value { value = parsed }
                }
            if currency != .usd { Text(currency.symbol).foregroundStyle(.secondary) }
        }
    }

    static func parse(_ s: String) -> Double? {
        let cleaned = s.filter { $0.isNumber || $0 == "," || $0 == "." }.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(cleaned), v >= 0, v < 100_000_000 else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
}

/// A date that may be in the future (e.g. "insurance valid until"), optional.
struct OptionalFutureDateRow: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        if let current = date {
            HStack {
                DatePicker(title, selection: Binding(get: { current }, set: { date = $0 }), displayedComponents: .date)
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .frame(minHeight: 44)
        } else {
            Button {
                date = Calendar.current.date(byAdding: .year, value: 1, to: Date())
            } label: {
                LabeledField(label: title) { Text(L10n.t("field.setDate")).foregroundStyle(Color.accentColor) }
            }
            .foregroundStyle(.primary)
        }
    }
}

/// 12 month toggles for seasonal items (e.g. April and October).
struct SeasonMonthsGrid: View {
    @Binding var selected: Set<Int>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(1...12, id: \.self) { m in
                let on = selected.contains(m)
                Button {
                    if on { selected.remove(m) } else { selected.insert(m) }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(Fmt.shortMonth(m))
                        .font(.footnote.weight(on ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
