import Foundation

/// Built-in list of standard maintenance items. Items added from it store only the `key`, so their name is
/// always shown in the current app language. Typical intervals are hints for empty fields, never saved values.
public struct CatalogItem: Equatable, Identifiable {
    public enum Category: String, CaseIterable {
        case engine, fuel, lpg, cooling, transmission, brakes, chassis, electrical, body, general
    }

    public var key: String
    public var category: Category
    public var uk: String
    public var ru: String
    public var en: String
    public var hintKm: Int?
    public var hintMonths: Int?
    /// Extra phrases the assistant should understand for this item.
    public var synonyms: [String]

    public var id: String { key }

    public func name(_ lang: AssistantLanguage) -> String {
        switch lang {
        case .uk: return uk
        case .ru: return ru
        case .en: return en
        }
    }

    public var allNames: [String] { [uk, ru, en] }
}

public enum Catalog {
    private static func c(_ key: String, _ cat: CatalogItem.Category, _ uk: String, _ ru: String, _ en: String,
                          km: Int? = nil, months: Int? = nil, _ synonyms: [String] = []) -> CatalogItem {
        CatalogItem(key: key, category: cat, uk: uk, ru: ru, en: en, hintKm: km, hintMonths: months, synonyms: synonyms)
    }

    public static let items: [CatalogItem] = [
        // Engine
        c("engine_oil", .engine, "Моторне масло", "Моторное масло", "Engine oil", km: 10_000, months: 12,
          ["масло двигателя", "моторна олива", "motor oil", "oil change", "заміна масла", "замена масла"]),
        c("oil_filter", .engine, "Масляний фільтр", "Масляный фильтр", "Oil filter", km: 10_000, months: 12,
          ["фильтр масла", "фільтр масла"]),
        c("air_filter", .engine, "Повітряний фільтр", "Воздушный фильтр", "Air filter", km: 30_000, months: 24,
          ["фильтр воздуха", "фільтр повітря", "engine air filter"]),
        c("spark_plugs", .engine, "Свічки запалювання", "Свечи зажигания", "Spark plugs", km: 40_000, months: 48,
          ["свечи", "свічки", "plugs"]),
        c("glow_plugs", .engine, "Свічки розжарювання (дизель)", "Свечи накаливания (дизель)", "Glow plugs (diesel)",
          km: 100_000, ["свечи накала", "свічки розжарення"]),
        c("ignition_coils", .engine, "Котушки запалювання", "Катушки зажигания", "Ignition coils", km: 100_000,
          ["катушки", "котушки"]),
        c("timing_belt", .engine, "Ремінь ГРМ", "Ремень ГРМ", "Timing belt", km: 90_000, months: 60, ["грм"]),
        c("timing_rollers", .engine, "Ролики й натягувач ГРМ", "Ролики и натяжитель ГРМ", "Timing belt rollers and tensioner",
          km: 90_000, months: 60, ["ролики грм", "натяжитель грм"]),
        c("timing_chain", .engine, "Ланцюг ГРМ", "Цепь ГРМ", "Timing chain", km: 200_000, ["цепь", "ланцюг"]),
        c("water_pump", .engine, "Помпа (водяний насос)", "Помпа (водяной насос)", "Water pump", km: 90_000, months: 60,
          ["помпа", "водяной насос"]),
        c("drive_belt", .engine, "Приводний ремінь (ремінь генератора)", "Приводной ремень (ремень генератора)",
          "Drive belt (alternator belt)", km: 60_000, months: 48, ["ремень генератора", "ремінь генератора", "serpentine belt"]),
        c("drive_belt_tensioner", .engine, "Натягувач приводного ременя", "Натяжитель приводного ремня",
          "Drive belt tensioner", km: 120_000),
        c("valve_adjustment", .engine, "Регулювання клапанів", "Регулировка клапанов", "Valve adjustment", km: 60_000,
          ["клапаны", "клапани"]),
        c("throttle_cleaning", .engine, "Чищення дросельної заслінки", "Чистка дроссельной заслонки", "Throttle body cleaning",
          km: 30_000, ["дроссель", "дросель", "throttle"]),
        c("injector_cleaning", .engine, "Чищення форсунок", "Чистка форсунок", "Injector cleaning", km: 50_000,
          ["форсунки", "injectors"]),
        // Fuel and exhaust
        c("fuel_filter", .fuel, "Паливний фільтр", "Топливный фильтр", "Fuel filter", km: 40_000, months: 24,
          ["фильтр топлива", "фільтр палива"]),
        c("dpf_cleaning", .fuel, "Сажовий фільтр (DPF) — чищення", "Сажевый фильтр (DPF) — чистка", "Diesel particulate filter (DPF) cleaning",
          km: 100_000, ["сажевый", "сажовий", "dpf"]),
        // LPG
        c("lpg_filters", .lpg, "Фільтри ГБО", "Фильтры ГБО", "LPG filters", km: 10_000, months: 12,
          ["фильтр гбо", "фільтр гбо", "lpg filter", "gas filter", "газовый фильтр"]),
        c("lpg_service", .lpg, "ТО ГБО (регулювання)", "ТО ГБО (регулировка)", "LPG service (tuning)", km: 10_000, months: 12,
          ["то гбо", "обслуживание гбо", "обслуговування гбо", "регулировка гбо"]),
        c("lpg_reducer_kit", .lpg, "Ремкомплект редуктора ГБО", "Ремкомплект редуктора ГБО", "LPG reducer repair kit",
          km: 60_000, months: 36, ["редуктор гбо", "мембраны", "мембрани"]),
        // Cooling and air conditioning
        c("coolant", .cooling, "Антифриз", "Антифриз", "Coolant", km: 60_000, months: 48,
          ["охлаждающая жидкость", "охолоджувальна рідина", "тосол", "antifreeze"]),
        c("thermostat", .cooling, "Термостат", "Термостат", "Thermostat", km: 100_000),
        c("ac_recharge", .cooling, "Заправка кондиціонера", "Заправка кондиционера", "A/C recharge", months: 24,
          ["кондиционер", "кондиціонер", "фреон", "air conditioning"]),
        c("ac_cleaning", .cooling, "Антибактеріальна обробка кондиціонера", "Антибактериальная обработка кондиционера",
          "A/C antibacterial cleaning", months: 12, ["чистка кондиционера", "чищення кондиціонера"]),
        c("cabin_filter", .cooling, "Фільтр салону", "Салонный фильтр", "Cabin filter", km: 15_000, months: 12,
          ["фильтр салона", "салонний фільтр", "pollen filter", "фильтр кондиционера"]),
        // Transmission
        c("atf_full", .transmission, "Масло АКПП — повна заміна", "Масло АКПП — полная замена", "ATF — full change",
          km: 60_000, months: 48, ["масло акп", "масло коробки", "atf", "трансмиссионное масло", "gearbox oil"]),
        c("atf_partial", .transmission, "Масло АКПП — часткова заміна", "Масло АКПП — частичная замена", "ATF — partial change",
          km: 30_000, months: 24, ["частичная замена атф", "часткова заміна"]),
        c("atf_filter", .transmission, "Фільтр АКПП", "Фильтр АКПП", "Automatic transmission filter", km: 60_000,
          ["фильтр коробки", "фільтр коробки"]),
        c("mt_oil", .transmission, "Масло МКПП", "Масло МКПП", "Manual transmission oil", km: 90_000, months: 72,
          ["механика", "механіка", "manual gearbox oil"]),
        c("cvt_oil", .transmission, "Масло варіатора (CVT)", "Масло вариатора (CVT)", "CVT fluid", km: 60_000, months: 48,
          ["вариатор", "варіатор", "cvt"]),
        c("dsg_oil", .transmission, "Масло DSG", "Масло DSG", "DSG oil", km: 60_000, months: 48, ["dsg", "дсг"]),
        c("transfer_case_oil", .transmission, "Масло роздавальної коробки", "Масло раздаточной коробки", "Transfer case oil",
          km: 60_000, ["раздатка", "роздатка"]),
        c("axle_oil", .transmission, "Масло редуктора мосту", "Масло редуктора моста", "Differential oil", km: 60_000,
          ["редуктор", "мост", "differential"]),
        c("clutch", .transmission, "Комплект зчеплення", "Комплект сцепления", "Clutch kit", km: 120_000,
          ["сцепление", "зчеплення"]),
        c("power_steering_fluid", .transmission, "Рідина ГПК", "Жидкость ГУР", "Power steering fluid", km: 60_000, months: 36,
          ["гур", "гпк", "гидроусилитель", "гідропідсилювач"]),
        // Brakes
        c("brake_fluid", .brakes, "Гальмівна рідина", "Тормозная жидкость", "Brake fluid", months: 24, ["тормозуха"]),
        c("front_pads", .brakes, "Передні гальмівні колодки", "Передние тормозные колодки", "Front brake pads", km: 30_000,
          ["передние колодки", "передні колодки", "колодки"]),
        c("rear_pads", .brakes, "Задні гальмівні колодки", "Задние тормозные колодки", "Rear brake pads", km: 50_000,
          ["задние колодки", "задні колодки"]),
        c("front_discs", .brakes, "Передні гальмівні диски", "Передние тормозные диски", "Front brake discs", km: 60_000,
          ["передние диски", "передні диски", "rotors"]),
        c("rear_discs", .brakes, "Задні гальмівні диски", "Задние тормозные диски", "Rear brake discs", km: 90_000,
          ["задние диски", "задні диски"]),
        c("caliper_service", .brakes, "Обслуговування супортів", "Обслуживание суппортов", "Brake caliper service",
          km: 30_000, months: 12, ["суппорты", "супорти", "calipers"]),
        c("parking_brake", .brakes, "Стоянкове гальмо (регулювання)", "Стояночный тормоз (регулировка)",
          "Parking brake adjustment", km: 30_000, ["ручник", "handbrake"]),
        // Chassis and wheels
        c("wheel_alignment", .chassis, "Розвал-сходження", "Развал-схождение", "Wheel alignment", km: 15_000, months: 12,
          ["развал", "розвал", "alignment"]),
        c("suspension_check", .chassis, "Діагностика ходової", "Диагностика ходовой", "Suspension check", km: 15_000, months: 12,
          ["ходовая", "ходова", "подвеска", "підвіска"]),
        c("shock_absorbers", .chassis, "Амортизатори", "Амортизаторы", "Shock absorbers", km: 80_000,
          ["амортизаторы", "амортизатори", "shocks"]),
        c("seasonal_tires", .chassis, "Сезонна заміна шин", "Сезонная смена шин", "Seasonal tire change", months: 6,
          ["переобувка", "резина", "гума", "зимняя резина", "літня гума"]),
        c("tire_rotation", .chassis, "Ротація коліс", "Ротация колёс", "Tire rotation", km: 10_000, months: 6,
          ["ротация", "ротація"]),
        c("wheel_balancing", .chassis, "Балансування коліс", "Балансировка колёс", "Wheel balancing", km: 10_000, months: 12,
          ["балансировка", "балансування"]),
        c("tire_replacement", .chassis, "Заміна шин", "Замена шин", "Tire replacement", km: 50_000, months: 72,
          ["шины", "шини", "покрышки", "tires"]),
        // Electrical
        c("battery", .electrical, "Акумулятор", "Аккумулятор", "Battery", months: 60, ["акб"]),
        c("wiper_blades", .electrical, "Щітки склоочисника", "Щётки стеклоочистителя", "Wiper blades", months: 12,
          ["дворники", "двірники", "wipers"]),
        c("headlight_bulbs", .electrical, "Лампи фар", "Лампы фар", "Headlight bulbs", months: 24, ["лампочки", "bulbs"]),
        // Body
        c("anticorrosion", .body, "Антикорозійна обробка", "Антикоррозийная обработка", "Anti-corrosion treatment", months: 24,
          ["антикор", "rustproofing"]),
        c("polishing", .body, "Полірування кузова", "Полировка кузова", "Body polishing", months: 12, ["полировка", "полірування"]),
        // General
        c("scheduled_service", .general, "Планове ТО", "Плановое ТО", "Scheduled service", km: 15_000, months: 12,
          ["то", "техобслуживание", "техобслуговування", "service"]),
        c("diagnostics", .general, "Комп’ютерна діагностика", "Компьютерная диагностика", "Computer diagnostics",
          km: 30_000, months: 12, ["диагностика", "діагностика", "scan"]),
        c("inspection", .general, "Техогляд", "Техосмотр", "Vehicle inspection", months: 24, ["техосмотр", "техогляд", "inspection"]),
        c("insurance", .general, "Страховка", "Страховка", "Insurance", months: 12,
          ["осаго", "автоцивилка", "автоцивілка", "автогражданка", "страховка"])
    ]

