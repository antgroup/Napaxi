import Foundation

public enum NapaxiError: Error, Equatable, Sendable, LocalizedError {
    case unavailable(String)
    case nativeError(code: String, message: String)
    case invalidJSON(String)
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message), .invalidJSON(let message), .invalidState(let message):
            return message
        case .nativeError(let code, let message):
            return "\(code): \(message)"
        }
    }
}

public let defaultMaxTokens = NapaxiConfig.defaultMaxTokens
public typealias LlmConfig = NapaxiConfig
public typealias LlmCapabilityConfig = NapaxiLlmCapabilityConfig
public typealias ScenePromptConfig = NapaxiScenePromptConfig
public typealias ContextEngineConfig = NapaxiContextEngineConfig
public typealias ShellSecurityConfig = NapaxiShellSecurityConfig
public typealias ShellApprovalMode = NapaxiShellApprovalMode

private let defaultLlmSystemPromptEN = "You are a helpful assistant."
private let defaultLlmSystemPromptZH = "你是一个有帮助的 AI 助手。"

public struct NapaxiConfig: Codable, Equatable, Sendable {
    public static let defaultMaxTokens = 40_960

    public var provider: String
    public var apiKey: String
    public var model: String
    public var baseUrl: String?
    public var systemPrompt: String
    public var responseLanguage: String
    public var maxTokens: Int
    public var maxToolIterations: Int
    public var extraHeaders: String?
    public var userTimezone: String?
    public var allowedModels: [[String: String]]?
    public var imageModel: String?
    public var imageAnalysisModel: String?
    public var imageBase64UrlFormat: String?
    public var videoModel: String?
    public var audioModel: String?
    public var capabilityConfigs: [String: NapaxiLlmCapabilityConfig]?
    public var scenePromptConfig: NapaxiScenePromptConfig?
    public var contextEngine: NapaxiContextEngineConfig
    public var shellSecurity: NapaxiShellSecurityConfig
    public var extra: [String: NapaxiJSONValue]

    public init(
        provider: String,
        apiKey: String,
        model: String,
        baseUrl: String? = nil,
        systemPrompt: String = "You are a helpful assistant.",
        responseLanguage: String = "en",
        maxTokens: Int = NapaxiConfig.defaultMaxTokens,
        maxToolIterations: Int = 50,
        extraHeaders: String? = nil,
        userTimezone: String? = nil,
        allowedModels: [[String: String]]? = nil,
        imageModel: String? = nil,
        imageAnalysisModel: String? = nil,
        imageBase64UrlFormat: String? = nil,
        videoModel: String? = nil,
        audioModel: String? = nil,
        capabilityConfigs: [String: NapaxiLlmCapabilityConfig]? = nil,
        scenePromptConfig: NapaxiScenePromptConfig? = nil,
        contextEngine: NapaxiContextEngineConfig = NapaxiContextEngineConfig(),
        shellSecurity: NapaxiShellSecurityConfig = NapaxiShellSecurityConfig(),
        extra: [String: NapaxiJSONValue] = [:]
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.baseUrl = baseUrl
        self.systemPrompt = systemPrompt
        self.responseLanguage = responseLanguage
        self.maxTokens = maxTokens
        self.maxToolIterations = maxToolIterations
        self.extraHeaders = extraHeaders
        self.userTimezone = userTimezone
        self.allowedModels = allowedModels
        self.imageModel = imageModel
        self.imageAnalysisModel = imageAnalysisModel
        self.imageBase64UrlFormat = imageBase64UrlFormat
        self.videoModel = videoModel
        self.audioModel = audioModel
        self.capabilityConfigs = capabilityConfigs
        self.scenePromptConfig = scenePromptConfig
        self.contextEngine = contextEngine
        self.shellSecurity = shellSecurity
        self.extra = extra
    }

    public init(jsonString: String) throws {
        let raw = try NapaxiRawJSON(jsonString: jsonString).value
        guard case .object(let object) = raw else {
            throw NapaxiError.invalidJSON("NapaxiConfig JSON must be an object")
        }
        try Self.validateFlutterJsonObject(object)
        self.init(jsonObject: object)
    }

    public static func fromJson(_ jsonString: String) throws -> Self {
        try Self(jsonString: jsonString)
    }

    public init(jsonObject object: [String: NapaxiJSONValue]) {
        var extra = object
        func takeString(_ key: String) -> String? {
            let value = extra[key]?.stringValue
            extra.removeValue(forKey: key)
            return value
        }
        func takeInt(_ key: String) -> Int? {
            let value: Int?
            if case .number(let number)? = extra[key], number.isFinite {
                let integer = number.rounded(.towardZero)
                value = integer == number ? Int(integer) : nil
            } else {
                value = nil
            }
            extra.removeValue(forKey: key)
            return value
        }
        func takeObject(_ key: String) -> [String: NapaxiJSONValue]? {
            let value = extra[key]?.objectValue
            extra.removeValue(forKey: key)
            return value
        }
        func takeStringMapArray(_ key: String) -> [[String: String]]? {
            guard case .array(let values)? = extra[key] else {
                extra.removeValue(forKey: key)
                return nil
            }
            extra.removeValue(forKey: key)
            return values.compactMap { value in
                guard case .object(let object) = value else { return nil }
                return object.mapValues { $0.stringValue ?? "" }
            }
        }

        let provider = takeString("provider") ?? "anthropic"
        let apiKey = takeString("api_key") ?? ""
        let baseUrl = takeString("base_url")
        let model = takeString("model") ?? ""
        let responseLanguage = takeString("response_language") ?? "en"
        let systemPrompt = takeString("system_prompt")
            ?? (Self.normalizedResponseLanguage(responseLanguage) == "zh" ? defaultLlmSystemPromptZH : "")
        let maxTokens = takeInt("max_tokens") ?? Self.defaultMaxTokens
        let maxToolIterations = takeInt("max_tool_iterations") ?? 50
        let extraHeaders = takeString("extra_headers")
        let userTimezone = takeString("user_timezone") ?? takeString("userTimeZone") ?? takeString("timeZoneId")
        let allowedModels = takeStringMapArray("allowed_models")
        let imageModel = takeString("image_model")
        let imageAnalysisModel = takeString("image_analysis_model")
        let imageBase64UrlFormat = takeString("image_base64_url_format")
        let videoModel = takeString("video_model")
        let audioModel = takeString("audio_model")
        let capabilityConfigs = takeObject("capability_configs")?.compactMapValues { value -> NapaxiLlmCapabilityConfig? in
            guard case .object(let object) = value else { return nil }
            return NapaxiLlmCapabilityConfig(raw: object)
        }
        let scenePromptConfig = takeObject("scene_prompt_config").map(NapaxiScenePromptConfig.init(raw:))
        let contextEngine = takeObject("context_engine").map(NapaxiContextEngineConfig.init(raw:)) ?? NapaxiContextEngineConfig()
        let shellSecurity = takeObject("shell_security").map(NapaxiShellSecurityConfig.init(raw:)) ?? NapaxiShellSecurityConfig()

        self.init(
            provider: provider,
            apiKey: apiKey,
            model: model,
            baseUrl: baseUrl,
            systemPrompt: systemPrompt,
            responseLanguage: responseLanguage,
            maxTokens: maxTokens,
            maxToolIterations: maxToolIterations,
            extraHeaders: extraHeaders,
            userTimezone: userTimezone,
            allowedModels: allowedModels,
            imageModel: imageModel,
            imageAnalysisModel: imageAnalysisModel,
            imageBase64UrlFormat: imageBase64UrlFormat,
            videoModel: videoModel,
            audioModel: audioModel,
            capabilityConfigs: capabilityConfigs,
            scenePromptConfig: scenePromptConfig,
            contextEngine: contextEngine,
            shellSecurity: shellSecurity,
            extra: extra
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: NapaxiJSONValue].self)
        try Self.validateFlutterJsonObject(object)
        self.init(jsonObject: object)
    }

    public func encode(to encoder: Encoder) throws {
        let value = try NapaxiRawJSON(jsonString: jsonString()).value
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public func jsonString() throws -> String {
        var object = extra
        object["provider"] = .string(provider)
        object["api_key"] = .string(apiKey)
        object["model"] = .string(model)
        object["base_url"] = baseUrl.map(NapaxiJSONValue.string) ?? .null
        object["system_prompt"] = .string(Self.effectiveSystemPrompt(systemPrompt, responseLanguage: responseLanguage))
        object["response_language"] = .string(responseLanguage)
        object["max_tokens"] = .number(Double(maxTokens))
        object["max_tool_iterations"] = .number(Double(maxToolIterations))
        object["extra_headers"] = extraHeaders.map(NapaxiJSONValue.string) ?? .null
        if let userTimezone, !userTimezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object["user_timezone"] = .string(userTimezone)
        }
        if let allowedModels {
            object["allowed_models"] = .array(allowedModels.map { .object($0.mapValues { .string($0) }) })
        }
        if let imageModel {
            object["image_model"] = .string(imageModel)
        }
        if let imageAnalysisModel {
            object["image_analysis_model"] = .string(imageAnalysisModel)
        }
        if let imageBase64UrlFormat {
            object["image_base64_url_format"] = .string(imageBase64UrlFormat)
        }
        if let videoModel {
            object["video_model"] = .string(videoModel)
        }
        if let audioModel {
            object["audio_model"] = .string(audioModel)
        }
        if let capabilityConfigs {
            object["capability_configs"] = .object(capabilityConfigs.mapValues { .object($0.toMap()) })
        }
        if let scenePromptConfig {
            object["scene_prompt_config"] = .object(scenePromptConfig.toMap())
        }
        object["context_engine"] = .object(contextEngine.toMap())
        object["shell_security"] = .object(shellSecurity.toMap())
        return try object.jsonString()
    }

    public func toJson() throws -> String {
        try jsonString()
    }

    private static func effectiveSystemPrompt(_ systemPrompt: String, responseLanguage: String) -> String {
        if systemPrompt == defaultLlmSystemPromptEN, normalizedResponseLanguage(responseLanguage) == "zh" {
            return defaultLlmSystemPromptZH
        }
        return systemPrompt
    }

    private static func defaultSystemPrompt(responseLanguage: String) -> String {
        normalizedResponseLanguage(responseLanguage) == "zh" ? defaultLlmSystemPromptZH : defaultLlmSystemPromptEN
    }

    private static func normalizedResponseLanguage(_ responseLanguage: String) -> String {
        switch responseLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "zh", "zh-cn", "chinese":
            return "zh"
        default:
            return "en"
        }
    }

    private static func validateFlutterJsonObject(_ object: [String: NapaxiJSONValue]) throws {
        try validateOptionalString(object["response_language"], field: "response_language")
        if let allowedModels = object["allowed_models"], allowedModels != .null {
            guard case .array(let values) = allowedModels else {
                throw NapaxiError.invalidJSON("allowed_models must be a JSON array")
            }
            for item in values {
                guard case .object(let model) = item else {
                    throw NapaxiError.invalidJSON("allowed_models entries must be JSON objects")
                }
                for value in model.values where value.stringValue == nil {
                    throw NapaxiError.invalidJSON("allowed_models values must be strings")
                }
            }
        }
        if let capabilityConfigs = object["capability_configs"], capabilityConfigs != .null {
            guard case .object(let configs) = capabilityConfigs else {
                throw NapaxiError.invalidJSON("capability_configs must be a JSON object")
            }
            for value in configs.values {
                guard case .object(let config) = value else {
                    throw NapaxiError.invalidJSON("capability_configs values must be JSON objects")
                }
                try validateFlutterCapabilityConfig(config)
            }
        }
        if let scenePromptConfig = object["scene_prompt_config"],
           case .object(let config) = scenePromptConfig {
            try validateFlutterScenePromptConfig(config)
        }
        if let contextEngine = object["context_engine"],
           case .object(let config) = contextEngine {
            try validateFlutterContextEngineConfig(config)
        }
        if let shellSecurity = object["shell_security"],
           case .object(let config) = shellSecurity {
            try validateFlutterShellSecurityConfig(config)
        }
    }

    private static func validateFlutterCapabilityConfig(_ config: [String: NapaxiJSONValue]) throws {
        try validateOptionalString(config["provider"], field: "capability_configs.provider")
        try validateOptionalString(config["api_key"], field: "capability_configs.api_key")
        try validateOptionalString(config["base_url"], field: "capability_configs.base_url")
        try validateOptionalString(config["model"], field: "capability_configs.model")
        try validateOptionalInt(config["max_tokens"], field: "capability_configs.max_tokens")
        try validateOptionalString(config["extra_headers"], field: "capability_configs.extra_headers")
        try validateOptionalString(config["image_base64_url_format"], field: "capability_configs.image_base64_url_format")
    }

    private static func validateFlutterScenePromptConfig(_ config: [String: NapaxiJSONValue]) throws {
        try validateOptionalBool(config["enabled"], field: "scene_prompt_config.enabled")
        if let hostPolicies = config["host_policies"], hostPolicies != .null {
            guard case .object = hostPolicies else {
                throw NapaxiError.invalidJSON("scene_prompt_config.host_policies must be a JSON object")
            }
        }
    }

    private static func validateFlutterContextEngineConfig(_ config: [String: NapaxiJSONValue]) throws {
        try validateOptionalBool(config["enabled"], field: "context_engine.enabled")
        try validateOptionalString(config["engine"], field: "context_engine.engine")
        try validateOptionalNumber(config["trigger_ratio"], field: "context_engine.trigger_ratio")
        try validateOptionalNumber(config["target_ratio"], field: "context_engine.target_ratio")
        try validateOptionalInt(config["protect_head_messages"], field: "context_engine.protect_head_messages")
        try validateOptionalInt(config["protect_tail_messages"], field: "context_engine.protect_tail_messages")
        try validateOptionalInt(config["context_window_tokens"], field: "context_engine.context_window_tokens")
        try validateOptionalInt(config["native_context_window_tokens"], field: "context_engine.native_context_window_tokens")
        try validateOptionalInt(config["provider_context_window_tokens"], field: "context_engine.provider_context_window_tokens")
        try validateOptionalInt(config["response_reserve_tokens"], field: "context_engine.response_reserve_tokens")
        try validateOptionalString(config["compaction_strategy"], field: "context_engine.compaction_strategy")
        try validateOptionalString(config["compaction_model"], field: "context_engine.compaction_model")
        try validateOptionalInt(config["compaction_timeout_ms"], field: "context_engine.compaction_timeout_ms")
        try validateOptionalBool(config["pre_compaction_memory_flush"], field: "context_engine.pre_compaction_memory_flush")
    }

    private static func validateFlutterShellSecurityConfig(_ config: [String: NapaxiJSONValue]) throws {
        try validateOptionalString(config["approval_mode"], field: "shell_security.approval_mode")
    }

    private static func validateOptionalString(_ value: NapaxiJSONValue?, field: String) throws {
        guard let value, value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("\(field) must be a string")
        }
    }

    private static func validateOptionalBool(_ value: NapaxiJSONValue?, field: String) throws {
        guard let value, value != .null else { return }
        guard case .bool = value else {
            throw NapaxiError.invalidJSON("\(field) must be a bool")
        }
    }

    private static func validateOptionalNumber(_ value: NapaxiJSONValue?, field: String) throws {
        guard let value, value != .null else { return }
        guard case .number(let number) = value, number.isFinite else {
            throw NapaxiError.invalidJSON("\(field) must be a number")
        }
    }

    private static func validateOptionalInt(_ value: NapaxiJSONValue?, field: String) throws {
        guard let value, value != .null else { return }
        guard case .number(let number) = value,
              number.isFinite,
              number.rounded(.towardZero) == number else {
            throw NapaxiError.invalidJSON("\(field) must be an integer")
        }
    }
}

