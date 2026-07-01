import Foundation

public struct NapaxiResolvedFile: Codable, Equatable, Sendable {
    public var sandboxPath: String
    public var realPath: String
    public var filename: String
    public var mimeType: String
    public var isImage: Bool
    public var isDirectory: Bool
    public var exists: Bool
    public var sizeBytes: Int?

    public init(
        sandboxPath: String,
        realPath: String,
        filename: String,
        mimeType: String,
        isImage: Bool,
        isDirectory: Bool = false,
        exists: Bool,
        sizeBytes: Int? = nil
    ) {
        self.sandboxPath = sandboxPath
        self.realPath = realPath
        self.filename = filename
        self.mimeType = mimeType
        self.isImage = isImage
        self.isDirectory = isDirectory
        self.exists = exists
        self.sizeBytes = sizeBytes
    }

    public init(raw: NapaxiJSONValue) {
        self = Self.fromMap(raw.napaxiObjectValue)
    }

    public init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: NapaxiJSONValue].self)
        self = Self.fromMap(object)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NapaxiJSONValue.object(toMap()))
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            sandboxPath: map["sandbox_path"]?.stringValue ?? "",
            realPath: map["real_path"]?.stringValue ?? "",
            filename: map["filename"]?.stringValue ?? "",
            mimeType: map["mime_type"]?.stringValue ?? "application/octet-stream",
            isImage: map["is_image"]?.boolValue ?? false,
            isDirectory: map["is_directory"]?.boolValue ?? false,
            exists: map["exists"]?.boolValue ?? false,
            sizeBytes: map["size_bytes"]?.napaxiIntValue
        )
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        var map: [String: NapaxiJSONValue] = [
            "sandbox_path": .string(sandboxPath),
            "real_path": .string(realPath),
            "filename": .string(filename),
            "mime_type": .string(mimeType),
            "is_image": .bool(isImage),
            "is_directory": .bool(isDirectory),
            "exists": .bool(exists),
        ]
        if let sizeBytes {
            map["size_bytes"] = .number(Double(sizeBytes))
        }
        return map
    }
}

public struct NapaxiWorkspaceFileInfo: Codable, Equatable, Sendable {
    public var name: String
    public var sandboxPath: String
    public var realPath: String
    public var mimeType: String
    public var isDirectory: Bool
    public var sizeBytes: Int
    public var modified: Date

    public init(
        name: String,
        sandboxPath: String,
        realPath: String,
        mimeType: String,
        isDirectory: Bool,
        sizeBytes: Int,
        modified: Date
    ) {
        self.name = name
        self.sandboxPath = sandboxPath
        self.realPath = realPath
        self.mimeType = mimeType
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.modified = modified
    }

    public init(raw: NapaxiJSONValue) {
        self = Self.fromMap(raw.napaxiObjectValue)
    }

    public init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: NapaxiJSONValue].self)
        self = Self.fromMap(object)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NapaxiJSONValue.object(toMap()))
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            name: map["name"]?.stringValue ?? "",
            sandboxPath: map["sandbox_path"]?.stringValue ?? "",
            realPath: map["real_path"]?.stringValue ?? "",
            mimeType: map["mime_type"]?.stringValue ?? "application/octet-stream",
            isDirectory: map["is_directory"]?.boolValue ?? false,
            sizeBytes: map["size_bytes"]?.napaxiIntValue ?? 0,
            modified: Date(timeIntervalSince1970: Double(map["modified"]?.napaxiIntValue ?? 0) / 1_000)
        )
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        [
            "name": .string(name),
            "sandbox_path": .string(sandboxPath),
            "real_path": .string(realPath),
            "mime_type": .string(mimeType),
            "is_directory": .bool(isDirectory),
            "size_bytes": .number(Double(sizeBytes)),
            "modified": .number(modified.timeIntervalSince1970 * 1_000),
        ]
    }
}

public struct NapaxiOpenFileResult: Codable, Equatable, Sendable {
    public var success: Bool
    public var error: String?
    public var code: String?

    public init(success: Bool, error: String? = nil, code: String? = nil) {
        self.success = success
        self.error = error
        self.code = code
    }

    public func jsonValue() -> NapaxiJSONValue {
        var object: [String: NapaxiJSONValue] = ["success": .bool(success)]
        if let error {
            object["error"] = .string(error)
        }
        if let code {
            object["code"] = .string(code)
        }
        return .object(object)
    }
}

extension NapaxiJSONValue {
    var napaxiObjectValue: [String: NapaxiJSONValue] {
        if case .object(let value) = self { return value }
        return [:]
    }

    var napaxiArrayValue: [NapaxiJSONValue] {
        if case .array(let value) = self { return value }
        return []
    }

    var napaxiIntValue: Int? {
        guard let numberValue else { return nil }
        return Int(numberValue)
    }
}
