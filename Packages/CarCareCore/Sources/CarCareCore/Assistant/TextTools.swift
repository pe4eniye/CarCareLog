import Foundation

/// Text normalization, light stemming and fuzzy token comparison for the offline assistant.
public enum TextTools {
    /// Lowercase, ё→е, apostrophes removed, punctuation → spaces, collapsed whitespace.
    public static func normalize(_ text: String) -> String {
        var out = ""
        for ch in text.lowercased() {
            switch ch {
            case "ё": out.append("е")
            case "'", "’", "ʼ", "`", "´": continue
            default:
                if ch.isLetter || ch.isNumber { out.append(ch) } else { out.append(" ") }
            }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    public static func words(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    // Longest first. Covers common Russian/Ukrainian noun and adjective endings.
    private static let cyrillicSuffixes: [String] = [
        "ями", "ами", "ого", "его", "ому", "ему", "ыми", "ими", "ові", "еві",
        "ов", "ев", "ів", "ей", "ой", "ий", "ый", "ая", "яя", "ое", "ее", "ую", "юю",
        "ом", "ем", "ам", "ям", "ах", "ях", "их", "ых", "ок",
        "а", "я", "о", "е", "и", "ы", "у", "ю", "і", "ї", "ь", "й"
    ]

    /// Light stemming: strips one ending, keeping at least 3 letters.
    public static func stem(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) {
            for suffix in cyrillicSuffixes where word.hasSuffix(suffix) {
                let stem = String(word.dropLast(suffix.count))
                if stem.count >= 3 { return stem }
            }
            return word
        }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("s") && !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    /// Canonical tokens shared across languages, applied after stemming.
    static let canonical: [String: String] = [
        // filter
        "фільтр": "фильтр", "filter": "фильтр", "фильтер": "фильтр",
        // oil
        "олив": "масл", "оліва": "масл", "олів": "масл", "мастил": "масл", "oil": "масл",
        // engine
        "двигател": "моторн", "двигун": "моторн", "двигуна": "моторн", "engine": "моторн", "motor": "моторн",
        // gearbox
        "акпп": "акп", "коробк": "коробк", "gearbox": "коробк", "transmission": "коробк",
        // spark plugs and ignition
        "свічк": "свеч", "свічок": "свеч", "свечк": "свеч", "plug": "свеч", "spark": "свеч",
        "зажигани": "зажигани", "запалюванн": "зажигани", "ignition": "зажигани",
        // cabin
        "cabin": "салон", "салонн": "салон", "салону": "салон",
        // air
        "повітр": "воздух", "повітрян": "воздух", "воздушн": "воздух", "air": "воздух",
        // fuel
        "паливн": "топлив", "палив": "топлив", "топливн": "топлив", "fuel": "топлив",
        // LPG
        "lpg": "гбо", "газов": "газ",
        // brakes
        "гальмівн": "тормозн", "гальм": "тормоз", "brake": "тормоз",
        // coolant
        "антифриз": "антифриз", "coolant": "антифриз", "тосол": "антифриз",
        // belt
        "ремен": "ремен", "ремінь": "ремен", "belt": "ремен", "грм": "грм", "timing": "грм"
    ]

    /// normalize → words → stem → canonical.
    public static func tokens(_ text: String) -> [Token] {
        words(text).map { w in
            let s = stem(w)
            return Token(word: w, stem: canonical[s] ?? canonical[w] ?? s)
        }
    }

    public struct Token: Equatable, Hashable {
        public var word: String
        public var stem: String
    }

    /// Exact stem match; prefix match when the shorter stem has ≥ 4 letters;
    /// typo tolerance for words with ≥ 5 letters: edit distance ≤ 2 (≤ 1 when the stem is shorter than 6,
    /// otherwise "масло" would match "мосты"). Typos keep the first letter: "радіатор" is not "варіатор".
    public static func matches(_ a: Token, _ b: Token) -> Bool {
        if a.stem == b.stem { return true }
        let shorter = a.stem.count <= b.stem.count ? a.stem : b.stem
        let longer = a.stem.count <= b.stem.count ? b.stem : a.stem
        if shorter.count >= 4 && longer.hasPrefix(shorter) { return true }
        if a.word.count >= 5 && b.word.count >= 5 && shorter.count >= 4 && a.stem.first == b.stem.first {
            let limit = shorter.count >= 6 ? 2 : 1
            return editDistance(a.stem, b.stem) <= limit
        }
        return false
    }

    public static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}
