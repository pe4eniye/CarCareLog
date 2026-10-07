import Foundation

/// Built-in multilingual synonym table. Each group lists phrases that mean the same part.
/// A user item that is named like one phrase of a group also answers to every other phrase of it.
/// Single-word translations (filter/фільтр/фильтр, oil/олива/масло, …) are handled by
/// `TextTools.canonical`, so groups only need phrases that differ in structure.
public enum Synonyms {
    public static let groups: [[String]] = [
        // Engine oil
        ["моторное масло", "масло двигателя", "масло в двигателе", "моторне масло", "моторна олива",
         "олива двигуна", "масло двигуна", "engine oil", "motor oil"],
        // Oil filter
        ["масляный фильтр", "фильтр масла", "масляний фільтр", "фільтр масла", "фільтр оливи", "oil filter"],
        // Automatic transmission fluid
        ["масло акп", "масло акпп", "atf", "масло коробки", "масло в коробке", "масло коробки передач",
         "трансмиссионное масло", "олива акпп", "олива коробки", "трансмісійна олива", "трансмісійне масло",
         "масло автомата", "gearbox oil", "transmission fluid", "transmission oil", "automatic transmission fluid"],
        // Transmission filter
        ["фильтр акп", "фильтр акпп", "фільтр акп", "фільтр акпп", "фильтр коробки", "transmission filter"],
        // Cabin filter
        ["салонный фильтр", "фильтр салона", "фільтр салону", "салонний фільтр", "фильтр кондиционера",
         "cabin filter", "cabin air filter", "pollen filter"],
        // Engine air filter
        ["воздушный фильтр", "фильтр воздуха", "повітряний фільтр", "фільтр повітря", "air filter",
         "engine air filter"],
        // Fuel filter
        ["топливный фильтр", "фильтр топлива", "паливний фільтр", "фільтр палива", "fuel filter"],
        // Spark plugs
        ["свечи зажигания", "свечи", "свічки запалювання", "свічки", "spark plugs", "plugs"],
        // LPG filters
        ["фильтр гбо", "фильтры гбо", "фільтр гбо", "фільтри гбо", "фильтр газа", "газовый фильтр",
         "газовий фільтр", "lpg filter", "gas filter"],
        // LPG service
        ["гбо", "газовое оборудование", "газове обладнання", "lpg", "autogas", "то гбо", "обслуживание гбо",
         "обслуговування гбо", "lpg service"],
        // Brake fluid
        ["тормозная жидкость", "гальмівна рідина", "brake fluid"],
        // Brake pads
        ["тормозные колодки", "колодки", "гальмівні колодки", "brake pads"],
        // Coolant
        ["антифриз", "охлаждающая жидкость", "охолоджувальна рідина", "тосол", "coolant", "antifreeze"],
        // Timing belt
        ["ремень грм", "ремінь грм", "грм", "timing belt"],
        // Drive belt
        ["приводной ремень", "ремень генератора", "приводний ремінь", "ремінь генератора", "drive belt",
         "serpentine belt"]
    ]

    static let tokenizedGroups: [[[TextTools.Token]]] = groups.map { group in
        group.map { ItemMatcher.contentTokens($0, fallbackToAll: true) }
    }
}