    private static let byKey: [String: CatalogItem] = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

    public static func item(_ key: String?) -> CatalogItem? {
        guard let key else { return nil }
        return byKey[key]
    }

    public static func name(_ key: String?, _ lang: AssistantLanguage) -> String? {
        item(key)?.name(lang)
    }

    public static func categoryName(_ category: CatalogItem.Category, _ lang: AssistantLanguage) -> String {
        let names: [CatalogItem.Category: (String, String, String)] = [
            .engine: ("Двигун", "Двигатель", "Engine"),
            .fuel: ("Паливо та вихлоп", "Топливо и выхлоп", "Fuel and exhaust"),
            .lpg: ("ГБО", "ГБО", "LPG"),
            .cooling: ("Охолодження та кондиціонер", "Охлаждение и кондиционер", "Cooling and A/C"),
            .transmission: ("Трансмісія", "Трансмиссия", "Transmission"),
            .brakes: ("Гальма", "Тормоза", "Brakes"),
            .chassis: ("Ходова та колеса", "Ходовая и колёса", "Chassis and wheels"),
            .electrical: ("Електрика", "Электрика", "Electrical"),
            .body: ("Кузов", "Кузов", "Body"),
            .general: ("Загальне", "Общее", "General")
        ]
        let n = names[category]!
        switch lang {
        case .uk: return n.0
        case .ru: return n.1
        case .en: return n.2
        }
    }
}
