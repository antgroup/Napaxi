import Foundation

public extension NapaxiStableString where Tag == NapaxiGroupMessageTypeTag {
    static let text = Self(rawValue: "text")
    static let toolCall = Self(rawValue: "tool_call")
    static let toolResult = Self(rawValue: "tool_result")
    static let system = Self(rawValue: "system")

    static func fromString(_ value: String) -> Self {
        switch value {
        case "tool_call":
            return .toolCall
        case "tool_result":
            return .toolResult
        case "system":
            return .system
        default:
            return .text
        }
    }
}

public extension NapaxiStableModel where Tag == NapaxiGroupInfoTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(
        id: String,
        name: String,
        members: [String],
        coordinator: String = "napaxi",
        createdAt: String = "",
        messageCount: Int = 0,
        lastMessagePreview: String? = nil,
        lastMessageTime: String? = nil,
        customPrompt: String? = nil
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "id": .string(id),
            "name": .string(name),
            "members": .array(members.map { .string($0) }),
            "coordinator": .string(coordinator),
            "created_at": .string(createdAt),
            "message_count": .number(Double(messageCount)),
        ]
        if let lastMessagePreview { raw["last_message_preview"] = .string(lastMessagePreview) }
        if let lastMessageTime { raw["last_message_time"] = .string(lastMessageTime) }
        if let customPrompt { raw["custom_prompt"] = .string(customPrompt) }
        self.init(raw: raw)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        let object = try groupObjectMap(from: jsonString)
        try validateGroupInfoObject(object)
        return Self(raw: object)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var id: String { string("id") ?? "" }
    var name: String { string("name") ?? "" }
    var members: [String] { raw.stringArray("members") ?? [] }
    var coordinator: String { string("coordinator") ?? "napaxi" }
    var createdAt: String { string("created_at") ?? string("createdAt") ?? "" }
    var messageCount: Int { raw.int("message_count") ?? raw.int("messageCount") ?? 0 }
    var lastMessagePreview: String? { string("last_message_preview") ?? string("lastMessagePreview") }
    var lastMessageTime: String? { string("last_message_time") ?? string("lastMessageTime") }
    var customPrompt: String? { string("custom_prompt") ?? string("customPrompt") }
}

public extension NapaxiStableModel where Tag == NapaxiGroupMessageTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(
        id: String,
        groupId: String,
        sender: String,
        content: String,
        messageType: NapaxiGroupMessageType = .text,
        timestamp: String = "",
        toolCallId: String? = nil,
        toolName: String? = nil,
        targetAgent: String? = nil
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "id": .string(id),
            "group_id": .string(groupId),
            "sender": .string(sender),
            "content": .string(content),
            "type": .string(messageType.rawValue),
            "timestamp": .string(timestamp),
        ]
        if let toolCallId { raw["tool_call_id"] = .string(toolCallId) }
        if let toolName { raw["tool_name"] = .string(toolName) }
        if let targetAgent { raw["target_agent"] = .string(targetAgent) }
        self.init(raw: raw)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        let object = try groupObjectMap(from: jsonString)
        try validateGroupMessageObject(object)
        return Self(raw: object)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var id: String { string("id") ?? "" }
    var groupId: String { string("group_id") ?? string("groupId") ?? "" }
    var sender: String { string("sender") ?? "" }
    var content: String { string("content") ?? "" }
    var messageType: NapaxiGroupMessageType {
        NapaxiGroupMessageType.fromString(string("type") ?? string("message_type") ?? string("messageType") ?? "text")
    }
    var timestamp: String { string("timestamp") ?? "" }
    var toolCallId: String? { string("tool_call_id") ?? string("toolCallId") }
    var toolName: String? { string("tool_name") ?? string("toolName") }
    var targetAgent: String? { string("target_agent") ?? string("targetAgent") }
    var isUser: Bool { sender == "user" }
    var isSystem: Bool { sender == "system" }
    var isDelegation: Bool { targetAgent != nil }
}

func validateGroupInfoObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateGroupOptionalString("id")
    try object.validateGroupOptionalString("name")
    try object.validateGroupOptionalStringArray("members")
    try object.validateGroupOptionalString("coordinator")
    try object.validateGroupOptionalString("created_at")
    try object.validateGroupOptionalInt("message_count")
    try object.validateGroupOptionalString("last_message_preview")
    try object.validateGroupOptionalString("last_message_time")
    try object.validateGroupOptionalString("custom_prompt")
}

func validateGroupMessageObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateGroupOptionalString("id")
    try object.validateGroupOptionalString("group_id")
    try object.validateGroupOptionalString("sender")
    try object.validateGroupOptionalString("content")
    try object.validateGroupOptionalString("type")
    try object.validateGroupOptionalString("timestamp")
    try object.validateGroupOptionalString("tool_call_id")
    try object.validateGroupOptionalString("tool_name")
    try object.validateGroupOptionalString("target_agent")
}

private func groupObjectMap(from jsonString: String) throws -> [String: NapaxiJSONValue] {
    let value = try NapaxiRawJSON(jsonString: jsonString).value
    guard case .object(let object) = value else {
        throw NapaxiError.invalidJSON("Group JSON must be an object")
    }
    return object
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func stringArray(_ key: String) -> [String]? {
        guard case .array(let values)? = self[key] else { return nil }
        return values.compactMap(\.stringValue)
    }

    func int(_ key: String) -> Int? {
        guard case .number(let value)? = self[key], value.isFinite else { return nil }
        let integer = value.rounded(.towardZero)
        guard integer == value else { return nil }
        return Int(integer)
    }

    func validateGroupOptionalString(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("Expected group field '\(key)' to be a string")
        }
    }

    func validateGroupOptionalStringArray(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("Expected group field '\(key)' to be an array")
        }
        for item in values {
            guard case .string = item else {
                throw NapaxiError.invalidJSON("Expected group field '\(key)' to contain strings")
            }
        }
    }

    func validateGroupOptionalInt(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .number(let number) = value,
              number.isFinite,
              number.rounded(.towardZero) == number
        else {
            throw NapaxiError.invalidJSON("Expected group field '\(key)' to be an integer")
        }
    }
}
