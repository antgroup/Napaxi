import Foundation

public extension NapaxiStableString where Tag == NapaxiToolFilterTag {
    static let all = Self(rawValue: "all")
    static let allowlist = Self(rawValue: "allowlist")
    static let denylist = Self(rawValue: "denylist")
}

public extension NapaxiStableModel where Tag == NapaxiAgentHandleTag {
    init(agentId: String) {
        self.init(raw: ["agent_id": .string(agentId)])
    }

    var agentId: String { string("agent_id") ?? string("agentId") ?? "" }
}

public extension NapaxiStableModel where Tag == NapaxiAgentDefinitionTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(
        id: String,
        name: String,
        description: String = "",
        systemPrompt: String = "",
        provider: String? = nil,
        model: String? = nil,
        modelProfileId: String? = nil,
        engineId: String = "napaxi_core",
        engineProfileId: String = "",
        engineConfig: [String: NapaxiJSONValue] = [:],
        toolFilter: NapaxiToolFilter = .all,
        toolList: [String]? = nil,
        icon: String? = nil
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "id": .string(id),
            "name": .string(name),
            "description": .string(description),
            "system_prompt": .string(systemPrompt),
            "tool_filter": .object([
                "type": .string(toolFilter.coreType),
            ]),
        ]
        raw.setIfPresent("provider", provider)
        raw.setIfPresent("model", model)
        raw.setIfPresent("model_profile_id", modelProfileId)
        raw["engine_id"] = .string(engineId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "napaxi_core" : engineId)
        raw.setNonEmpty("engine_profile_id", engineProfileId)
        if !engineConfig.isEmpty {
            raw["engine_config"] = .object(engineConfig)
        }
        raw.setIfPresent("icon", icon)
        if let toolList {
            raw["tool_filter"] = .object([
                "type": .string(toolFilter.coreType),
                "tools": .array(toolList.map { .string($0) }),
            ])
        }
        self.init(raw: raw)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        let filterObject = map.object("tool_filter") ?? map.object("toolFilter")
        let filterType = filterObject?["type"]?.stringValue ?? "AllTools"
        let filter: NapaxiToolFilter
        switch filterType {
        case "Allowlist", "allowlist":
            filter = .allowlist
        case "Denylist", "denylist":
            filter = .denylist
        default:
            filter = .all
        }

        return Self(
            id: map.string("id") ?? "",
            name: map.string("name") ?? "",
            description: map.string("description") ?? "",
            systemPrompt: map.string("system_prompt") ?? map.string("systemPrompt") ?? "",
            provider: map.string("provider"),
            model: map.string("model"),
            modelProfileId: map.string("model_profile_id") ?? map.string("modelProfileId"),
            engineId: map.string("engine_id") ?? map.string("engineId") ?? "napaxi_core",
            engineProfileId: map.string("engine_profile_id") ?? map.string("engineProfileId") ?? "",
            engineConfig: map.object("engine_config") ?? map.object("engineConfig") ?? [:],
            toolFilter: filter,
            toolList: filterObject?.stringArray("tools"),
            icon: map.string("icon")
        )
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        let object = try agentObjectMap(from: jsonString)
        try validateAgentDefinitionObject(object)
        return Self.fromMap(object)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        var map: [String: NapaxiJSONValue] = [
            "id": .string(id),
            "name": .string(name),
            "description": .string(description),
            "system_prompt": .string(systemPrompt),
            "tool_filter": .object([
                "type": .string(toolFilter.coreType),
            ]),
        ]
        map.setNonEmpty("provider", provider)
        map.setNonEmpty("model", model)
        map.setNonEmpty("model_profile_id", modelProfileId)
        map["engine_id"] = .string(engineId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "napaxi_core" : engineId)
        map.setNonEmpty("engine_profile_id", engineProfileId)
        if !engineConfig.isEmpty {
            map["engine_config"] = .object(engineConfig)
        }
        if let toolList {
            map["tool_filter"] = .object([
                "type": .string(toolFilter.coreType),
                "tools": .array(toolList.map { .string($0) }),
            ])
        }
        map.setNonEmpty("icon", icon)
        return map
    }

    func toJson() throws -> String {
        try toMap().jsonString()
    }

    var id: String { string("id") ?? "" }
    var name: String { string("name") ?? "" }
    var description: String { string("description") ?? "" }
    var systemPrompt: String { string("system_prompt") ?? string("systemPrompt") ?? "" }
    var provider: String? { string("provider") }
    var model: String? { string("model") }
    var modelProfileId: String? { string("model_profile_id") ?? string("modelProfileId") }
    var engineId: String { string("engine_id") ?? string("engineId") ?? "napaxi_core" }
    var engineProfileId: String { string("engine_profile_id") ?? string("engineProfileId") ?? "" }
    var engineConfig: [String: NapaxiJSONValue] {
        raw.object("engine_config") ?? raw.object("engineConfig") ?? [:]
    }
    var toolFilter: NapaxiToolFilter {
        let type = raw.object("tool_filter")?["type"]?.stringValue
            ?? raw.object("toolFilter")?["type"]?.stringValue
            ?? "AllTools"
        switch type {
        case "Allowlist", "allowlist":
            return .allowlist
        case "Denylist", "denylist":
            return .denylist
        default:
            return .all
        }
    }
    var toolList: [String]? {
        raw.object("tool_filter")?.stringArray("tools") ?? raw.object("toolFilter")?.stringArray("tools")
    }
    var icon: String? { string("icon") }
}

func validateAgentDefinitionObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateAgentDefinitionOptionalString("id")
    try object.validateAgentDefinitionOptionalString("name")
    try object.validateAgentDefinitionOptionalString("description")
    try object.validateAgentDefinitionOptionalString("system_prompt")
    try object.validateAgentDefinitionOptionalString("provider")
    try object.validateAgentDefinitionOptionalString("model")
    try object.validateAgentDefinitionOptionalString("model_profile_id")
    try object.validateAgentDefinitionOptionalString("engine_id")
    try object.validateAgentDefinitionOptionalString("engine_profile_id")
    try object.validateAgentDefinitionOptionalObject("engine_config")
    try object.validateAgentDefinitionOptionalString("icon")
    try object.validateAgentDefinitionToolFilter("tool_filter")
}

public extension NapaxiStableModel where Tag == NapaxiToolInfoTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(name: String, description: String = "") {
        self.init(raw: [
            "name": .string(name),
            "description": .string(description),
        ])
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            name: map.string("name") ?? "",
            description: map.string("description") ?? ""
        )
    }

    var name: String { string("name") ?? "" }
    var description: String { string("description") ?? "" }
}

func validateToolInfoObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateAgentDefinitionOptionalString("name")
    try object.validateAgentDefinitionOptionalString("description")
}

private extension NapaxiStableString where Tag == NapaxiToolFilterTag {
    var coreType: String {
        switch rawValue {
        case "allowlist":
            return "Allowlist"
        case "denylist":
            return "Denylist"
        default:
            return "AllTools"
        }
    }
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    mutating func setNonEmpty(_ key: String, _ value: String?) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        self[key] = .string(value)
    }

    mutating func setIfPresent(_ key: String, _ value: String?) {
        guard let value else { return }
        self[key] = .string(value)
    }

    func object(_ key: String) -> [String: NapaxiJSONValue]? {
        guard case .object(let object)? = self[key] else { return nil }
        return object
    }

    func stringArray(_ key: String) -> [String]? {
        guard case .array(let values)? = self[key] else { return nil }
        return values.compactMap(\.stringValue)
    }

    func validateAgentDefinitionOptionalString(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("Expected agent definition field '\(key)' to be a string")
        }
    }

    func validateAgentDefinitionOptionalObject(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected agent definition field '\(key)' to be an object")
        }
    }

    func validateAgentDefinitionToolFilter(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .object(let filter) = value else {
            throw NapaxiError.invalidJSON("Expected agent definition field '\(key)' to be an object")
        }
        try filter.validateAgentDefinitionOptionalString("type")
        guard let tools = filter["tools"], tools != .null else { return }
        guard case .array(let values) = tools else {
            throw NapaxiError.invalidJSON("Expected agent definition field '\(key).tools' to be an array")
        }
        for item in values {
            guard case .string = item else {
                throw NapaxiError.invalidJSON("Expected agent definition field '\(key).tools' to contain strings")
            }
        }
    }
}

private func agentObjectMap(from jsonString: String) throws -> [String: NapaxiJSONValue] {
    let value = try NapaxiRawJSON(jsonString: jsonString).value
    guard case .object(let object) = value else {
        throw NapaxiError.invalidJSON("Agent JSON must be an object")
    }
    return object
}
