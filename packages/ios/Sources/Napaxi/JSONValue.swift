import Foundation

public enum NapaxiJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([NapaxiJSONValue])
    case object([String: NapaxiJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([NapaxiJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: NapaxiJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: NapaxiJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [NapaxiJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

public struct NapaxiRawJSON: Codable, Equatable, Sendable {
    public var value: NapaxiJSONValue

    public init(_ value: NapaxiJSONValue = .object([:])) {
        self.value = value
    }

    public init(data: Data) throws {
        self.value = try JSONDecoder().decode(NapaxiJSONValue.self, from: data)
    }

    public init(jsonString: String) throws {
        try self.init(data: Data(jsonString.utf8))
    }

    public func data() throws -> Data {
        try JSONEncoder().encode(value)
    }

    public func jsonString() throws -> String {
        String(data: try data(), encoding: .utf8) ?? "{}"
    }
}

extension NapaxiJSONValue {
    func requiredString() throws -> String {
        guard case .string(let value) = self else {
            throw NapaxiError.invalidJSON("Expected JSON string")
        }
        return value
    }

    func decodedArray<T: Decodable>(of type: T.Type) throws -> [T] {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode([T].self, from: data)
    }

    func decodedObjectList<T: Decodable>(of type: T.Type) throws -> [T] {
        try decodeJsonObjectListFromValue(self) { object in
            try NapaxiJSONValue.object(object).decodedObject(of: T.self)
        }
    }

    func decodedObject<T: Decodable>(of type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func requiredBool() throws -> Bool {
        guard case .bool(let value) = self else {
            throw NapaxiError.invalidJSON("Expected JSON bool")
        }
        return value
    }

    func requiredInt() throws -> Int {
        if let value = numberValue {
            return Int(value)
        }
        if let value = stringValue, let parsed = Int(value) {
            return parsed
        }
        throw NapaxiError.invalidJSON("Expected JSON integer")
    }
}

extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public func decodeJsonValue(_ jsonString: String) throws -> NapaxiJSONValue {
    try NapaxiRawJSON(jsonString: jsonString).value
}

public func decodeJsonObject(_ jsonString: String) throws -> [String: NapaxiJSONValue] {
    let decoded = try decodeJsonValue(jsonString)
    if let object = asJsonObject(decoded) {
        return object
    }
    throw NapaxiError.invalidJSON("Expected a JSON object")
}

public func decodeJsonArray(_ jsonString: String) throws -> [NapaxiJSONValue] {
    let decoded = try decodeJsonValue(jsonString)
    if let array = asJsonArray(decoded) {
        return array
    }
    throw NapaxiError.invalidJSON("Expected a JSON array")
}

public func asJsonObject(_ value: NapaxiJSONValue?) -> [String: NapaxiJSONValue]? {
    value?.objectValue
}

public func asJsonArray(_ value: NapaxiJSONValue?) -> [NapaxiJSONValue]? {
    value?.arrayValue
}

public func jsonErrorMessage(_ decoded: NapaxiJSONValue?) -> String? {
    guard let error = asJsonObject(decoded)?["error"] else {
        return nil
    }
    return error.jsonCodecDisplayString
}

public func throwIfJsonError(_ decoded: NapaxiJSONValue?) throws {
    if let error = jsonErrorMessage(decoded) {
        throw NapaxiError.invalidState(error)
    }
}

public func decodeJsonObjectListFromValue<T>(
    _ decoded: NapaxiJSONValue?,
    _ convert: ([String: NapaxiJSONValue]) throws -> T
) throws -> [T] {
    guard let items = asJsonArray(decoded) else {
        throw NapaxiError.invalidJSON("Expected a JSON array")
    }
    return try items.compactMap { item in
        guard let object = asJsonObject(item) else {
            return nil
        }
        return try convert(object)
    }
}

public func decodeJsonObjectList<T>(
    _ jsonString: String,
    _ convert: ([String: NapaxiJSONValue]) throws -> T
) throws -> [T] {
    try decodeJsonObjectListFromValue(decodeJsonValue(jsonString), convert)
}

extension NapaxiJSONValue {
    var jsonCodecDisplayString: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return String(value)
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .string(let value):
            return value
        case .array(let values):
            return "[\(values.map(\.jsonCodecDisplayString).joined(separator: ", "))]"
        case .object(let object):
            let entries = object.keys.sorted().map { key in
                "\(key): \(object[key]?.jsonCodecDisplayString ?? "null")"
            }
            return "{\(entries.joined(separator: ", "))}"
        }
    }
}
