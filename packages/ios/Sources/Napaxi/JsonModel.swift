import Foundation

// iOS adapter parity for the Flutter shared JSON model helpers
// (`packages/flutter/lib/models/json_model.dart`). The Flutter model layer is
// intentionally thin: it accepts contract-owned camelCase/snake_case aliases,
// preserves unknown adapter fields, and lets core/contract own business
// semantics. These free functions are the Swift equivalents over
// `NapaxiJSONValue` maps, so each adapter decodes model maps the same way.

/// Returns a shallow copy that model instances can keep as their raw payload.
public func jsonModelRaw(_ map: [String: NapaxiJSONValue]) -> [String: NapaxiJSONValue] {
    map
}

/// Merges a model's canonical encoded fields over its raw payload. Unknown
/// fields survive round-trips while normalized fields use the canonical
/// representation.
public func mergePreservedJsonModel(
    _ raw: [String: NapaxiJSONValue],
    _ canonical: [String: NapaxiJSONValue]
) -> [String: NapaxiJSONValue] {
    var merged = raw
    for (key, value) in canonical {
        merged[key] = value
    }
    return merged
}

/// Decode the first present key as an ISO-8601 / RFC-3339 date string.
public func jsonDateTimeField(_ map: [String: NapaxiJSONValue], _ keys: [String]) -> Date? {
    for key in keys {
        if let value = map[key]?.stringValue, let date = napaxiParseDate(value) {
            return date
        }
    }
    return nil
}

/// Decode the first present key as an integer.
public func jsonIntField(
    _ map: [String: NapaxiJSONValue],
    _ keys: [String],
    defaultValue: Int = 0
) -> Int {
    for key in keys {
        if let number = map[key]?.numberValue {
            return Int(number)
        }
    }
    return defaultValue
}

/// Decode the first present key as a double.
public func jsonDoubleField(
    _ map: [String: NapaxiJSONValue],
    _ keys: [String],
    defaultValue: Double = 0
) -> Double {
    for key in keys {
        if let number = map[key]?.numberValue {
            return number
        }
    }
    return defaultValue
}

/// Decode the first present key as a bool.
public func jsonBoolField(
    _ map: [String: NapaxiJSONValue],
    _ keys: [String],
    defaultValue: Bool = false
) -> Bool {
    for key in keys {
        if let value = map[key]?.boolValue {
            return value
        }
    }
    return defaultValue
}

/// Decode the first present key as a string. When `nonEmpty` is true, empty
/// strings are skipped.
public func jsonStringField(
    _ map: [String: NapaxiJSONValue],
    _ keys: [String],
    nonEmpty: Bool = true
) -> String? {
    for key in keys {
        if let value = map[key]?.stringValue, !nonEmpty || !value.isEmpty {
            return value
        }
    }
    return nil
}

/// Decode the first present key as a list of strings.
public func jsonStringListField(
    _ map: [String: NapaxiJSONValue],
    _ keys: [String]
) -> [String] {
    for key in keys {
        if let array = map[key]?.arrayValue {
            return array.map { $0.stringValue ?? napaxiStringify($0) }
        }
    }
    return []
}

private func napaxiParseDate(_ value: String) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: value) { return date }
    iso.formatOptions = [.withInternetDateTime]
    return iso.date(from: value)
}

private func napaxiStringify(_ value: NapaxiJSONValue) -> String {
    switch value {
    case .string(let string): return string
    case .number(let number):
        return number.rounded() == number ? String(Int(number)) : String(number)
    case .bool(let bool): return String(bool)
    case .null: return ""
    case .array, .object: return (try? NapaxiRawJSON(value).jsonString()) ?? ""
    }
}