public extension NapaxiStableModel where Tag == NapaxiScenePromptConfigTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(
        enabled: Bool = false,
        hostPolicies: [String: String]? = nil
    ) {
        var raw: [String: NapaxiJSONValue] = ["enabled": .bool(enabled)]
        if let hostPolicies {
            raw["host_policies"] = .object(hostPolicies.mapValues { .string($0) })
        }
        self.init(raw: raw)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            enabled: map["enabled"]?.boolValue ?? false,
            hostPolicies: map.configObject("host_policies")?.mapValues { $0.configStringValue }
        )
    }

    func toMap() -> [String: NapaxiJSONValue] {
        var map: [String: NapaxiJSONValue] = [
            "enabled": .bool(enabled),
        ]
        if let hostPolicies {
            map["host_policies"] = .object(hostPolicies.mapValues { .string($0) })
        }
        return map
    }

    var enabled: Bool { bool("enabled") ?? false }
    var hostPolicies: [String: String]? {
        raw.configObject("host_policies")?.mapValues { $0.configStringValue }
    }
}

public extension NapaxiStableModel where Tag == NapaxiContextEngineConfigTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(
        enabled: Bool = true,
        engine: String = "compressor",
        triggerRatio: Double = 0.85,
        targetRatio: Double = 0.45,
        protectHeadMessages: Int = 2,
        protectTailMessages: Int = 20,
        contextWindowTokens: Int? = nil,
        nativeContextWindowTokens: Int? = nil,
        providerContextWindowTokens: Int? = nil,
        responseReserveTokens: Int? = nil,
        compactionStrategy: String = "llm_summary",
        compactionModel: String? = nil,
        compactionTimeoutMs: Int = 60_000,
        preCompactionMemoryFlush: Bool = false
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "enabled": .bool(enabled),
            "engine": .string(engine),
            "trigger_ratio": .number(triggerRatio),
            "target_ratio": .number(targetRatio),
            "protect_head_messages": .number(Double(protectHeadMessages)),
            "protect_tail_messages": .number(Double(protectTailMessages)),
            "compaction_strategy": .string(compactionStrategy),
            "compaction_timeout_ms": .number(Double(compactionTimeoutMs)),
            "pre_compaction_memory_flush": .bool(preCompactionMemoryFlush),
        ]
        if let contextWindowTokens { raw["context_window_tokens"] = .number(Double(contextWindowTokens)) }
        if let nativeContextWindowTokens { raw["native_context_window_tokens"] = .number(Double(nativeContextWindowTokens)) }
        if let providerContextWindowTokens { raw["provider_context_window_tokens"] = .number(Double(providerContextWindowTokens)) }
        if let responseReserveTokens { raw["response_reserve_tokens"] = .number(Double(responseReserveTokens)) }
        raw.setConfigTrimmedNonEmptyString("compaction_model", compactionModel)
        self.init(raw: raw)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            enabled: map["enabled"]?.boolValue ?? true,
            engine: map["engine"]?.stringValue ?? "compressor",
            triggerRatio: map["trigger_ratio"]?.numberValue ?? map["triggerRatio"]?.numberValue ?? 0.85,
            targetRatio: map["target_ratio"]?.numberValue ?? map["targetRatio"]?.numberValue ?? 0.45,
            protectHeadMessages: map.configInt("protect_head_messages") ?? map.configInt("protectHeadMessages") ?? 2,
            protectTailMessages: map.configInt("protect_tail_messages") ?? map.configInt("protectTailMessages") ?? 20,
            contextWindowTokens: map.configInt("context_window_tokens") ?? map.configInt("contextWindowTokens"),
            nativeContextWindowTokens: map.configInt("native_context_window_tokens") ?? map.configInt("nativeContextWindowTokens"),
            providerContextWindowTokens: map.configInt("provider_context_window_tokens") ?? map.configInt("providerContextWindowTokens"),
            responseReserveTokens: map.configInt("response_reserve_tokens") ?? map.configInt("responseReserveTokens"),
            compactionStrategy: map["compaction_strategy"]?.stringValue ?? map["compactionStrategy"]?.stringValue ?? "llm_summary",
            compactionModel: map["compaction_model"]?.stringValue ?? map["compactionModel"]?.stringValue,
            compactionTimeoutMs: map.configInt("compaction_timeout_ms") ?? map.configInt("compactionTimeoutMs") ?? 60_000,
            preCompactionMemoryFlush: map["pre_compaction_memory_flush"]?.boolValue ?? map["preCompactionMemoryFlush"]?.boolValue ?? false
        )
    }

    func toMap() -> [String: NapaxiJSONValue] {
        var map: [String: NapaxiJSONValue] = [
            "enabled": .bool(enabled),
            "engine": .string(engine),
            "trigger_ratio": .number(triggerRatio),
            "target_ratio": .number(targetRatio),
            "protect_head_messages": .number(Double(protectHeadMessages)),
            "protect_tail_messages": .number(Double(protectTailMessages)),
            "compaction_strategy": .string(compactionStrategy),
            "compaction_timeout_ms": .number(Double(compactionTimeoutMs)),
            "pre_compaction_memory_flush": .bool(preCompactionMemoryFlush),
        ]
        if let contextWindowTokens {
            map["context_window_tokens"] = .number(Double(contextWindowTokens))
        }
        if let nativeContextWindowTokens {
            map["native_context_window_tokens"] = .number(Double(nativeContextWindowTokens))
        }
        if let providerContextWindowTokens {
            map["provider_context_window_tokens"] = .number(Double(providerContextWindowTokens))
        }
        if let responseReserveTokens {
            map["response_reserve_tokens"] = .number(Double(responseReserveTokens))
        }
        map.setConfigTrimmedNonEmptyString("compaction_model", compactionModel)
        return map
    }

    var enabled: Bool { bool("enabled") ?? true }
    var engine: String { string("engine") ?? "compressor" }
    var triggerRatio: Double { number("trigger_ratio") ?? number("triggerRatio") ?? 0.85 }
    var targetRatio: Double { number("target_ratio") ?? number("targetRatio") ?? 0.45 }
    var protectHeadMessages: Int { raw.configInt("protect_head_messages") ?? raw.configInt("protectHeadMessages") ?? 2 }
    var protectTailMessages: Int { raw.configInt("protect_tail_messages") ?? raw.configInt("protectTailMessages") ?? 20 }
    var contextWindowTokens: Int? { raw.configInt("context_window_tokens") ?? raw.configInt("contextWindowTokens") }
    var nativeContextWindowTokens: Int? { raw.configInt("native_context_window_tokens") ?? raw.configInt("nativeContextWindowTokens") }
    var providerContextWindowTokens: Int? { raw.configInt("provider_context_window_tokens") ?? raw.configInt("providerContextWindowTokens") }
    var responseReserveTokens: Int? { raw.configInt("response_reserve_tokens") ?? raw.configInt("responseReserveTokens") }
    var compactionStrategy: String { string("compaction_strategy") ?? string("compactionStrategy") ?? "llm_summary" }
    var compactionModel: String? { string("compaction_model") ?? string("compactionModel") }
    var compactionTimeoutMs: Int { raw.configInt("compaction_timeout_ms") ?? raw.configInt("compactionTimeoutMs") ?? 60_000 }
    var preCompactionMemoryFlush: Bool { bool("pre_compaction_memory_flush") ?? bool("preCompactionMemoryFlush") ?? false }
}

/// Shell command approval posture. Mirrors the Rust `ShellApprovalMode`.
public enum NapaxiShellApprovalMode: String, Sendable, CaseIterable {
    case readOnlyOnly = "read_only_only"
    case onRequest = "on_request"
    case trustedAllow = "trusted_allow"
    case custom = "custom"

    public static func fromWire(_ value: String?) -> NapaxiShellApprovalMode {
        NapaxiShellApprovalMode(rawValue: value ?? "") ?? .onRequest
    }
}

public extension NapaxiStableModel where Tag == NapaxiShellSecurityConfigTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(approvalMode: NapaxiShellApprovalMode) {
        self.init(raw: ["approval_mode": .string(approvalMode.rawValue)])
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(approvalMode: NapaxiShellApprovalMode.fromWire(map["approval_mode"]?.stringValue))
    }

    func toMap() -> [String: NapaxiJSONValue] {
        ["approval_mode": .string(approvalMode.rawValue)]
    }

    var approvalMode: NapaxiShellApprovalMode {
        NapaxiShellApprovalMode.fromWire(string("approval_mode"))
    }
}

