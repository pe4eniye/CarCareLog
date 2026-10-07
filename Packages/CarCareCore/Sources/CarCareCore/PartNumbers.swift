import Foundation

public enum PartNumbers {
    /// Uppercase and strip spaces, hyphens and dots.
    public static func normalize(_ raw: String) -> String {
        var out = ""
        for ch in raw.uppercased() {
            if ch == "-" || ch == "." || ch.isWhitespace { continue }
            out.append(ch)
        }
        return out
    }

    public enum OEMChange: Equatable {
        /// No old number, or the new one is empty: just save.
        case none
        /// Same number after normalization.
        case same
        /// A different number replaces an existing one: ask "Replace / Keep as is".
        case different(old: String)
    }

    public static func oemChange(existing: String?, new: String?) -> OEMChange {
        let old = normalize(existing ?? "")
        let nw = normalize(new ?? "")
        if old.isEmpty || nw.isEmpty { return .none }
        return old == nw ? .same : .different(old: existing ?? "")
    }

    public struct Conflict: Equatable {
        public var number: String
        public var itemID: UUID
        public var itemName: String
        public var asOEM: Bool
    }

    /// Numbers that already exist on ANOTHER item, as OEM or analog.
    public static func conflicts(numbers: [String], editingItemID: UUID?, items: [ItemInfo]) -> [Conflict] {
        var result: [Conflict] = []
        for number in numbers {
            let n = normalize(number)
            if n.isEmpty { continue }
            for item in items where item.id != editingItemID {
                if let oem = item.oemNumber, normalize(oem) == n {
                    result.append(Conflict(number: number, itemID: item.id, itemName: item.name, asOEM: true))
                } else if item.analogNumbers.contains(where: { normalize($0) == n }) {
                    result.append(Conflict(number: number, itemID: item.id, itemName: item.name, asOEM: false))
                }
            }
        }
        return result
    }

    /// Removes empty values and duplicates (by normalized form), keeps the user's spelling.
    public static func cleanList(_ numbers: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in numbers {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let n = normalize(trimmed)
            if n.isEmpty || seen.contains(n) { continue }
            seen.insert(n)
            result.append(trimmed)
        }
        return result
    }
}
