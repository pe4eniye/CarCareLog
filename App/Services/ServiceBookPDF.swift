import UIKit
import SwiftData
import CarCareCore

/// "Service book" PDF in the current app language: cover info, schedule summary, full history, part numbers.
enum ServiceBookPDF {
    private static let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 in points
    private static let margin: CGFloat = 40
    private static let accent = UIColor(red: 0.06, green: 0.55, blue: 0.49, alpha: 1)

    @MainActor
    static func make(context: ModelContext) -> URL? {
        let snap = SnapshotBuilder.fetch(context)
        let now = Date()
        let cal = Fmt.calendar
        let statuses = ForecastEngine.statuses(for: snap, today: now, calendar: cal)
        let current = snap.currentOdometerKm
        let carName = snap.car?.name.isEmpty == false ? snap.car!.name : "CarCare Log"
        // Computed here: the drawing closure below is not on the main actor.
        let intervals = Dictionary(snap.items.map { ($0.id, ItemRow.intervalText(km: $0.intervalKm, months: $0.intervalMonths)) },
                                   uniquingKeysWith: { a, _ in a })

        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { ctx in
            var y: CGFloat = 0
            var pageNumber = 0
            let width = page.width - margin * 2

            func newPage() {
                ctx.beginPage()
                pageNumber += 1
                y = margin
                draw("CarCare Log · \(L10n.t("pdf.title")) · \(pageNumber)", at: CGPoint(x: margin, y: page.height - 28),
                     width: width, font: .systemFont(ofSize: 8), color: .gray)
            }
            func ensure(_ height: CGFloat) {
                if y + height > page.height - 48 { newPage() }
            }
            @discardableResult
            func text(_ s: String, x: CGFloat = margin, w: CGFloat? = nil, size: CGFloat = 10,
                      weight: UIFont.Weight = .regular, color: UIColor = .black, advance: Bool = true) -> CGFloat {
                let h = draw(s, at: CGPoint(x: x, y: y), width: w ?? width,
                             font: .systemFont(ofSize: size, weight: weight), color: color)
                if advance { y += h }
                return h
            }
            func line() {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: page.width - margin, y: y))
                UIColor(white: 0.85, alpha: 1).setStroke()
                path.lineWidth = 0.5
                path.stroke()
            }
            func sectionTitle(_ s: String) {
                ensure(40)
                y += 14
                text(s, size: 14, weight: .semibold, color: accent)
                y += 4
                line()
                y += 6
            }