public extension NapaxiStableModel where Tag == NapaxiLlmCapabilityConfigTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    init(
        provider: String,
        apiKey: String,
        model: String,
        baseUrl: String? = nil,
        maxTokens: Int? = nil,
        extraHeaders: String? = nil,
        imageBase64UrlFormat: String? = nil
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "provider": .string(provider),
            "api_key": .string(apiKey),
            "model": .string(model),
        ]
        raw.setConfigOptionalString("base_url", baseUrl)
        if let maxTokens { raw["max_tokens"] = .number(Double(maxTokens)) }
        if let extraHeaders { raw["extra_headers"] = .string(extraHeaders) }
        if let imageBase64UrlFormat { raw["image_base64_url_format"] = .string(imageBase64UrlFormat) }
        self.init(raw: raw)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            provider: map["provider"]?.stringValue ?? "",
            apiKey: map["api_key"]?.stringValue ?? map["apiKey"]?.stringValue ?? "",
            model: map["model"]?.stringValue ?? "",
            baseUrl: map["base_url"]?.stringValue ?? map["baseUrl"]?.stringValue,
            maxTokens: map.configInt("max_tokens") ?? map.configInt("maxTokens"),
            extraHeaders: map["extra_headers"]?.stringValue ?? map["extraHeaders"]?.stringValue,
            imageBase64UrlFormat: map["image_base64_url_format"]?.stringValue ?? map["imageBase64UrlFormat"]?.stringValue
        )
    }

    func toMap() -> [String: NapaxiJSONValue] {
        var map: [String: NapaxiJSONValue] = [
            "provider": .string(provider),
            "api_key": .string(apiKey),
            "base_url": baseUrl.map(NapaxiJSONValue.string) ?? .null,
            "model": .string(model),
        ]
        if let maxTokens {
            map["max_tokens"] = .number(Double(maxTokens))
        }
        if let extraHeaders {
            map["extra_headers"] = .string(extraHeaders)
        }
        if let imageBase64UrlFormat {
            map["image_base64_url_format"] = .string(imageBase64UrlFormat)
        }
        return map
    }

    var provider: String { string("provider") ?? "" }
    var apiKey: String { string("api_key") ?? string("apiKey") ?? "" }
    var baseUrl: String? { string("base_url") ?? string("baseUrl") }
    var model: String { string("model") ?? "" }
    var maxTokens: Int? { raw.configInt("max_tokens") ?? raw.configInt("maxTokens") }
    var extraHeaders: String? { string("extra_headers") ?? string("extraHeaders") }
    var imageBase64UrlFormat: String? { string("image_base64_url_format") ?? string("imageBase64UrlFormat") }
}

extension NapaxiJSONValue {
    var intValue: Int? {
        if let numberValue {
            return Int(numberValue)
        }
        if let stringValue {
            return Int(stringValue)
        }
        return nil
    }

    var configStringValue: String {
        jsonCodecDisplayString
    }
}

extension Dictionary where Key == String, Value == NapaxiJSONValue {
    mutating func setConfigOptionalString(_ key: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        self[key] = .string(value)
    }

    mutating func setConfigTrimmedNonEmptyString(_ key: String, _ value: String?) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        self[key] = .string(value)
    }

    func configObject(_ key: String) -> [String: NapaxiJSONValue]? {
        if case .object(let object)? = self[key] {
            return object
        }
        return nil
    }

    func configInt(_ key: String) -> Int? {
        guard case .number(let value)? = self[key], value.isFinite else { return nil }
        let integer = value.rounded(.towardZero)
        guard integer == value else { return nil }
        return Int(integer)
    }
}

public struct NapaxiCapabilityProfile: Codable, Equatable, Sendable {
    public var platform: String?
    public var supportedCapabilities: [String]
    public var disabledCapabilities: [String]

    public init(
        platform: String? = nil,
        supportedCapabilities: [String] = [],
        disabledCapabilities: [String] = []
    ) {
        self.platform = platform
        self.supportedCapabilities = supportedCapabilities
        self.disabledCapabilities = disabledCapabilities
    }

    enum CodingKeys: String, CodingKey {
        case platform
        case supportedCapabilities = "supported_capabilities"
        case disabledCapabilities = "disabled_capabilities"
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toJson())
    }

    public func jsonString() throws -> String {
        try NapaxiRawJSON(jsonValue()).jsonString()
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "supported_capabilities": .array(supportedCapabilities.map { .string($0) }),
            "disabled_capabilities": .array(disabledCapabilities.map { .string($0) }),
        ]
        if let platform {
            object["platform"] = .string(platform)
        }
        return object
    }

    public func toJsonString() throws -> String {
        try jsonString()
    }
}

public struct NapaxiCapabilitySelection: Codable, Equatable, Sendable {
    public var enabledCapabilities: [String]
    public var disabledCapabilities: [String]
    public var config: [String: NapaxiJSONValue]

    public init(
        enabledCapabilities: [String] = [],
        disabledCapabilities: [String] = [],
        config: [String: NapaxiJSONValue] = [:]
    ) {
        self.enabledCapabilities = enabledCapabilities
        self.disabledCapabilities = disabledCapabilities
        self.config = config
    }

    enum CodingKeys: String, CodingKey {
        case enabledCapabilities = "enabled_capabilities"
        case disabledCapabilities = "disabled_capabilities"
        case config
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toJson())
    }

    public func jsonString() throws -> String {
        try NapaxiRawJSON(jsonValue()).jsonString()
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "enabled_capabilities": .array(enabledCapabilities.map { .string($0) }),
            "disabled_capabilities": .array(disabledCapabilities.map { .string($0) }),
            "config": .object(config),
        ]
    }

    public func toJsonString() throws -> String {
        try jsonString()
    }
}

public struct NapaxiCapabilityDefinition: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var version: String
    public var platforms: [String]
    public var configSchema: [String: NapaxiJSONValue]
    public var risk: String
    public var requirements: [String]
    public var defaultEnabled: Bool
    public var activation: String

    public init(
        id: String,
        kind: String,
        version: String,
        platforms: [String],
        configSchema: [String: NapaxiJSONValue] = [:],
        risk: String,
        requirements: [String] = [],
        defaultEnabled: Bool,
        activation: String
    ) {
        self.id = id
        self.kind = kind
        self.version = version
        self.platforms = platforms
        self.configSchema = configSchema
        self.risk = risk
        self.requirements = requirements
        self.defaultEnabled = defaultEnabled
        self.activation = activation
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            id: json["id"]?.stringValue ?? "",
            kind: json["kind"]?.stringValue ?? "",
            version: json["version"]?.stringValue ?? "",
            platforms: json.capabilityStringArray("platforms"),
            configSchema: json["config_schema"]?.objectValue ?? [:],
            risk: json["risk"]?.stringValue ?? "",
            requirements: json.capabilityStringArray("requirements"),
            defaultEnabled: json["default_enabled"]?.boolValue ?? false,
            activation: json["activation"]?.stringValue ?? ""
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "id": .string(id),
            "kind": .string(kind),
            "version": .string(version),
            "platforms": .array(platforms.map { .string($0) }),
            "config_schema": .object(configSchema),
            "risk": .string(risk),
            "requirements": .array(requirements.map { .string($0) }),
            "default_enabled": .bool(defaultEnabled),
            "activation": .string(activation),
        ]
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toJson())
    }

    public func jsonString() throws -> String {
        try NapaxiRawJSON(jsonValue()).jsonString()
    }

    public func toJsonString() throws -> String {
        try jsonString()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case version
        case platforms
        case configSchema = "config_schema"
        case risk
        case requirements
        case defaultEnabled = "default_enabled"
        case activation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = Self(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
            kind: try container.decodeIfPresent(String.self, forKey: .kind) ?? "",
            version: try container.decodeIfPresent(String.self, forKey: .version) ?? "",
            platforms: try container.decodeFlutterStringArray(forKey: .platforms),
            configSchema: (try? container.decode([String: NapaxiJSONValue].self, forKey: .configSchema)) ?? [:],
            risk: try container.decodeIfPresent(String.self, forKey: .risk) ?? "",
            requirements: try container.decodeFlutterStringArray(forKey: .requirements),
            defaultEnabled: try container.decodeIfPresent(Bool.self, forKey: .defaultEnabled) ?? false,
            activation: try container.decodeIfPresent(String.self, forKey: .activation) ?? ""
        )
    }
}

public struct NapaxiCapabilityStatus: Codable, Equatable, Sendable {
    public var definition: NapaxiCapabilityDefinition
    public var registered: Bool
    public var available: Bool
    public var enabled: Bool
    public var unavailableReason: String?

    public init(
        definition: NapaxiCapabilityDefinition,
        registered: Bool,
        available: Bool,
        enabled: Bool,
        unavailableReason: String? = nil
    ) {
        self.definition = definition
        self.registered = registered
        self.available = available
        self.enabled = enabled
        self.unavailableReason = unavailableReason
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            definition: NapaxiCapabilityDefinition.fromJson(json["definition"]?.objectValue ?? [:]),
            registered: json["registered"]?.boolValue ?? false,
            available: json["available"]?.boolValue ?? false,
            enabled: json["enabled"]?.boolValue ?? false,
            unavailableReason: json["unavailable_reason"]?.stringValue
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "definition": .object(definition.toJson()),
            "registered": .bool(registered),
            "available": .bool(available),
            "enabled": .bool(enabled),
        ]
        if let unavailableReason {
            object["unavailable_reason"] = .string(unavailableReason)
        }
        return object
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toJson())
    }

    public func jsonString() throws -> String {
        try NapaxiRawJSON(jsonValue()).jsonString()
    }

    public func toJsonString() throws -> String {
        try jsonString()
    }

    enum CodingKeys: String, CodingKey {
        case definition
        case registered
        case available
        case enabled
        case unavailableReason = "unavailable_reason"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = Self(
            definition: try container.decodeIfPresent(NapaxiCapabilityDefinition.self, forKey: .definition)
                ?? NapaxiCapabilityDefinition(
                    id: "",
                    kind: "",
                    version: "",
                    platforms: [],
                    risk: "",
                    defaultEnabled: false,
                    activation: ""
                ),
            registered: try container.decodeIfPresent(Bool.self, forKey: .registered) ?? false,
            available: try container.decodeIfPresent(Bool.self, forKey: .available) ?? false,
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            unavailableReason: try container.decodeIfPresent(String.self, forKey: .unavailableReason)
        )
    }
}

public enum NapaxiChannelSurfaceKind {
    public static let im = "im"
    public static let device = "device"
    public static let app = "app"
    public static let system = "system"
    public static let custom = "custom"
}

public enum NapaxiChannelEndpointKind {
    public static let direct = "direct"
    public static let group = "group"
    public static let room = "room"
    public static let thread = "thread"
    public static let broadcast = "broadcast"
    public static let device = "device"
    public static let custom = "custom"
}

public enum NapaxiChannelModality {
    public static let text = "text"
    public static let audio = "audio"
    public static let image = "image"
    public static let file = "file"
    public static let control = "control"
    public static let sensor = "sensor"
    public static let presence = "presence"
}

public enum NapaxiChannelContentFormat {
    public static let plainText = "plain_text"
    public static let markdown = "markdown"
}

public enum NapaxiChannelCapability {
    public static let im = "napaxi.channel.im"
    public static let device = "napaxi.channel.device"
}

public struct NapaxiChannelRegistration: Codable, Equatable, Sendable {
    public var name: String
    public var type: String?
    public var accountId: String?
    public var surfaceKind: String?
    public var endpointKind: String?
    public var modalities: [String]
    public var contentFormats: [String]
    public var transport: String?
    public var config: [String: NapaxiJSONValue]

    public init(
        name: String,
        type: String? = nil,
        accountId: String? = nil,
        surfaceKind: String? = nil,
        endpointKind: String? = nil,
        modalities: [String] = [],
        contentFormats: [String] = [],
        transport: String? = nil,
        config: [String: NapaxiJSONValue] = [:]
    ) {
        self.name = name
        self.type = type
        self.accountId = accountId
        self.surfaceKind = surfaceKind
        self.endpointKind = endpointKind
        self.modalities = modalities
        self.contentFormats = contentFormats
        self.transport = transport
        self.config = config
    }

