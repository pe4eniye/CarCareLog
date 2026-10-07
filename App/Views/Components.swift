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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.body.weight(.medium))
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
            if let d = forecast.dueDate { parts.append(Fmt.date(d)) }
            if let km = forecast.dueKm { parts.append(Fmt.km(km)) }
            return L10n.f("home.overdueSince", parts.joined(separator: " · "))
        }
        if forecast.dueDate == nil, let km = forecast.dueKm {
            return L10n.f("home.atKm", Fmt.km(km))
        }
        return "≈ " + Fmt.km(forecast.predictedOdometerKm)
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
                let parsed = Fmt.parseInt(newValue)
                if parsed != value { value = parsed }
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