            // Cover band
            newPage()
            accent.setFill()
            UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: width, height: 96), cornerRadius: 12).fill()
            let top = y
            y = top + 16
            text(L10n.t("pdf.title"), x: margin + 18, w: width - 36, size: 11, weight: .medium, color: .white)
            text(carName, x: margin + 18, w: width - 36, size: 22, weight: .bold, color: .white)
            var meta: [String] = []
            if let vin = snap.car?.vin, !vin.isEmpty { meta.append("VIN \(vin)") }
            if let km = current { meta.append(L10n.f("pdf.odometer", Fmt.km(km))) }
            meta.append(L10n.f("pdf.generated", Fmt.date(now)))
            text(meta.joined(separator: "  ·  "), x: margin + 18, w: width - 36, size: 10, color: .white)
            y = top + 96 + 8

            // Schedule summary
            let active = ForecastEngine.urgencySorted(snap.activeItems, statuses: statuses)
            if !active.isEmpty {
                sectionTitle(L10n.t("pdf.schedule"))
                let cols: [CGFloat] = [0.32, 0.22, 0.23, 0.23].map { $0 * width }
                func row(_ values: [String], bold: Bool = false, dot: UIColor? = nil) {
                    let heights = values.enumerated().map { i, v in
                        measure(v, width: cols[i] - 8, font: .systemFont(ofSize: 9, weight: bold ? .semibold : .regular))
                    }
                    let h = (heights.max() ?? 12) + 6
                    ensure(h)
                    var x = margin
                    for (i, v) in values.enumerated() {
                        var tx = x
                        if i == 0, let dot {
                            dot.setFill()
                            UIBezierPath(ovalIn: CGRect(x: x, y: y + 3.5, width: 6, height: 6)).fill()
                            tx += 10
                        }
                        draw(v, at: CGPoint(x: tx, y: y), width: cols[i] - 8 - (tx - x),
                             font: .systemFont(ofSize: 9, weight: bold ? .semibold : .regular),
                             color: bold ? .darkGray : .black)
                        x += cols[i]
                    }
                    y += h
                }
                row([L10n.t("pdf.colItem"), L10n.t("pdf.colInterval"), L10n.t("pdf.colLast"), L10n.t("pdf.colNext")],
                    bold: true)
                for item in active {
                    let interval = intervals[item.id] ?? ""
                    let last = ForecastEngine.lastEntry(for: item.id, entries: snap.entries)
                        .map { "\(Fmt.date($0.date))\n\(Fmt.km($0.odometerKm))" } ?? "—"
                    var next = "—"
                    var color = UIColor.lightGray
                    if let f = statuses[item.id]?.forecast {
                        let u = f.urgency(today: now, calendar: cal, currentOdometerKm: current)
                        color = u == .overdue ? .systemRed : (u == .soon ? .systemOrange : .systemGreen)
                        if f.isOverdue {
                            next = L10n.t("home.overdue")
                        } else if let d = f.dueDate {
                            next = "≈ \(Fmt.monthYear(d))\n≈ \(Fmt.km(f.predictedOdometerKm))"
                        } else if let km = f.dueKm {
                            next = Fmt.km(km)
                        }
                    }
                    row([item.name, interval.isEmpty ? "—" : interval, last, next], dot: color)
                }
            }

            // History
            let history = snap.entries.sorted { $0.date != $1.date ? $0.date > $1.date : $0.odometerKm > $1.odometerKm }
            if !history.isEmpty {
                sectionTitle(L10n.f("pdf.history", history.count))
                for e in history {
                    let names = e.displayNames(items: snap.items).joined(separator: ", ")
                    let h = measure(names, width: width - 170, font: .systemFont(ofSize: 10)) + 8
                    ensure(h)
                    draw(Fmt.date(e.date), at: CGPoint(x: margin, y: y), width: 90,
                         font: .systemFont(ofSize: 10, weight: .semibold), color: .black)
                    draw(Fmt.km(e.odometerKm), at: CGPoint(x: margin + 92, y: y), width: 76,
                         font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular), color: .darkGray)
                    draw(names, at: CGPoint(x: margin + 170, y: y), width: width - 170,
                         font: .systemFont(ofSize: 10), color: .black)
                    y += h
                }
            }

            // Part numbers
            let numbered = snap.items.filter { !($0.oemNumber ?? "").isEmpty || !$0.analogNumbers.isEmpty }
            if !numbered.isEmpty {
                sectionTitle(L10n.t("pdf.numbers"))
                for item in numbered {
                    var parts: [String] = []
                    if let oem = item.oemNumber, !oem.isEmpty { parts.append("OEM: \(oem)") }
                    if !item.analogNumbers.isEmpty {
                        parts.append(L10n.f("pdf.analogs", item.analogNumbers.joined(separator: ", ")))
                    }
                    let body = parts.joined(separator: "   ")
                    let h = max(measure(item.name, width: 160, font: .systemFont(ofSize: 10, weight: .semibold)),
                                measure(body, width: width - 170, font: .systemFont(ofSize: 10))) + 6
                    ensure(h)
                    draw(item.name, at: CGPoint(x: margin, y: y), width: 160,
                         font: .systemFont(ofSize: 10, weight: .semibold), color: .black)
                    draw(body, at: CGPoint(x: margin + 170, y: y), width: width - 170,
                         font: .systemFont(ofSize: 10), color: .black)
                    y += h
                }
            }
        }

        let name = "CarCareLog-service-book-\(BackupCodec.suggestedFileName(date: now, calendar: cal).suffix(15))"
            .replacingOccurrences(of: ".json", with: ".pdf")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    @discardableResult
    private static func draw(_ s: String, at point: CGPoint, width: CGFloat, font: UIFont, color: UIColor) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let rect = (s as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                attributes: attrs, context: nil)
        (s as NSString).draw(with: CGRect(x: point.x, y: point.y, width: width, height: ceil(rect.height)),
                             options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        return ceil(rect.height)
    }

    private static func measure(_ s: String, width: CGFloat, font: UIFont) -> CGFloat {
        let rect = (s as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                attributes: [.font: font], context: nil)
        return ceil(rect.height)
    }
}