    public static func im(
        name: String,
        type: String,
        accountId: String? = nil,
        endpointKind: String? = nil,
        modalities: [String] = [NapaxiChannelModality.text],
        contentFormats: [String] = [NapaxiChannelContentFormat.plainText],
        transport: String? = nil,
        config: [String: NapaxiJSONValue] = [:]
    ) -> Self {
        Self(
            name: name,
            type: type,
            accountId: accountId,
            surfaceKind: NapaxiChannelSurfaceKind.im,
            endpointKind: endpointKind,
            modalities: modalities,
            contentFormats: contentFormats,
            transport: transport,
            config: config
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = ["name": .string(name)]
        if let type {
            object["type"] = .string(type)
        }
        if let accountId {
            object["account_id"] = .string(accountId)
        }
        if let surfaceKind {
            object["surface_kind"] = .string(surfaceKind)
        }
        if let endpointKind {
            object["endpoint_kind"] = .string(endpointKind)
        }
        if !modalities.isEmpty {
            object["modalities"] = .array(modalities.map { .string($0) })
        }
        if !contentFormats.isEmpty {
            object["content_formats"] = .array(contentFormats.map { .string($0) })
        }
        if let transport {
            object["transport"] = .string(transport)
        }
        if !config.isEmpty {
            object["config"] = .object(config)
        }
        return object
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toJson())
    }

    public func jsonString() throws -> String {
        try NapaxiRawJSON(jsonValue()).jsonString()
    }

    public func toJsonString() throws -> String {
        try jsonString()
    }
}

public struct NapaxiChannelRecord: Codable, Equatable, Sendable {
    public var name: String
    public var type: String?
    public var surfaceKind: String?
    public var endpointKind: String?
    public var modalities: [String]
    public var contentFormats: [String]
    public var transport: String?
    public var capabilityId: String?
    public var config: [String: NapaxiJSONValue]
    public var registeredAt: String
    public var updatedAt: String

    public init(
        name: String,
        type: String? = nil,
        surfaceKind: String? = nil,
        endpointKind: String? = nil,
        modalities: [String] = [],
        contentFormats: [String] = [],
        transport: String? = nil,
        capabilityId: String? = nil,
        config: [String: NapaxiJSONValue] = [:],
        registeredAt: String = "",
        updatedAt: String = ""
    ) {
        self.name = name
        self.type = type
        self.surfaceKind = surfaceKind
        self.endpointKind = endpointKind
        self.modalities = modalities
        self.contentFormats = contentFormats
        self.transport = transport
        self.capabilityId = capabilityId
        self.config = config
        self.registeredAt = registeredAt
        self.updatedAt = updatedAt
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            name: json["name"]?.stringValue ?? "",
            type: json["type"]?.stringValue,
            surfaceKind: json["surface_kind"]?.stringValue,
            endpointKind: json["endpoint_kind"]?.stringValue,
            modalities: json.capabilityStringArray("modalities"),
            contentFormats: json.capabilityStringArray("content_formats", fallback: "contentFormats"),
            transport: json["transport"]?.stringValue,
            capabilityId: json["capability_id"]?.stringValue,
            config: json["config"]?.objectValue ?? [:],
            registeredAt: json["registered_at"]?.stringValue ?? "",
            updatedAt: json["updated_at"]?.stringValue ?? ""
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "name": .string(name),
            "config": .object(config),
            "registered_at": .string(registeredAt),
            "updated_at": .string(updatedAt),
        ]
        if let type {
            object["type"] = .string(type)
        }
        if let surfaceKind {
            object["surface_kind"] = .string(surfaceKind)
        }
        if let endpointKind {
            object["endpoint_kind"] = .string(endpointKind)
        }
        if !modalities.isEmpty {
            object["modalities"] = .array(modalities.map { .string($0) })
        }
        if !contentFormats.isEmpty {
            object["content_formats"] = .array(contentFormats.map { .string($0) })
        }
        if let transport {
            object["transport"] = .string(transport)
        }
        if let capabilityId {
            object["capability_id"] = .string(capabilityId)
        }
        return object
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toJson())
    }

    public func jsonString() throws -> String {
        try NapaxiRawJSON(jsonValue()).jsonString()
    }

    public func toJsonString() throws -> String {
        try jsonString()
    }
}

public struct NapaxiChannelPeer: Codable, Equatable, Sendable {
    public var kind: String
    public var id: String
    public var displayName: String?

    public init(kind: String = NapaxiChannelEndpointKind.direct, id: String, displayName: String? = nil) {
        self.kind = kind
        self.id = id
        self.displayName = displayName
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            kind: json["kind"]?.stringValue ?? NapaxiChannelEndpointKind.direct,
            id: json["id"]?.stringValue ?? "",
            displayName: json["display_name"]?.stringValue
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = ["kind": .string(kind), "id": .string(id)]
        if let displayName {
            object["display_name"] = .string(displayName)
        }
        return object
    }
}

public struct NapaxiChannelActor: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String?
    public var isBot: Bool?

    public init(id: String, displayName: String? = nil, isBot: Bool? = nil) {
        self.id = id
        self.displayName = displayName
        self.isBot = isBot
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            id: json["id"]?.stringValue ?? "",
            displayName: json["display_name"]?.stringValue,
            isBot: json["is_bot"]?.boolValue
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = ["id": .string(id)]
        if let displayName {
            object["display_name"] = .string(displayName)
        }
        if let isBot {
            object["is_bot"] = .bool(isBot)
        }
        return object
    }
}

public struct NapaxiChannelMedia: Codable, Equatable, Sendable {
    public var kind: String
    public var uri: String?
    public var mimeType: String?
    public var name: String?
    public var sizeBytes: UInt64?
    public var raw: [String: NapaxiJSONValue]?

    public init(
        kind: String,
        uri: String? = nil,
        mimeType: String? = nil,
        name: String? = nil,
        sizeBytes: UInt64? = nil,
        raw: [String: NapaxiJSONValue]? = nil
    ) {
        self.kind = kind
        self.uri = uri
        self.mimeType = mimeType
        self.name = name
        self.sizeBytes = sizeBytes
        self.raw = raw
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            kind: json["kind"]?.stringValue ?? NapaxiChannelModality.file,
            uri: json["uri"]?.stringValue,
            mimeType: json["mime_type"]?.stringValue,
            name: json["name"]?.stringValue,
            sizeBytes: json["size_bytes"]?.numberValue.map { UInt64($0) },
            raw: json["raw"]?.objectValue
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = ["kind": .string(kind)]
        if let uri {
            object["uri"] = .string(uri)
        }
        if let mimeType {
            object["mime_type"] = .string(mimeType)
        }
        if let name {
            object["name"] = .string(name)
        }
        if let sizeBytes {
            object["size_bytes"] = .number(Double(sizeBytes))
        }
        if let raw {
            object["raw"] = .object(raw)
        }
        return object
    }
}

public struct NapaxiChannelInboundMessage: Codable, Equatable, Sendable {
    public var id: String
    public var channelName: String
    public var accountId: String
    public var peer: NapaxiChannelPeer
    public var sender: NapaxiChannelActor
    public var platformMessageId: String?
    public var threadId: String?
    public var text: String?
    public var media: [NapaxiChannelMedia]
    public var raw: [String: NapaxiJSONValue]?
    public var status: String
    public var receivedAt: String
    public var updatedAt: String

    public init(
        id: String = "",
        channelName: String,
        accountId: String = "default",
        peer: NapaxiChannelPeer,
        sender: NapaxiChannelActor,
        platformMessageId: String? = nil,
        threadId: String? = nil,
        text: String? = nil,
        media: [NapaxiChannelMedia] = [],
        raw: [String: NapaxiJSONValue]? = nil,
        status: String = "",
        receivedAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.channelName = channelName
        self.accountId = accountId
        self.peer = peer
        self.sender = sender
        self.platformMessageId = platformMessageId
        self.threadId = threadId
        self.text = text
        self.media = media
        self.raw = raw
        self.status = status
        self.receivedAt = receivedAt
        self.updatedAt = updatedAt
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            id: json["id"]?.stringValue ?? "",
            channelName: json["channel_name"]?.stringValue ?? json["channel"]?.stringValue ?? "",
            accountId: json["account_id"]?.stringValue ?? "default",
            peer: NapaxiChannelPeer.fromJson(json["peer"]?.objectValue ?? [:]),
            sender: NapaxiChannelActor.fromJson(json["sender"]?.objectValue ?? [:]),
            platformMessageId: json["platform_message_id"]?.stringValue,
            threadId: json["thread_id"]?.stringValue,
            text: json["text"]?.stringValue,
            media: json.channelMediaArray("media"),
            raw: json["raw"]?.objectValue,
            status: json["status"]?.stringValue ?? "",
            receivedAt: json["received_at"]?.stringValue ?? "",
            updatedAt: json["updated_at"]?.stringValue ?? ""
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "channel_name": .string(channelName),
            "account_id": .string(accountId),
            "peer": .object(peer.toJson()),
            "sender": .object(sender.toJson()),
        ]
        if !id.isEmpty {
            object["id"] = .string(id)
        }
        if let platformMessageId {
            object["platform_message_id"] = .string(platformMessageId)
        }
        if let threadId {
            object["thread_id"] = .string(threadId)
        }
        if let text {
            object["text"] = .string(text)
        }
        if !media.isEmpty {
            object["media"] = .array(media.map { .object($0.toJson()) })
        }
        if let raw {
            object["raw"] = .object(raw)
        }
        return object
    }

    public func jsonString() throws -> String { try NapaxiRawJSON(.object(toJson())).jsonString() }
    public func toJsonString() throws -> String { try jsonString() }
}

public struct NapaxiChannelOutboundMessage: Codable, Equatable, Sendable {
    public var id: String
    public var channelName: String
    public var accountId: String
    public var peer: NapaxiChannelPeer
    public var replyToMessageId: String?
    public var threadId: String?
    public var text: String?
    public var format: String?
    public var media: [NapaxiChannelMedia]
    public var raw: [String: NapaxiJSONValue]?
    public var leaseId: String?
    public var platformReceipt: [String: NapaxiJSONValue]?
    public var error: String?
    public var status: String
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = "",
        channelName: String,
        accountId: String = "default",
        peer: NapaxiChannelPeer,
        replyToMessageId: String? = nil,
        threadId: String? = nil,
        text: String? = nil,
        format: String? = nil,
        media: [NapaxiChannelMedia] = [],
        raw: [String: NapaxiJSONValue]? = nil,
        leaseId: String? = nil,
        platformReceipt: [String: NapaxiJSONValue]? = nil,
        error: String? = nil,
        status: String = "",
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.channelName = channelName
        self.accountId = accountId
        self.peer = peer
        self.replyToMessageId = replyToMessageId
        self.threadId = threadId
        self.text = text
        self.format = format
        self.media = media
        self.raw = raw
        self.leaseId = leaseId
        self.platformReceipt = platformReceipt
        self.error = error
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            id: json["id"]?.stringValue ?? "",
            channelName: json["channel_name"]?.stringValue ?? json["channel"]?.stringValue ?? "",
            accountId: json["account_id"]?.stringValue ?? "default",
            peer: NapaxiChannelPeer.fromJson(json["peer"]?.objectValue ?? [:]),
            replyToMessageId: json["reply_to_message_id"]?.stringValue,
            threadId: json["thread_id"]?.stringValue,
            text: json["text"]?.stringValue,
            format: json["format"]?.stringValue ?? json["content_format"]?.stringValue ?? json["contentFormat"]?.stringValue,
            media: json.channelMediaArray("media"),
            raw: json["raw"]?.objectValue,
            leaseId: json["lease_id"]?.stringValue,
            platformReceipt: json["platform_receipt"]?.objectValue,
            error: json["error"]?.stringValue,
            status: json["status"]?.stringValue ?? "",
            createdAt: json["created_at"]?.stringValue ?? "",
            updatedAt: json["updated_at"]?.stringValue ?? ""
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "channel_name": .string(channelName),
            "account_id": .string(accountId),
            "peer": .object(peer.toJson()),
        ]
        if !id.isEmpty {
            object["id"] = .string(id)
        }
        if let replyToMessageId {
            object["reply_to_message_id"] = .string(replyToMessageId)
        }
        if let threadId {
            object["thread_id"] = .string(threadId)
        }
        if let text {
            object["text"] = .string(text)
        }
        if let format, !format.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object["format"] = .string(format)
        }
        if !media.isEmpty {
            object["media"] = .array(media.map { .object($0.toJson()) })
        }
        if let raw {
            object["raw"] = .object(raw)
        }
        return object
    }

    public func jsonString() throws -> String { try NapaxiRawJSON(.object(toJson())).jsonString() }
    public func toJsonString() throws -> String { try jsonString() }
}

