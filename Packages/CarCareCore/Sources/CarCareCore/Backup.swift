import Foundation

/// One JSON file with all user data. `formatVersion` lets future versions migrate old files.
public struct BackupFile: Codable, Equatable {
    // 2: car "name" instead of make/model/year, item "isArchived", entry "itemNames". Version 1 files still load.
    // 3: item kind/season/validUntil, entry costs/currency/note.
    public static let currentFormatVersion = 3
    public static let appIdentifier = "CarCareLog"

    public var app: String
    public var formatVersion: Int
    public var exportedAt: Date
    public var car: CarInfo?
    public var items: [ItemInfo]
    public var entries: [ServiceEntryInfo]
    public var odometerReadings: [OdometerReadingInfo]

    public init(snapshot: DataSnapshot, exportedAt: Date) {
        app = Self.appIdentifier
        formatVersion = Self.currentFormatVersion
        self.exportedAt = exportedAt
        car = snapshot.car
        items = snapshot.items
        entries = snapshot.entries
        odometerReadings = snapshot.odometerReadings
    }

    public var snapshot: DataSnapshot {
        DataSnapshot(car: car, items: items, entries: entries, odometerReadings: odometerReadings)
    }
}

public enum BackupError: Error, Equatable {
    case notABackup
    case newerFormat(Int)
}

public enum BackupCodec {
    public static func encode(_ snapshot: DataSnapshot, exportedAt: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(formatDate(date))
        }
        return try encoder.encode(BackupFile(snapshot: snapshot, exportedAt: exportedAt))
    }

    public static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            guard let d = parseDate(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(s)")
            }
            return d
        }
        // Check the header first so a wrong file gives a clear error.
        struct Header: Decodable { var app: String?; var formatVersion: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.app == BackupFile.appIdentifier,
              let version = header.formatVersion else {
            throw BackupError.notABackup
        }
        if version > BackupFile.currentFormatVersion { throw BackupError.newerFormat(version) }

        let file: BackupFile
        do {
            file = try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
        // Entries may reference deleted items: their names are kept in `itemNames`.
        return file
    }

    public static func suggestedFileName(date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "CarCareLog-backup-%04d-%02d-%02d.json", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func formatDate(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
