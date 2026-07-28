import Foundation
import os

/// Shared Documents JSON read/write for app stores.
/// Stores keep domain APIs; this owns encoder/decoder + atomic disk I/O only.
enum JSONFileStore {
    private static let logger = Logger(subsystem: "com.atlasbound.app", category: "persistence")

    /// Exact save contract. Mismatched versions start a fresh atlas.
    static let currentSchemaVersion = 3

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func documentsURL(fileName: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent(fileName)
    }

    static func load<T: Decodable>(_ type: T.Type, from fileURL: URL) -> T? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(type, from: data)
        } catch {
            logger.error("Failed to load \(fileURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to fileURL: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            logger.error("Failed to save \(fileURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