public struct NapaxiChannelAcceptedReceipt: Codable, Equatable, Sendable {
    public var accepted: Bool
    public var id: String
    public var duplicate: Bool
    public var error: String?

    public init(accepted: Bool, id: String, duplicate: Bool = false, error: String? = nil) {
        self.accepted = accepted
        self.id = id
        self.duplicate = duplicate
        self.error = error
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            accepted: json["accepted"]?.boolValue ?? false,
            id: json["id"]?.stringValue ?? "",
            duplicate: json["duplicate"]?.boolValue ?? false,
            error: json["error"]?.stringValue
        )
    }
}

public struct NapaxiChannelAgentRoute: Codable, Equatable, Sendable {
    public var id: String
    public var channelName: String
    public var channelAccountId: String?
    public var peerKind: String?
    public var peerId: String?
    public var threadId: String?
    public var sessionAccountId: String
    public var agentId: String
    public var enabled: Bool
    public var sessionPolicy: String
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = "",
        channelName: String,
        channelAccountId: String? = nil,
        peerKind: String? = nil,
        peerId: String? = nil,
        threadId: String? = nil,
        sessionAccountId: String = "default",
        agentId: String = "napaxi",
        enabled: Bool = true,
        sessionPolicy: String = "stable_by_peer_or_thread",
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.channelName = channelName
        self.channelAccountId = channelAccountId
        self.peerKind = peerKind
        self.peerId = peerId
        self.threadId = threadId
        self.sessionAccountId = sessionAccountId
        self.agentId = agentId
        self.enabled = enabled
        self.sessionPolicy = sessionPolicy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func channelDefault(
        channelName: String,
        channelAccountId: String? = nil,
        sessionAccountId: String,
        agentId: String,
        enabled: Bool = true
    ) -> Self {
        Self(
            channelName: channelName,
            channelAccountId: channelAccountId,
            sessionAccountId: sessionAccountId,
            agentId: agentId,
            enabled: enabled
        )
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            id: json["id"]?.stringValue ?? "",
            channelName: json["channel_name"]?.stringValue ?? json["channel"]?.stringValue ?? "",
            channelAccountId: json["channel_account_id"]?.stringValue,
            peerKind: json["peer_kind"]?.stringValue,
            peerId: json["peer_id"]?.stringValue,
            threadId: json["thread_id"]?.stringValue,
            sessionAccountId: json["session_account_id"]?.stringValue ?? "default",
            agentId: json["agent_id"]?.stringValue ?? "napaxi",
            enabled: json["enabled"]?.boolValue ?? true,
            sessionPolicy: json["session_policy"]?.stringValue ?? "stable_by_peer_or_thread",
            createdAt: json["created_at"]?.stringValue ?? "",
            updatedAt: json["updated_at"]?.stringValue ?? ""
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "channel_name": .string(channelName),
            "session_account_id": .string(sessionAccountId),
            "agent_id": .string(agentId),
            "enabled": .bool(enabled),
            "session_policy": .string(sessionPolicy),
        ]
        if !id.isEmpty {
            object["id"] = .string(id)
        }
        if let channelAccountId {
            object["channel_account_id"] = .string(channelAccountId)
        }
        if let peerKind {
            object["peer_kind"] = .string(peerKind)
        }
        if let peerId {
            object["peer_id"] = .string(peerId)
        }
        if let threadId {
            object["thread_id"] = .string(threadId)
        }
        return object
    }

    public func jsonString() throws -> String { try NapaxiRawJSON(.object(toJson())).jsonString() }
    public func toJsonString() throws -> String { try jsonString() }
}

public struct NapaxiChannelAgentStatus: Codable, Equatable, Sendable {
    public var routes: [NapaxiChannelAgentRoute]
    public var pendingHuman: [[String: NapaxiJSONValue]]

    public init(routes: [NapaxiChannelAgentRoute] = [], pendingHuman: [[String: NapaxiJSONValue]] = []) {
        self.routes = routes
        self.pendingHuman = pendingHuman
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            routes: json["routes"]?.arrayValue?.compactMap { item in
                item.objectValue.map(NapaxiChannelAgentRoute.fromJson)
            } ?? [],
            pendingHuman: json["pending_human"]?.arrayValue?.compactMap { $0.objectValue } ?? []
        )
    }
}

public struct NapaxiScenarioSettingsContribution: Codable, Equatable, Sendable {
    public var id: String
    public var capabilityId: String
    public var placement: String
    public var title: String
    public var description: String
    public var schema: [String: NapaxiJSONValue]
    public var actions: [String]

    public init(
        id: String,
        capabilityId: String,
        placement: String = "",
        title: String = "",
        description: String = "",
        schema: [String: NapaxiJSONValue] = [:],
        actions: [String] = []
    ) {
        self.id = id
        self.capabilityId = capabilityId
        self.placement = placement
        self.title = title
        self.description = description
        self.schema = schema
        self.actions = actions
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            id: json["id"]?.stringValue ?? "",
            capabilityId: json["capability_id"]?.stringValue ?? "",
            placement: json["placement"]?.stringValue ?? "",
            title: json["title"]?.stringValue ?? "",
            description: json["description"]?.stringValue ?? "",
            schema: json["schema"]?.objectValue ?? [:],
            actions: json.capabilityStringArray("actions")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "id": .string(id),
            "capability_id": .string(capabilityId),
            "placement": .string(placement),
            "title": .string(title),
            "description": .string(description),
            "schema": .object(schema),
            "actions": .array(actions.map { .string($0) }),
        ]
    }

    enum CodingKeys: String, CodingKey {
        case id
        case capabilityId = "capability_id"
        case placement
        case title
        case description
        case schema
        case actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = Self(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
            capabilityId: try container.decodeIfPresent(String.self, forKey: .capabilityId) ?? "",
            placement: try container.decodeIfPresent(String.self, forKey: .placement) ?? "",
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
            schema: try container.decodeIfPresent([String: NapaxiJSONValue].self, forKey: .schema) ?? [:],
            actions: try container.decodeNapaxiStringArray(forKey: .actions)
        )
    }
}

public struct NapaxiScenarioUiContribution: Codable, Equatable, Sendable {
    public var id: String
    public var capabilityId: String
    public var placement: String
    public var title: String
    public var description: String
    public var icon: String
    public var renderer: String
    public var dataSources: [String: NapaxiJSONValue]
    public var actions: [String]

    public init(
        id: String,
        capabilityId: String,
        placement: String = "",
        title: String = "",
        description: String = "",
        icon: String = "",
        renderer: String,
        dataSources: [String: NapaxiJSONValue] = [:],
        actions: [String] = []
    ) {
        self.id = id
        self.capabilityId = capabilityId
        self.placement = placement
        self.title = title
        self.description = description
        self.icon = icon
        self.renderer = renderer
        self.dataSources = dataSources
        self.actions = actions
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            id: json["id"]?.stringValue ?? "",
            capabilityId: json["capability_id"]?.stringValue ?? "",
            placement: json["placement"]?.stringValue ?? "",
            title: json["title"]?.stringValue ?? "",
            description: json["description"]?.stringValue ?? "",
            icon: json["icon"]?.stringValue ?? "",
            renderer: json["renderer"]?.stringValue ?? "",
            dataSources: json["data_sources"]?.objectValue ?? [:],
            actions: json.capabilityStringArray("actions")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "id": .string(id),
            "capability_id": .string(capabilityId),
            "placement": .string(placement),
            "title": .string(title),
            "description": .string(description),
            "icon": .string(icon),
            "renderer": .string(renderer),
            "data_sources": .object(dataSources),
            "actions": .array(actions.map { .string($0) }),
        ]
    }

    enum CodingKeys: String, CodingKey {
        case id
        case capabilityId = "capability_id"
        case placement
        case title
        case description
        case icon
        case renderer
        case dataSources = "data_sources"
        case actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = Self(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
            capabilityId: try container.decodeIfPresent(String.self, forKey: .capabilityId) ?? "",
            placement: try container.decodeIfPresent(String.self, forKey: .placement) ?? "",
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
            icon: try container.decodeIfPresent(String.self, forKey: .icon) ?? "",
            renderer: try container.decodeIfPresent(String.self, forKey: .renderer) ?? "",
            dataSources: try container.decodeIfPresent([String: NapaxiJSONValue].self, forKey: .dataSources) ?? [:],
            actions: try container.decodeNapaxiStringArray(forKey: .actions)
        )
    }
}

public struct NapaxiScenarioPack: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    public var label: String
    public var description: String
    public var risk: String
    public var activation: String
    public var executionPlanes: [String]
    public var requiredCapabilities: [String]
    public var recommendedCapabilities: [String]
    public var optionalCapabilities: [String]
    public var uiSurfaces: [String]
    public var settingsContributions: [NapaxiScenarioSettingsContribution]
    public var uiContributions: [NapaxiScenarioUiContribution]
    public var memoryScopes: [String]
    public var tags: [String]

    public init(
        id: String,
        version: String,
        label: String,
        description: String,
        risk: String,
        activation: String,
        executionPlanes: [String] = [],
        requiredCapabilities: [String] = [],
        recommendedCapabilities: [String] = [],
        optionalCapabilities: [String] = [],
        uiSurfaces: [String] = [],
        settingsContributions: [NapaxiScenarioSettingsContribution] = [],
        uiContributions: [NapaxiScenarioUiContribution] = [],
        memoryScopes: [String] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.version = version
        self.label = label
        self.description = description
        self.risk = risk
        self.activation = activation
        self.executionPlanes = executionPlanes
        self.requiredCapabilities = requiredCapabilities
        self.recommendedCapabilities = recommendedCapabilities
        self.optionalCapabilities = optionalCapabilities
        self.uiSurfaces = uiSurfaces
        self.settingsContributions = settingsContributions
        self.uiContributions = uiContributions
        self.memoryScopes = memoryScopes
        self.tags = tags
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            id: json["id"]?.stringValue ?? "",
            version: json["version"]?.stringValue ?? "",
            label: json["label"]?.stringValue ?? "",
            description: json["description"]?.stringValue ?? "",
            risk: json["risk"]?.stringValue ?? "",
            activation: json["activation"]?.stringValue ?? "",
            executionPlanes: json.capabilityStringArray("execution_planes"),
            requiredCapabilities: json.capabilityStringArray("required_capabilities"),
            recommendedCapabilities: json.capabilityStringArray("recommended_capabilities"),
            optionalCapabilities: json.capabilityStringArray("optional_capabilities"),
            uiSurfaces: json.capabilityStringArray("ui_surfaces"),
            settingsContributions: json.scenarioSettingsContributions("settings_contributions"),
            uiContributions: json.scenarioUiContributions("ui_contributions"),
            memoryScopes: json.capabilityStringArray("memory_scopes"),
            tags: json.capabilityStringArray("tags")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "id": .string(id),
            "version": .string(version),
            "label": .string(label),
            "description": .string(description),
            "risk": .string(risk),
            "activation": .string(activation),
            "execution_planes": .array(executionPlanes.map { .string($0) }),
            "required_capabilities": .array(requiredCapabilities.map { .string($0) }),
            "recommended_capabilities": .array(recommendedCapabilities.map { .string($0) }),
            "optional_capabilities": .array(optionalCapabilities.map { .string($0) }),
            "ui_surfaces": .array(uiSurfaces.map { .string($0) }),
            "settings_contributions": .array(settingsContributions.map { .object($0.toJson()) }),
            "ui_contributions": .array(uiContributions.map { .object($0.toJson()) }),
            "memory_scopes": .array(memoryScopes.map { .string($0) }),
            "tags": .array(tags.map { .string($0) }),
        ]
    }

    public func jsonValue() -> NapaxiJSONValue { .object(toJson()) }
    public func jsonString() throws -> String { try NapaxiRawJSON(jsonValue()).jsonString() }
    public func toJsonString() throws -> String { try jsonString() }

    enum CodingKeys: String, CodingKey {
        case id
        case version
        case label
        case description
        case risk
        case activation
        case executionPlanes = "execution_planes"
        case requiredCapabilities = "required_capabilities"
        case recommendedCapabilities = "recommended_capabilities"
        case optionalCapabilities = "optional_capabilities"
        case uiSurfaces = "ui_surfaces"
        case settingsContributions = "settings_contributions"
        case uiContributions = "ui_contributions"
        case memoryScopes = "memory_scopes"
        case tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = Self(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
            version: try container.decodeIfPresent(String.self, forKey: .version) ?? "",
            label: try container.decodeIfPresent(String.self, forKey: .label) ?? "",
            description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
            risk: try container.decodeIfPresent(String.self, forKey: .risk) ?? "",
            activation: try container.decodeIfPresent(String.self, forKey: .activation) ?? "",
            executionPlanes: try container.decodeNapaxiStringArray(forKey: .executionPlanes),
            requiredCapabilities: try container.decodeNapaxiStringArray(forKey: .requiredCapabilities),
            recommendedCapabilities: try container.decodeNapaxiStringArray(forKey: .recommendedCapabilities),
            optionalCapabilities: try container.decodeNapaxiStringArray(forKey: .optionalCapabilities),
            uiSurfaces: try container.decodeNapaxiStringArray(forKey: .uiSurfaces),
            settingsContributions: try container.decodeIfPresent([NapaxiScenarioSettingsContribution].self, forKey: .settingsContributions) ?? [],
            uiContributions: try container.decodeIfPresent([NapaxiScenarioUiContribution].self, forKey: .uiContributions) ?? [],
            memoryScopes: try container.decodeNapaxiStringArray(forKey: .memoryScopes),
            tags: try container.decodeNapaxiStringArray(forKey: .tags)
        )
    }
}

