import Foundation

// The API serialises records from a Redis-backed store. Most fields are typed
// correctly today, but the published schema still allows strings where a
// client would expect booleans or numbers, and empty strings where it would
// expect null. These helpers accept every documented representation so that
// a server-side change in representation does not break decoding.

extension KeyedDecodingContainer {
    /// Returns `nil` when the key is absent or null.
    private func isPresent(_ key: Key) throws -> Bool {
        guard contains(key) else { return false }
        return try !decodeNil(forKey: key)
    }

    /// Decodes a boolean from `true`, `"true"`, `"1"`, `1`, and their
    /// negatives. Returns `nil` for null, missing, or `""`.
    func lenientBool(_ key: Key) throws -> Bool? {
        guard try isPresent(key) else { return nil }
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decode(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            case "": return nil
            default: break
            }
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a boolean")
    }

    /// Decodes a number from a JSON number or a numeric string. Returns `nil`
    /// for null, missing, or `""`.
    func lenientDouble(_ key: Key) throws -> Double? {
        guard try isPresent(key) else { return nil }
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            if value.isEmpty { return nil }
            if let parsed = Double(value) { return parsed }
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a number")
    }

    /// Decodes an integer from a JSON number (fractions are truncated) or a
    /// numeric string. Returns `nil` for null, missing, or `""`.
    func lenientInt(_ key: Key) throws -> Int? {
        guard let value = try lenientDouble(key) else { return nil }
        return Int(value)
    }

    /// Decodes a Unix timestamp (seconds, possibly fractional) into a `Date`.
    func timestamp(_ key: Key) throws -> Date? {
        guard let seconds = try lenientDouble(key) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Decodes a string, accepting numbers and booleans as their textual
    /// forms. Returns `nil` for null or missing.
    func lenientString(_ key: Key) throws -> String? {
        guard try isPresent(key) else { return nil }
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a string")
    }

    /// Decodes a list of strings from an array, or from a single string that
    /// may hold comma-separated values. Blank entries are dropped.
    func stringList(_ key: Key) throws -> [String] {
        guard try isPresent(key) else { return [] }
        if let values = try? decode([String].self, forKey: key) {
            return values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let value = try? decode(String.self, forKey: key) {
            return value.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a list of strings")
    }

    /// Decodes a URL from a string, ignoring blank or unparseable values.
    func lenientURL(_ key: Key) throws -> URL? {
        guard let string = try lenientString(key), !string.isEmpty else { return nil }
        return URL(string: string)
    }
}
