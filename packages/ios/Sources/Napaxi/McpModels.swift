import Foundation

public extension NapaxiStableString where Tag == NapaxiMcpConnectionStateTag {
    static let disconnected = Self(rawValue: "disconnected")
    static let connecting = Self(rawValue: "connecting")
    static let connected = Self(rawValue: "connected")
    static let error = Self(rawValue: "error")
}

public extension NapaxiStableModel where Tag == NapaxiMcpServerInfoTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(
        name: String,
        url: String,
        connected: Bool,
        tools: [String] = [],
        error: String? = nil,
        authRequired: Bool = false,
        oauthConnected: Bool = false,
        oauthPending: Bool = false,
        transport: String? = nil
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "name": .string(name),
            "url": .string(url),
            "connected": .bool(connected),
            "tools": .array(tools.map { .string($0) }),
            "authRequired": .bool(authRequired),
            "oauthConnected": .bool(oauthConnected),
            "oauthPending": .bool(oauthPending),
        ]
        if let error { raw["error"] = .string(error) }
        if let transport { raw["transport"] = .string(transport) }
        self.init(raw: raw)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        let object = try mcpObjectMap(from: jsonString)
        try validateMcpServerInfoObject(object)
        return Self(raw: object)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var name: String { string("name") ?? "" }
    var url: String { string("url") ?? "" }
    var connected: Bool { bool("connected") ?? false }
    var tools: [String] { raw.stringArray("tools") ?? [] }
    var error: String? {
        guard let value = string("error"), !value.isEmpty else { return nil }
        return value
    }
    var authRequired: Bool { bool("authRequired") ?? bool("auth_required") ?? false }
    var oauthConnected: Bool { bool("oauthConnected") ?? bool("oauth_connected") ?? false }
    var oauthPending: Bool { bool("oauthPending") ?? bool("oauth_pending") ?? false }
    var transport: String? { string("transport") }
    var connectionState: NapaxiMcpConnectionState {
        if error != nil { return .error }
        if oauthPending { return .connecting }
        if connected { return .connected }
        return .disconnected
    }
}

public extension NapaxiStableModel where Tag == NapaxiMcpToolInfoTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(name: String, serverName: String) {
        self.init(raw: [
            "name": .string(name),
            "serverName": .string(serverName),
        ])
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        let object = try mcpObjectMap(from: jsonString)
        try validateMcpToolInfoObject(object)
        return Self(raw: object)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var name: String { string("name") ?? "" }
    var serverName: String { string("serverName") ?? string("server_name") ?? "" }
}

public extension NapaxiStableModel where Tag == NapaxiMcpServerActionResultTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(name: String, toolsLoaded: [String] = [], message: String? = nil, error: String? = nil) {
        var raw: [String: NapaxiJSONValue] = [
            "name": .string(name),
            "tools_loaded": .array(toolsLoaded.map { .string($0) }),
        ]
        if let message { raw["message"] = .string(message) }
        if let error { raw["error"] = .string(error) }
        self.init(raw: raw)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self.fromMap(json)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        let object = try mcpObjectMap(from: jsonString)
        try validateMcpServerActionResultObject(object)
        return Self(raw: object)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var name: String { string("name") ?? "" }
    var toolsLoaded: [String] { raw.stringArray("tools_loaded") ?? raw.stringArray("toolsLoaded") ?? [] }
    var message: String? { string("message") }
    var error: String? {
        guard let value = string("error"), !value.isEmpty else { return nil }
        return value
    }
    var isSuccess: Bool { error == nil }
}

public extension NapaxiStableModel where Tag == NapaxiMcpOAuthStartResultTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(
        name: String,
        authorizationUrl: String,
        state: String,
        redirectUri: String,
        error: String? = nil
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "name": .string(name),
            "authorization_url": .string(authorizationUrl),
            "state": .string(state),
            "redirect_uri": .string(redirectUri),
        ]
        if let error { raw["error"] = .string(error) }
        self.init(raw: raw)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self.fromMap(json)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        let object = try mcpObjectMap(from: jsonString)
        try validateMcpOAuthStartResultObject(object)
        return Self(raw: object)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var name: String { string("name") ?? "" }
    var authorizationUrl: String { string("authorization_url") ?? string("authorizationUrl") ?? "" }
    var state: String { string("state") ?? "" }
    var redirectUri: String { string("redirect_uri") ?? string("redirectUri") ?? "" }
    var error: String? {
        guard let value = string("error"), !value.isEmpty else { return nil }
        return value
    }
    var isSuccess: Bool { error == nil }
}

private func mcpObjectMap(from jsonString: String) throws -> [String: NapaxiJSONValue] {
    let value = try NapaxiRawJSON(jsonString: jsonString).value
    guard case .object(let object) = value else {
        throw NapaxiError.invalidJSON("MCP JSON must be an object")
    }
    return object
}

func validateMcpServerInfoObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateMcpOptionalString("name")
    try object.validateMcpOptionalString("url")
    try object.validateMcpOptionalBool("connected")
    try object.validateMcpOptionalStringArray("tools")
    try object.validateMcpOptionalString("error")
    try object.validateMcpOptionalBool("authRequired")
    try object.validateMcpOptionalBool("auth_required")
    try object.validateMcpOptionalBool("oauthConnected")
    try object.validateMcpOptionalBool("oauth_connected")
    try object.validateMcpOptionalBool("oauthPending")
    try object.validateMcpOptionalBool("oauth_pending")
    try object.validateMcpOptionalString("transport")
}

func validateMcpToolInfoObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateMcpOptionalString("name")
    try object.validateMcpOptionalString("serverName")
    try object.validateMcpOptionalString("server_name")
}

func validateMcpServerActionResultObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateMcpOptionalString("name")
    try object.validateMcpOptionalStringArray("tools_loaded")
    try object.validateMcpOptionalStringArray("toolsLoaded")
    try object.validateMcpOptionalString("message")
    try object.validateMcpOptionalString("error")
}

func validateMcpOAuthStartResultObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateMcpOptionalString("name")
    try object.validateMcpOptionalString("authorization_url")
    try object.validateMcpOptionalString("authorizationUrl")
    try object.validateMcpOptionalString("state")
    try object.validateMcpOptionalString("redirect_uri")
    try object.validateMcpOptionalString("redirectUri")
    try object.validateMcpOptionalString("error")
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func stringArray(_ key: String) -> [String]? {
        guard case .array(let values)? = self[key] else { return nil }
        return values.compactMap(\.stringValue)
    }

    func validateMcpOptionalString(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("Expected MCP field '\(key)' to be a string")
        }
    }

    func validateMcpOptionalBool(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .bool = value else {
            throw NapaxiError.invalidJSON("Expected MCP field '\(key)' to be a bool")
        }
    }

    func validateMcpOptionalStringArray(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("Expected MCP field '\(key)' to be an array")
        }
        for item in values {
            guard case .string = item else {
                throw NapaxiError.invalidJSON("Expected MCP field '\(key)' to contain strings")
            }
        }
    }
}