public struct NapaxiScenarioStatus: Codable, Equatable, Sendable {
    public var definition: NapaxiScenarioPack
    public var registered: Bool
    public var available: Bool
    public var enabled: Bool
    public var missingRequiredCapabilities: [String]
    public var disabledRequiredCapabilities: [String]
    public var unavailableReasons: [String]

    public init(
        definition: NapaxiScenarioPack,
        registered: Bool,
        available: Bool,
        enabled: Bool,
        missingRequiredCapabilities: [String] = [],
        disabledRequiredCapabilities: [String] = [],
        unavailableReasons: [String] = []
    ) {
        self.definition = definition
        self.registered = registered
        self.available = available
        self.enabled = enabled
        self.missingRequiredCapabilities = missingRequiredCapabilities
        self.disabledRequiredCapabilities = disabledRequiredCapabilities
        self.unavailableReasons = unavailableReasons
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            definition: NapaxiScenarioPack.fromJson(json["definition"]?.objectValue ?? [:]),
            registered: json["registered"]?.boolValue ?? false,
            available: json["available"]?.boolValue ?? false,
            enabled: json["enabled"]?.boolValue ?? false,
            missingRequiredCapabilities: json.capabilityStringArray("missing_required_capabilities"),
            disabledRequiredCapabilities: json.capabilityStringArray("disabled_required_capabilities"),
            unavailableReasons: json.capabilityStringArray("unavailable_reasons")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "definition": .object(definition.toJson()),
            "registered": .bool(registered),
            "available": .bool(available),
            "enabled": .bool(enabled),
            "missing_required_capabilities": .array(missingRequiredCapabilities.map { .string($0) }),
            "disabled_required_capabilities": .array(disabledRequiredCapabilities.map { .string($0) }),
            "unavailable_reasons": .array(unavailableReasons.map { .string($0) }),
        ]
    }

    public func jsonValue() -> NapaxiJSONValue { .object(toJson()) }
    public func jsonString() throws -> String { try NapaxiRawJSON(jsonValue()).jsonString() }
    public func toJsonString() throws -> String { try jsonString() }

    enum CodingKeys: String, CodingKey {
        case definition
        case registered
        case available
        case enabled
        case missingRequiredCapabilities = "missing_required_capabilities"
        case disabledRequiredCapabilities = "disabled_required_capabilities"
        case unavailableReasons = "unavailable_reasons"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = Self(
            definition: try container.decodeIfPresent(NapaxiScenarioPack.self, forKey: .definition)
                ?? NapaxiScenarioPack(id: "", version: "", label: "", description: "", risk: "", activation: ""),
            registered: try container.decodeIfPresent(Bool.self, forKey: .registered) ?? false,
            available: try container.decodeIfPresent(Bool.self, forKey: .available) ?? false,
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            missingRequiredCapabilities: try container.decodeNapaxiStringArray(forKey: .missingRequiredCapabilities),
            disabledRequiredCapabilities: try container.decodeNapaxiStringArray(forKey: .disabledRequiredCapabilities),
            unavailableReasons: try container.decodeNapaxiStringArray(forKey: .unavailableReasons)
        )
    }
}

public struct NapaxiScenarioActivationPlan: Codable, Equatable, Sendable {
    public var supportedCapabilities: [String]
    public var enabledCapabilities: [String]
    public var disabledCapabilities: [String]
    public var hostRequiredCapabilities: [String]
    public var remoteRequiredCapabilities: [String]
    public var policyRequiredCapabilities: [String]
    public var warnings: [String]

    public init(
        supportedCapabilities: [String] = [],
        enabledCapabilities: [String] = [],
        disabledCapabilities: [String] = [],
        hostRequiredCapabilities: [String] = [],
        remoteRequiredCapabilities: [String] = [],
        policyRequiredCapabilities: [String] = [],
        warnings: [String] = []
    ) {
        self.supportedCapabilities = supportedCapabilities
        self.enabledCapabilities = enabledCapabilities
        self.disabledCapabilities = disabledCapabilities
        self.hostRequiredCapabilities = hostRequiredCapabilities
        self.remoteRequiredCapabilities = remoteRequiredCapabilities
        self.policyRequiredCapabilities = policyRequiredCapabilities
        self.warnings = warnings
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            supportedCapabilities: json.capabilityStringArray("supported_capabilities"),
            enabledCapabilities: json.capabilityStringArray("enabled_capabilities"),
            disabledCapabilities: json.capabilityStringArray("disabled_capabilities"),
            hostRequiredCapabilities: json.capabilityStringArray("host_required_capabilities"),
            remoteRequiredCapabilities: json.capabilityStringArray("remote_required_capabilities"),
            policyRequiredCapabilities: json.capabilityStringArray("policy_required_capabilities"),
            warnings: json.capabilityStringArray("warnings")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "supported_capabilities": .array(supportedCapabilities.map { .string($0) }),
            "enabled_capabilities": .array(enabledCapabilities.map { .string($0) }),
            "disabled_capabilities": .array(disabledCapabilities.map { .string($0) }),
            "host_required_capabilities": .array(hostRequiredCapabilities.map { .string($0) }),
            "remote_required_capabilities": .array(remoteRequiredCapabilities.map { .string($0) }),
            "policy_required_capabilities": .array(policyRequiredCapabilities.map { .string($0) }),
            "warnings": .array(warnings.map { .string($0) }),
        ]
    }

    public func jsonValue() -> NapaxiJSONValue { .object(toJson()) }
    public func jsonString() throws -> String { try NapaxiRawJSON(jsonValue()).jsonString() }
    public func toJsonString() throws -> String { try jsonString() }

    enum CodingKeys: String, CodingKey {
        case supportedCapabilities = "supported_capabilities"
        case enabledCapabilities = "enabled_capabilities"
        case disabledCapabilities = "disabled_capabilities"
        case hostRequiredCapabilities = "host_required_capabilities"
        case remoteRequiredCapabilities = "remote_required_capabilities"
        case policyRequiredCapabilities = "policy_required_capabilities"
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = Self(
            supportedCapabilities: try container.decodeNapaxiStringArray(forKey: .supportedCapabilities),
            enabledCapabilities: try container.decodeNapaxiStringArray(forKey: .enabledCapabilities),
            disabledCapabilities: try container.decodeNapaxiStringArray(forKey: .disabledCapabilities),
            hostRequiredCapabilities: try container.decodeNapaxiStringArray(forKey: .hostRequiredCapabilities),
            remoteRequiredCapabilities: try container.decodeNapaxiStringArray(forKey: .remoteRequiredCapabilities),
            policyRequiredCapabilities: try container.decodeNapaxiStringArray(forKey: .policyRequiredCapabilities),
            warnings: try container.decodeNapaxiStringArray(forKey: .warnings)
        )
    }
}

public struct NapaxiScenarioResolution: Codable, Equatable, Sendable {
    public var status: NapaxiScenarioStatus
    public var activationPlan: NapaxiScenarioActivationPlan

    public init(status: NapaxiScenarioStatus, activationPlan: NapaxiScenarioActivationPlan) {
        self.status = status
        self.activationPlan = activationPlan
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            status: NapaxiScenarioStatus.fromJson(json["status"]?.objectValue ?? [:]),
            activationPlan: NapaxiScenarioActivationPlan.fromJson(json["activation_plan"]?.objectValue ?? [:])
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "status": .object(status.toJson()),
            "activation_plan": .object(activationPlan.toJson()),
        ]
    }

    public func jsonValue() -> NapaxiJSONValue { .object(toJson()) }
    public func jsonString() throws -> String { try NapaxiRawJSON(jsonValue()).jsonString() }
    public func toJsonString() throws -> String { try jsonString() }

    enum CodingKeys: String, CodingKey {
        case status
        case activationPlan = "activation_plan"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = Self(
            status: try container.decodeIfPresent(NapaxiScenarioStatus.self, forKey: .status)
                ?? NapaxiScenarioStatus(
                    definition: NapaxiScenarioPack(id: "", version: "", label: "", description: "", risk: "", activation: ""),
                    registered: false,
                    available: false,
                    enabled: false
                ),
            activationPlan: try container.decodeIfPresent(NapaxiScenarioActivationPlan.self, forKey: .activationPlan)
                ?? NapaxiScenarioActivationPlan()
        )
    }
}

public struct NapaxiScenarioPackInstallResult: Codable, Equatable, Sendable {
    public var definition: NapaxiScenarioPack
    public var installed: Bool
    public var replaced: Bool
    public var warnings: [String]

    public init(
        definition: NapaxiScenarioPack,
        installed: Bool,
        replaced: Bool,
        warnings: [String] = []
    ) {
        self.definition = definition
        self.installed = installed
        self.replaced = replaced
        self.warnings = warnings
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            definition: NapaxiScenarioPack.fromJson(json["definition"]?.objectValue ?? [:]),
            installed: json["installed"]?.boolValue ?? false,
            replaced: json["replaced"]?.boolValue ?? false,
            warnings: json.capabilityStringArray("warnings")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "definition": .object(definition.toJson()),
            "installed": .bool(installed),
            "replaced": .bool(replaced),
            "warnings": .array(warnings.map { .string($0) }),
        ]
    }

    public func jsonValue() -> NapaxiJSONValue { .object(toJson()) }
    public func jsonString() throws -> String { try NapaxiRawJSON(jsonValue()).jsonString() }
    public func toJsonString() throws -> String { try jsonString() }

    enum CodingKeys: String, CodingKey {
        case definition
        case installed
        case replaced
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = Self(
            definition: try container.decodeIfPresent(NapaxiScenarioPack.self, forKey: .definition)
                ?? NapaxiScenarioPack(id: "", version: "", label: "", description: "", risk: "", activation: ""),
            installed: try container.decodeIfPresent(Bool.self, forKey: .installed) ?? false,
            replaced: try container.decodeIfPresent(Bool.self, forKey: .replaced) ?? false,
            warnings: try container.decodeNapaxiStringArray(forKey: .warnings)
        )
    }
}

public struct NapaxiScenarioPackRemovalResult: Codable, Equatable, Sendable {
    public var scenarioId: String
    public var removed: Bool

    public init(scenarioId: String, removed: Bool) {
        self.scenarioId = scenarioId
        self.removed = removed
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(
            scenarioId: json["scenario_id"]?.stringValue ?? "",
            removed: json["removed"]?.boolValue ?? false
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "scenario_id": .string(scenarioId),
            "removed": .bool(removed),
        ]
    }

    public func jsonValue() -> NapaxiJSONValue { .object(toJson()) }
    public func jsonString() throws -> String { try NapaxiRawJSON(jsonValue()).jsonString() }
    public func toJsonString() throws -> String { try jsonString() }

    enum CodingKeys: String, CodingKey {
        case scenarioId = "scenario_id"
        case removed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = Self(
            scenarioId: try container.decodeIfPresent(String.self, forKey: .scenarioId) ?? "",
            removed: try container.decodeIfPresent(Bool.self, forKey: .removed) ?? false
        )
    }
}

