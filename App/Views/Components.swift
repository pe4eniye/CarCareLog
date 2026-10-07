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
