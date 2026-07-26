import Foundation

/// Local development flags. Prefer root `.env` (synced into the app bundle as `atlasbound.env`).
enum DevConfig {
    /// Master switch from `.env` / process environment. Settings can only expose Sim GPS when this is true.
    static var isSimGPSFeatureAvailable: Bool {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["ATLASBOUND_ENABLE_SIM_GPS"] {
            return Self.isTruthy(value)
        }
        if let value = bundledEnv["ATLASBOUND_ENABLE_SIM_GPS"] {
            return Self.isTruthy(value)
        }
        return false
        #else
        return false
        #endif
    }

    private static let bundledEnv: [String: String] = {
        #if DEBUG
        guard let url = Bundle.main.url(forResource: "atlasbound", withExtension: "env"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        return parseEnv(text)
        #else
        return [:]
        #endif
    }()

    private static func parseEnv(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    private static func isTruthy(_ value: String) -> Bool {
        ["1", "true", "yes", "on"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