public func decodeCapabilityDefinitions(_ raw: String) throws -> [NapaxiCapabilityDefinition] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value) { object in
        try NapaxiJSONValue.object(object).decodedObject(of: NapaxiCapabilityDefinition.self)
    }
}

public func decodeChannelRecords(_ raw: String) throws -> [NapaxiChannelRecord] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value) { object in
        NapaxiChannelRecord.fromJson(object)
    }
}

public func decodeChannelAcceptedReceipt(_ raw: String) throws -> NapaxiChannelAcceptedReceipt {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .object(let object) = value else {
        return NapaxiChannelAcceptedReceipt(accepted: false, id: "")
    }
    return NapaxiChannelAcceptedReceipt.fromJson(object)
}

public func decodeChannelInboundMessages(_ raw: String) throws -> [NapaxiChannelInboundMessage] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value) { object in
        NapaxiChannelInboundMessage.fromJson(object)
    }
}

public func decodeChannelOutboundMessages(_ raw: String) throws -> [NapaxiChannelOutboundMessage] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value) { object in
        NapaxiChannelOutboundMessage.fromJson(object)
    }
}

public func decodeCapabilityStatuses(_ raw: String) throws -> [NapaxiCapabilityStatus] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value) { object in
        try NapaxiJSONValue.object(object).decodedObject(of: NapaxiCapabilityStatus.self)
    }
}

public func decodeScenarioPacks(_ raw: String) throws -> [NapaxiScenarioPack] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value) { object in
        try NapaxiJSONValue.object(object).decodedObject(of: NapaxiScenarioPack.self)
    }
}

public func decodeScenarioStatuses(_ raw: String) throws -> [NapaxiScenarioStatus] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value) { object in
        try NapaxiJSONValue.object(object).decodedObject(of: NapaxiScenarioStatus.self)
    }
}

public func decodeScenarioResolution(_ raw: String) throws -> NapaxiScenarioResolution? {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .object(let object) = value, object["error"] == nil else { return nil }
    return try value.decodedObject(of: NapaxiScenarioResolution.self)
}

public func decodeScenarioPackInstallResult(_ raw: String) throws -> NapaxiScenarioPackInstallResult? {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .object(let object) = value, object["error"] == nil else { return nil }
    return try value.decodedObject(of: NapaxiScenarioPackInstallResult.self)
}

public func decodeScenarioPackRemovalResult(_ raw: String) throws -> NapaxiScenarioPackRemovalResult? {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .object(let object) = value, object["error"] == nil else { return nil }
    return try value.decodedObject(of: NapaxiScenarioPackRemovalResult.self)
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func capabilityStringArray(_ key: String, fallback: String? = nil) -> [String] {
        let value = self[key] ?? fallback.flatMap { self[$0] }
        guard case .array(let values)? = value else { return [] }
        return values.map(\.jsonCodecDisplayString)
    }

    func channelMediaArray(_ key: String) -> [NapaxiChannelMedia] {
        guard case .array(let values)? = self[key] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value else { return nil }
            return NapaxiChannelMedia.fromJson(object)
        }
    }

    func scenarioSettingsContributions(_ key: String) -> [NapaxiScenarioSettingsContribution] {
        guard case .array(let values)? = self[key] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value else { return nil }
            return NapaxiScenarioSettingsContribution.fromJson(object)
        }
    }

    func scenarioUiContributions(_ key: String) -> [NapaxiScenarioUiContribution] {
        guard case .array(let values)? = self[key] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value else { return nil }
            return NapaxiScenarioUiContribution.fromJson(object)
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeNapaxiStringArray(forKey key: Key) throws -> [String] {
        let values = try decodeIfPresent([NapaxiJSONValue].self, forKey: key) ?? []
        return values.map(\.jsonCodecDisplayString)
    }
}

private extension KeyedDecodingContainer where Key == NapaxiCapabilityDefinition.CodingKeys {
    func decodeFlutterStringArray(forKey key: Key) throws -> [String] {
        let values = try decodeIfPresent([NapaxiJSONValue].self, forKey: key) ?? []
        return values.map(\.jsonCodecDisplayString)
    }
}

public struct NapaxiAttachment: Codable, Equatable, Sendable {
    public var kind: String
    public var mimeType: String
    public var filename: String?
    public var sandboxPath: String?
    public var localPath: String?
    public var dataBase64: String
    public var extractedText: String?

    public init(
        kind: String,
        mimeType: String,
        filename: String? = nil,
        sandboxPath: String? = nil,
        localPath: String? = nil,
        dataBase64: String,
        extractedText: String? = nil
    ) {
        self.kind = kind
        self.mimeType = mimeType
        self.filename = filename
        self.sandboxPath = sandboxPath
        self.localPath = localPath
        self.dataBase64 = dataBase64
        self.extractedText = extractedText
    }

    public init(
        kind: String,
        mimeType: String,
        filename: String? = nil,
        sandboxPath: String? = nil,
        localPath: String? = nil,
        data: Data,
        extractedText: String? = nil
    ) {
        self.init(
            kind: kind,
            mimeType: mimeType,
            filename: filename,
            sandboxPath: sandboxPath,
            localPath: localPath,
            dataBase64: data.base64EncodedString(),
            extractedText: extractedText
        )
    }

    public var data: Data? {
        Data(base64Encoded: dataBase64)
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case mimeType = "mime_type"
        case filename
        case sandboxPath = "sandbox_path"
        case localPath = "path"
        case dataBase64 = "data_base64"
        case extractedText = "extracted_text"
    }

    public func toMap(sandboxPath overrideSandboxPath: String? = nil) -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "kind": .string(kind),
            "mime_type": .string(mimeType),
            "data_base64": .string(dataBase64),
        ]
        if let filename { object["filename"] = .string(filename) }
        if let sandboxPath = overrideSandboxPath ?? sandboxPath {
            object["sandbox_path"] = .string(sandboxPath)
        }
        if let localPath { object["path"] = .string(localPath) }
        if let extractedText { object["extracted_text"] = .string(extractedText) }
        return object
    }

    public static func jsonString(for attachments: [NapaxiAttachment]) throws -> String {
        let value = NapaxiJSONValue.array(attachments.map { .object($0.toMap()) })
        return try NapaxiRawJSON(value).jsonString()
    }
}

public struct NapaxiSessionKey: Codable, Equatable, Sendable {
    public var channelType: String
    public var accountId: String
    public var threadId: String

    public init(channelType: String = "app", accountId: String = "default", threadId: String) {
        self.channelType = channelType
        self.accountId = accountId
        self.threadId = threadId
    }

    enum CodingKeys: String, CodingKey {
        case channelType = "channel_type"
        case accountId = "account_id"
        case threadId = "thread_id"
    }

    public func jsonString() throws -> String {
        String(data: try JSONEncoder().encode(self), encoding: .utf8) ?? "{}"
    }
}

public enum NapaxiSessionRunStatus: String, Codable, Equatable, Sendable {
    case running
    case waitingForInput
    case cancelling
    case completed
    case failed
    case cancelled

    enum CodingKeys: String, CodingKey {
        case running
        case waitingForInput = "waiting_for_input"
        case cancelling
        case completed
        case failed
        case cancelled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "running": self = .running
        case "waiting_for_input", "waitingForInput": self = .waitingForInput
        case "cancelling": self = .cancelling
        case "completed": self = .completed
        case "failed": self = .failed
        case "cancelled": self = .cancelled
        default: self = .failed
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .waitingForInput:
            try container.encode("waiting_for_input")
        default:
            try container.encode(rawValue)
        }
    }
}

public struct NapaxiSessionRunInfo: Codable, Equatable, Sendable {
    public var key: NapaxiSessionKey
    public var agentId: String
    public var status: NapaxiSessionRunStatus
    public var activity: String
    public var humanRequestId: String?
    public var error: String?
    public var startedAt: Date
    public var updatedAt: Date

    public init(
        key: NapaxiSessionKey,
        agentId: String,
        status: NapaxiSessionRunStatus,
        activity: String,
        humanRequestId: String? = nil,
        error: String? = nil,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.key = key
        self.agentId = agentId
        self.status = status
        self.activity = activity
        self.humanRequestId = humanRequestId
        self.error = error
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var id: String {
        "\(agentId):\(key.channelType):\(key.accountId):\(key.threadId)"
    }

    public var isTerminal: Bool {
        status == .completed || status == .failed || status == .cancelled
    }

    public var needsInput: Bool {
        status == .waitingForInput
    }

    enum CodingKeys: String, CodingKey {
        case key
        case agentId = "agent_id"
        case status
        case activity
        case humanRequestId = "human_request_id"
        case error
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }

    public func copyWith(
        status: NapaxiSessionRunStatus? = nil,
        activity: String? = nil,
        humanRequestId: String? = nil,
        clearHumanRequest: Bool = false,
        error: String? = nil,
        clearError: Bool = false,
        updatedAt: Date? = nil
    ) -> NapaxiSessionRunInfo {
        NapaxiSessionRunInfo(
            key: key,
            agentId: agentId,
            status: status ?? self.status,
            activity: activity ?? self.activity,
            humanRequestId: clearHumanRequest ? nil : (humanRequestId ?? self.humanRequestId),
            error: clearError ? nil : (error ?? self.error),
            startedAt: startedAt,
            updatedAt: updatedAt ?? self.updatedAt
        )
    }

    func updated(
        status: NapaxiSessionRunStatus? = nil,
        activity: String? = nil,
        humanRequestId: String? = nil,
        clearHumanRequest: Bool = false,
        error: String? = nil,
        clearError: Bool = false,
        updatedAt: Date = Date()
    ) -> NapaxiSessionRunInfo {
        copyWith(
            status: status,
            activity: activity,
            humanRequestId: humanRequestId,
            clearHumanRequest: clearHumanRequest,
            error: error,
            clearError: clearError,
            updatedAt: updatedAt
        )
    }
}

public struct NapaxiChatEvent: Codable, Equatable, Sendable {
    public var raw: NapaxiJSONValue

    public init(raw: NapaxiJSONValue) {
        self.raw = raw
    }

    public init(map: [String: NapaxiJSONValue]) {
        self.raw = .object(map)
    }

    public init(jsonString: String) throws {
        self.raw = try NapaxiRawJSON(jsonString: jsonString).value
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> NapaxiChatEvent {
        NapaxiChatEvent(map: map)
    }

    public static func fromJsonString(_ jsonString: String) throws -> NapaxiChatEvent {
        try NapaxiChatEvent(jsonString: jsonString)
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        object
    }

    public var object: [String: NapaxiJSONValue] {
        guard case .object(let object) = raw else { return [:] }
        return object
    }

    public var type: String {
        string("type") ?? ""
    }

    public var runId: String { string("run_id") ?? string("runId") ?? "" }
    public var sessionKey: String { string("session_key") ?? string("sessionKey") ?? "" }
    public var agentId: String { string("agent_id") ?? string("agentId") ?? "" }
    public var kind: String { string("kind") ?? "" }
    public var message: String { string("message") ?? "" }
    public var status: String { string("status") ?? "" }
    public var evidenceKind: String { string("evidence_kind") ?? string("evidenceKind") ?? "" }
    public var verification: String { string("verification") ?? "" }
    public var toolCallCount: Int { int("tool_call_count") ?? int("toolCallCount") ?? 0 }
    public var isUnverified: Bool { status == "unverified" || verification == "unverified" }
    public var callId: String { string("call_id") ?? string("callId") ?? "" }
    public var name: String { string("name") ?? "" }
    public var arguments: String { string("arguments") ?? "" }
    public var argumentsDelta: String { string("arguments_delta") ?? string("argumentsDelta") ?? "" }
    public var argumentsSoFar: String { string("arguments_so_far") ?? string("argumentsSoFar") ?? "" }
    public var output: String { string("output") ?? "" }
    public var isError: Bool { bool("is_error") ?? bool("isError") ?? false }
    public var content: String { string("content") ?? "" }
    public var fromAgent: String { string("from_agent") ?? string("fromAgent") ?? "" }
    public var toAgent: String { string("to_agent") ?? string("toAgent") ?? "" }
    public var groupId: String { string("group_id") ?? string("groupId") ?? "" }
    public var task: String { string("task") ?? "" }
    public var result: String { string("result") ?? "" }
    public var dataUrl: String { string("data_url") ?? string("dataUrl") ?? "" }
    public var path: String? { string("path") }
    public var stream: String { string("stream") ?? "" }
    public var question: String { string("question") ?? "" }
    public var requestId: String { string("request_id") ?? string("requestId") ?? "" }
    public var options: [String] { stringArray("options") }
    public var context: String? { string("context") }
    public var response: String { string("response") ?? "" }
    public var usagePercent: Double { number("usage_percent") ?? number("usagePercent") ?? 0 }
    public var strategy: String { string("strategy") ?? "" }
    public var turnsRemoved: Int { int("turns_removed") ?? int("turnsRemoved") ?? 0 }
    public var tokensBefore: Int { int("tokens_before") ?? int("tokensBefore") ?? 0 }
    public var tokensAfter: Int { int("tokens_after") ?? int("tokensAfter") ?? 0 }
    public var target: String { string("target") ?? "" }
    public var skillName: String { string("skill_name") ?? string("skillName") ?? "" }
    public var action: String { string("action") ?? "" }
    public var summary: String { string("summary") ?? "" }
    public var reviewTypes: [String] {
        let snakeCase = stringArray("review_types")
        return snakeCase.isEmpty ? stringArray("reviewTypes") : snakeCase
    }
    public var evolutionQueuedRuns: [NapaxiEvolutionQueuedRun] {
        objectArray("runs").map(NapaxiEvolutionQueuedRun.init(raw:))
    }
    public var runIds: [String] {
        evolutionQueuedRuns.map(\.id)
    }
    public var activatedSkills: [NapaxiActivatedSkillInfo] {
        objectArray("skills").map(NapaxiActivatedSkillInfo.init(raw:))
    }
    public var providerId: String { string("provider_id") ?? string("providerId") ?? "" }
    public var actionId: String { string("action_id") ?? string("actionId") ?? "" }
    public var toolName: String { string("tool_name") ?? string("toolName") ?? string("name") ?? "" }
    public var risk: String { string("risk") ?? "" }
    public var expiresAt: String { string("expires_at") ?? string("expiresAt") ?? "" }
    public var mode: String { string("mode") ?? "" }
    public var providerTraceId: String? { string("provider_trace_id") ?? string("providerTraceId") }
    /// Reason an in-flight LLM stream dropped/stalled and is being retried.
    /// Present on `stream_reset` events. The UI should discard any partial
    /// assistant content/reasoning for the current turn and await the
    /// reconnected stream; no history side effects have occurred yet.
    public var reason: String { string("reason") ?? "" }

    public func string(_ key: String) -> String? {
        return object[key]?.stringValue
    }

    public func bool(_ key: String) -> Bool? {
        object[key]?.boolValue
    }

    public func number(_ key: String) -> Double? {
        object[key]?.numberValue
    }

    public func int(_ key: String) -> Int? {
        guard case .number(let value)? = object[key], value.isFinite else { return nil }
        let integer = value.rounded(.towardZero)
        guard integer == value else { return nil }
        return Int(integer)
    }

    public func stringArray(_ key: String) -> [String] {
        guard case .array(let values)? = object[key] else {
            return []
        }
        return values.compactMap(\.stringValue)
    }

    public func objectArray(_ key: String) -> [[String: NapaxiJSONValue]] {
        guard case .array(let values)? = object[key] else {
            return []
        }
        return values.compactMap { value in
            guard case .object(let object) = value else { return nil }
            return object
        }
    }

    public func jsonString() throws -> String {
        try NapaxiRawJSON(raw).jsonString()
    }
}

func validateChatEventObject(_ object: [String: NapaxiJSONValue]) throws {
    let type = try object.requiredChatEventString("type")
    switch type {
    case "run_started":
        try object.requireChatEventStrings("run_id", "session_key", "agent_id")
    case "run_progress":
        try object.requireChatEventStrings("run_id", "kind", "message")
    case "run_completed":
        try object.requireChatEventStrings("run_id", "status", "evidence_kind", "verification")
        try object.validateChatEventOptionalInt("tool_call_count")
    case "tool_call":
        try object.requireChatEventStrings("call_id", "name", "arguments")
    case "tool_call_delta":
        try object.requireChatEventStrings("call_id", "name", "arguments_delta", "arguments_so_far")
    case "tool_result":
        try object.requireChatEventStrings("call_id", "name", "output")
        try object.validateChatEventRequiredBool("is_error")
    case "response", "response_delta", "reasoning_delta", "thinking":
        _ = try object.requiredChatEventString("content")
    case "error":
        _ = try object.requiredChatEventString("message")
    case "agent_delegation":
        try object.requireChatEventStrings("from_agent", "to_agent", "message")
    case "agent_delegation_result":
        try object.requireChatEventStrings("from_agent", "to_agent", "content")
        try object.validateChatEventRequiredBool("is_error")
    case "agent_tool_call":
        try object.requireChatEventStrings("call_id", "name", "arguments", "agent_id")
    case "agent_tool_call_delta":
        try object.requireChatEventStrings("call_id", "name", "arguments_delta", "arguments_so_far", "agent_id")
    case "agent_tool_result":
        try object.requireChatEventStrings("call_id", "name", "output", "agent_id")
        try object.validateChatEventRequiredBool("is_error")
    case "group_delegation":
        try object.requireChatEventStrings("group_id", "from_agent", "to_agent", "task")
    case "group_delegation_result":
        try object.requireChatEventStrings("group_id", "from_agent", "to_agent", "result")
        try object.validateChatEventRequiredBool("is_error")
    case "image_generated":
        _ = try object.requiredChatEventString("data_url")
        try object.validateChatEventOptionalString("path")
    case "tool_output_chunk":
        try object.requireChatEventStrings("call_id", "content", "stream")
    case "message_injected":
        _ = try object.requiredChatEventString("content")
    case "asking_human":
        try object.requireChatEventStrings("question", "request_id")
        try object.validateChatEventOptionalStringArray("options")
        try object.validateChatEventOptionalString("context")
    case "human_response":
        try object.requireChatEventStrings("request_id", "response")
    case "context_compacting":
        try object.validateChatEventRequiredNumber("usage_percent")
        _ = try object.requiredChatEventString("strategy")
    case "context_compacted":
        try object.requireChatEventInts("turns_removed", "tokens_before", "tokens_after")
    case "memory_evolved":
        try object.requireChatEventStrings("target", "content")
    case "skill_evolved":
        try object.requireChatEventStrings("skill_name", "action", "summary")
    case "evolution_queued":
        try object.validateChatEventOptionalStringArray("review_types")
        try object.validateEvolutionQueuedRuns()
    case "skill_activated":
        try object.validateChatEventOptionalString("agent_id")
        try object.validateActivatedSkillInfos()
    case "action_proposal_created":
        try object.requireChatEventStrings("request_id", "provider_id", "agent_id", "action_id", "tool_name", "risk", "expires_at")
    case "action_handoff_started":
        try object.requireChatEventStrings("request_id", "mode")
    case "action_waiting_for_provider":
        try object.requireChatEventStrings("request_id", "provider_id")
    case "action_result_received":
        try object.requireChatEventStrings("request_id", "status")
        try object.validateChatEventOptionalString("provider_trace_id")
    case "action_expired":
        _ = try object.requiredChatEventString("request_id")
    case "action_failed":
        try object.requireChatEventStrings("request_id", "message")
    case "interrupted":
        break
    case "stream_reset":
        try object.validateChatEventOptionalString("reason")
    default:
        break
    }
}

func decodeChatEventsFromValue(
    _ value: NapaxiJSONValue,
    expectedArrayMessage: String,
    propagatingJSONError: Bool = false
) throws -> [NapaxiChatEvent] {
    if propagatingJSONError {
        try throwIfJsonError(value)
    }
    do {
        return try decodeJsonObjectListFromValue(value) { object in
            try validateChatEventObject(object)
            return NapaxiChatEvent(map: object)
        }
    } catch NapaxiError.invalidJSON("Expected a JSON array") {
        throw NapaxiError.invalidJSON(expectedArrayMessage)
    }
}

public struct NapaxiEvolutionQueuedRun: Codable, Equatable, Sendable {
    public var id: String
    public var reviewType: String

    public init(id: String, reviewType: String) {
        self.id = id
        self.reviewType = reviewType
    }

    public init(raw: [String: NapaxiJSONValue]) {
        self.init(
            id: raw["id"]?.stringValue ?? "",
            reviewType: raw["review_type"]?.stringValue ?? raw["reviewType"]?.stringValue ?? ""
        )
    }
}

public struct NapaxiActivatedSkillInfo: Codable, Equatable, Sendable {
    public var name: String
    public var version: String
    public var description: String
    public var trust: String
    public var reason: String

    public init(
        name: String,
        version: String = "",
        description: String = "",
        trust: String = "",
        reason: String = ""
    ) {
        self.name = name
        self.version = version
        self.description = description
        self.trust = trust
        self.reason = reason
    }

    public init(raw: [String: NapaxiJSONValue]) {
        self.init(
            name: raw["name"]?.stringValue ?? "",
            version: raw["version"]?.stringValue ?? "",
            description: raw["description"]?.stringValue ?? "",
            trust: raw["trust"]?.stringValue ?? "",
            reason: raw["reason"]?.stringValue ?? ""
        )
    }
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func requiredChatEventString(_ key: String) throws -> String {
        guard case .string(let value)? = self[key] else {
            throw NapaxiError.invalidJSON("Expected chat event field '\(key)' to be a string")
        }
        return value
    }

    func requireChatEventStrings(_ keys: String...) throws {
        for key in keys {
            _ = try requiredChatEventString(key)
        }
    }

    func requireChatEventInts(_ keys: String...) throws {
        for key in keys {
            try validateChatEventRequiredInt(key)
        }
    }

    func validateChatEventOptionalString(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("Expected chat event field '\(key)' to be a string")
        }
    }

    func validateChatEventRequiredBool(_ key: String) throws {
        guard case .bool = self[key] else {
            throw NapaxiError.invalidJSON("Expected chat event field '\(key)' to be a bool")
        }
    }

    func validateChatEventRequiredNumber(_ key: String) throws {
        guard case .number(let value)? = self[key], value.isFinite else {
            throw NapaxiError.invalidJSON("Expected chat event field '\(key)' to be a number")
        }
    }

    func validateChatEventRequiredInt(_ key: String) throws {
        guard let value = self[key] else {
            throw NapaxiError.invalidJSON("Expected chat event field '\(key)' to be an integer")
        }
        try validateChatEventIntegerValue(value, key: key)
    }

    func validateChatEventOptionalInt(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        try validateChatEventIntegerValue(value, key: key)
    }

    func validateChatEventOptionalStringArray(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("Expected chat event field '\(key)' to be an array")
        }
        for item in values {
            guard case .string = item else {
                throw NapaxiError.invalidJSON("Expected chat event field '\(key)' to contain strings")
            }
        }
    }

    func validateEvolutionQueuedRuns() throws {
        guard let value = self["runs"], value != .null else { return }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("Expected chat event field 'runs' to be an array")
        }
        for item in values {
            guard case .object(let run) = item else { continue }
            _ = try run.requiredChatEventString("id")
            _ = try run.requiredChatEventString("review_type")
        }
    }

    func validateActivatedSkillInfos() throws {
        guard let value = self["skills"], value != .null else { return }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("Expected chat event field 'skills' to be an array")
        }
        for item in values {
            guard case .object(let skill) = item else { continue }
            try skill.validateChatEventOptionalString("name")
            try skill.validateChatEventOptionalString("version")
            try skill.validateChatEventOptionalString("description")
            try skill.validateChatEventOptionalString("trust")
            try skill.validateChatEventOptionalString("reason")
        }
    }

    private func validateChatEventIntegerValue(_ value: NapaxiJSONValue, key: String) throws {
        guard case .number(let number) = value,
              number.isFinite,
              number.rounded(.towardZero) == number
        else {
            throw NapaxiError.invalidJSON("Expected chat event field '\(key)' to be an integer")
        }
    }
}

public struct NapaxiAPIEnvelope: Codable, Equatable, Sendable {
    public struct NativeError: Codable, Equatable, Sendable {
        public var code: String
        public var message: String
    }

    public var ok: Bool
    public var value: NapaxiJSONValue?
    public var error: NativeError?
}
