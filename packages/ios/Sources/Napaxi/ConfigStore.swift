import Foundation
#if canImport(Security)
import Security
#endif

public struct NapaxiConfigProfile: Codable, Equatable, Sendable {
    public static let defaultMaxTokens = 40_960

    public var id: String
    public var name: String
    public var provider: String
    public var model: String
    public var baseUrl: String?
    public var systemPrompt: String
    public var maxTokens: Int
    public var maxToolIterations: Int
    public var extraHeaders: String?
    public var userTimezone: String?
    public var allowedModels: [[String: String]]?
    public var imageModel: String?
    public var imageAnalysisModel: String?
    public var videoModel: String?
    public var audioModel: String?
    public var contextEngine: NapaxiContextEngineConfig
    public var shellSecurity: NapaxiShellSecurityConfig
    public var metadata: [String: NapaxiJSONValue]

    public init(
        id: String,
        name: String,
        provider: String,
        model: String,
        baseUrl: String? = nil,
        systemPrompt: String = "",
        maxTokens: Int = NapaxiConfigProfile.defaultMaxTokens,
        maxToolIterations: Int = 50,
        extraHeaders: String? = nil,
        userTimezone: String? = nil,
        allowedModels: [[String: String]]? = nil,
        imageModel: String? = nil,
        imageAnalysisModel: String? = nil,
        videoModel: String? = nil,
        audioModel: String? = nil,
        contextEngine: NapaxiContextEngineConfig = NapaxiContextEngineConfig(),
        shellSecurity: NapaxiShellSecurityConfig = NapaxiShellSecurityConfig(),
        metadata: [String: NapaxiJSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.model = model
        self.baseUrl = baseUrl
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
        self.maxToolIterations = maxToolIterations
        self.extraHeaders = extraHeaders
        self.userTimezone = userTimezone
        self.allowedModels = allowedModels
        self.imageModel = imageModel
        self.imageAnalysisModel = imageAnalysisModel
        self.videoModel = videoModel
        self.audioModel = audioModel
        self.contextEngine = contextEngine
        self.shellSecurity = shellSecurity
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case provider
        case model
        case baseUrl = "base_url"
        case systemPrompt = "system_prompt"
        case maxTokens = "max_tokens"
        case maxToolIterations = "max_tool_iterations"
        case extraHeaders = "extra_headers"
        case userTimezone = "user_timezone"
        case allowedModels = "allowed_models"
        case imageModel = "image_model"
        case imageAnalysisModel = "image_analysis_model"
        case videoModel = "video_model"
        case audioModel = "audio_model"
        case contextEngine = "context_engine"
        case shellSecurity = "shell_security"
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            provider: try container.decodeIfPresent(String.self, forKey: .provider) ?? "",
            model: try container.decodeIfPresent(String.self, forKey: .model) ?? "",
            baseUrl: try container.decodeIfPresent(String.self, forKey: .baseUrl),
            systemPrompt: try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? "",
            maxTokens: try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? Self.defaultMaxTokens,
            maxToolIterations: try container.decodeIfPresent(Int.self, forKey: .maxToolIterations) ?? 50,
            extraHeaders: try container.decodeIfPresent(String.self, forKey: .extraHeaders),
            userTimezone: try container.decodeIfPresent(String.self, forKey: .userTimezone),
            allowedModels: try container.decodeIfPresent([[String: String]].self, forKey: .allowedModels),
            imageModel: try container.decodeIfPresent(String.self, forKey: .imageModel),
            imageAnalysisModel: try container.decodeIfPresent(String.self, forKey: .imageAnalysisModel),
            videoModel: try container.decodeIfPresent(String.self, forKey: .videoModel),
            audioModel: try container.decodeIfPresent(String.self, forKey: .audioModel),
            contextEngine: try container.decodeIfPresent(NapaxiContextEngineConfig.self, forKey: .contextEngine) ?? NapaxiContextEngineConfig(),
            shellSecurity: try container.decodeIfPresent(NapaxiShellSecurityConfig.self, forKey: .shellSecurity) ?? NapaxiShellSecurityConfig(),
            metadata: try container.decodeIfPresent([String: NapaxiJSONValue].self, forKey: .metadata) ?? [:]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NapaxiJSONValue.object(toMap()))
    }

    public func toConfig(apiKey: String) -> NapaxiConfig {
        return NapaxiConfig(
            provider: provider,
            apiKey: apiKey,
            model: model,
            baseUrl: baseUrl,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            maxToolIterations: maxToolIterations,
            extraHeaders: extraHeaders,
            userTimezone: userTimezone,
            allowedModels: allowedModels,
            imageModel: imageModel,
            imageAnalysisModel: imageAnalysisModel,
            videoModel: videoModel,
            audioModel: audioModel,
            contextEngine: contextEngine,
            shellSecurity: shellSecurity
        )
    }

    public init(map: [String: NapaxiJSONValue]) {
        self.init(
            id: map["id"]?.stringValue ?? "",
            name: map["name"]?.stringValue ?? "",
            provider: map["provider"]?.stringValue ?? "",
            model: map["model"]?.stringValue ?? "",
            baseUrl: map["base_url"]?.stringValue,
            systemPrompt: map["system_prompt"]?.stringValue ?? "",
            maxTokens: map.configInt("max_tokens") ?? Self.defaultMaxTokens,
            maxToolIterations: map.configInt("max_tool_iterations") ?? 50,
            extraHeaders: map["extra_headers"]?.stringValue,
            userTimezone: map["user_timezone"]?.stringValue ?? map["userTimeZone"]?.stringValue ?? map["timeZoneId"]?.stringValue,
            allowedModels: Self.stringMapArray(from: map["allowed_models"]),
            imageModel: map["image_model"]?.stringValue,
            imageAnalysisModel: map["image_analysis_model"]?.stringValue,
            videoModel: map["video_model"]?.stringValue,
            audioModel: map["audio_model"]?.stringValue,
            contextEngine: NapaxiContextEngineConfig.fromMap(map["context_engine"]?.objectValue ?? [:]),
            shellSecurity: NapaxiShellSecurityConfig.fromMap(map["shell_security"]?.objectValue ?? [:]),
            metadata: map["metadata"]?.objectValue ?? [:]
        )
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> NapaxiConfigProfile {
        NapaxiConfigProfile(map: map)
    }

    static func fromFlutterPersistedMap(_ map: [String: NapaxiJSONValue]) throws -> NapaxiConfigProfile {
        var profile = NapaxiConfigProfile(map: map)
        profile.allowedModels = try flutterStringMapArray(from: map["allowed_models"], field: "allowed_models")
        return profile
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        var map: [String: NapaxiJSONValue] = [
            "id": .string(id),
            "name": .string(name),
            "provider": .string(provider),
            "base_url": baseUrl.map(NapaxiJSONValue.string) ?? .null,
            "model": .string(model),
            "max_tokens": .number(Double(maxTokens)),
            "max_tool_iterations": .number(Double(maxToolIterations)),
            "extra_headers": extraHeaders.map(NapaxiJSONValue.string) ?? .null,
        ]
        if let userTimezone, !userTimezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            map["user_timezone"] = .string(userTimezone)
        }
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            map["system_prompt"] = .string(systemPrompt)
        }
        if let allowedModels {
            map["allowed_models"] = .array(allowedModels.map { .object($0.mapValues { .string($0) }) })
        }
        if let imageModel {
            map["image_model"] = .string(imageModel)
        }
        if let imageAnalysisModel {
            map["image_analysis_model"] = .string(imageAnalysisModel)
        }
        if let videoModel {
            map["video_model"] = .string(videoModel)
        }
        if let audioModel {
            map["audio_model"] = .string(audioModel)
        }
        map["context_engine"] = .object(contextEngine.toMap())
        map["shell_security"] = .object(shellSecurity.toMap())
        if !metadata.isEmpty {
            map["metadata"] = .object(metadata)
        }
        return map
    }

    private static func stringMapArray(from value: NapaxiJSONValue?) -> [[String: String]]? {
        guard case .array(let values)? = value else { return nil }
        return values.compactMap { item in
            guard case .object(let object) = item else { return nil }
            return object.mapValues { $0.stringValue ?? "" }
        }
    }

    private static func flutterStringMapArray(from value: NapaxiJSONValue?, field: String) throws -> [[String: String]]? {
        guard let value, value != .null else { return nil }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("\(field) must be a JSON array")
        }
        return try values.map { item in
            guard case .object(let object) = item else {
                throw NapaxiError.invalidJSON("\(field) entries must be JSON objects")
            }
            return try object.mapValues { value in
                guard let string = value.stringValue else {
                    throw NapaxiError.invalidJSON("\(field) values must be strings")
                }
                return string
            }
        }
    }
}

public struct NapaxiConfigSelection: Codable, Equatable, Sendable {
    public var selectedProfileId: String?
    public var selectedProfileIdByCapability: [String: String]
    public var systemPrompt: String
    public var maxToolIterations: Int

    public init(
        selectedProfileId: String? = nil,
        selectedProfileIdByCapability: [String: String] = [:],
        systemPrompt: String = "",
        maxToolIterations: Int = 50
    ) {
        self.selectedProfileId = selectedProfileId
        self.selectedProfileIdByCapability = selectedProfileIdByCapability
        self.systemPrompt = systemPrompt
        self.maxToolIterations = maxToolIterations
    }

    enum CodingKeys: String, CodingKey {
        case selectedProfileId = "selected_profile_id"
        case selectedProfileIdByCapability = "selected_profile_id_by_capability"
        case systemPrompt = "system_prompt"
        case maxToolIterations = "max_tool_iterations"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NapaxiJSONValue.object(toMap()))
    }

    public init(map: [String: NapaxiJSONValue]) {
        self.init(
            selectedProfileId: map["selected_profile_id"]?.stringValue,
            selectedProfileIdByCapability: map["selected_profile_id_by_capability"]?.stringMapValue ?? [:],
            systemPrompt: map["system_prompt"]?.stringValue ?? "",
            maxToolIterations: map.configInt("max_tool_iterations") ?? 50
        )
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> NapaxiConfigSelection {
        NapaxiConfigSelection(map: map)
    }

    static func fromFlutterPersistedMap(_ map: [String: NapaxiJSONValue]) throws -> NapaxiConfigSelection {
        var selection = NapaxiConfigSelection(map: map)
        selection.selectedProfileIdByCapability = try flutterStringMap(
            from: map["selected_profile_id_by_capability"],
            field: "selected_profile_id_by_capability"
        ) ?? [:]
        return selection
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        [
            "selected_profile_id": selectedProfileId.map(NapaxiJSONValue.string) ?? .null,
            "selected_profile_id_by_capability": .object(selectedProfileIdByCapability.mapValues { .string($0) }),
            "system_prompt": .string(systemPrompt),
            "max_tool_iterations": .number(Double(maxToolIterations)),
        ]
    }

    private static func flutterStringMap(from value: NapaxiJSONValue?, field: String) throws -> [String: String]? {
        guard let value, value != .null else { return nil }
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("\(field) must be a JSON object")
        }
        return try object.mapValues { value in
            guard let string = value.stringValue else {
                throw NapaxiError.invalidJSON("\(field) values must be strings")
            }
            return string
        }
    }
}

public protocol NapaxiConfigKeyValueStore: Sendable {
    func read(_ key: String) async throws -> String?
    func write(_ key: String, value: String) async throws
    func delete(_ key: String) async throws
}

public protocol NapaxiConfigSecretStore: Sendable {
    func read(_ key: String) async throws -> String?
    func write(_ key: String, value: String) async throws
    func delete(_ key: String) async throws
}

public final class NapaxiMemoryConfigStore: NapaxiConfigKeyValueStore, NapaxiConfigSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var values: [String: String] = [:]

    public init() {}

    public func read(_ key: String) async throws -> String? {
        withValues { $0[key] }
    }

    public func write(_ key: String, value: String) async throws {
        withValues { $0[key] = value }
    }

    public func delete(_ key: String) async throws {
        _ = withValues { $0.removeValue(forKey: key) }
    }

    private func withValues<T>(_ body: (inout [String: String]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&values)
    }
}

public final class NapaxiUserDefaultsConfigKeyValueStore: NapaxiConfigKeyValueStore, @unchecked Sendable {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func read(_ key: String) async throws -> String? {
        userDefaults.string(forKey: key)
    }

    public func write(_ key: String, value: String) async throws {
        userDefaults.set(value, forKey: key)
    }

    public func delete(_ key: String) async throws {
        userDefaults.removeObject(forKey: key)
    }
}

#if canImport(Security)
public final class NapaxiKeychainConfigSecretStore: NapaxiConfigSecretStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "dev.napaxi.config") {
        self.service = service
    }

    public func read(_ key: String) async throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw NapaxiError.nativeError(code: "keychain_read_failed", message: "Keychain read failed: \(status)")
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ key: String, value: String) async throws {
        try await delete(key)
        var query = baseQuery(key)
        query[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NapaxiError.nativeError(code: "keychain_write_failed", message: "Keychain write failed: \(status)")
        }
    }

    public func delete(_ key: String) async throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NapaxiError.nativeError(code: "keychain_delete_failed", message: "Keychain delete failed: \(status)")
        }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
#endif

public final class NapaxiConfigStore: @unchecked Sendable {
    public static let profilesKey = "napaxi.config.profiles.v1"
    public static let selectionKey = "napaxi.config.selection.v1"
    public static let apiKeyPrefix = "napaxi.config.api_key."

    public static let instance = NapaxiConfigStore(
        keyValueStore: NapaxiUserDefaultsConfigKeyValueStore(),
        secretStore: defaultSecretStore()
    )

    private let keyValueStore: NapaxiConfigKeyValueStore
    private let secretStore: NapaxiConfigSecretStore

    public init(
        keyValueStore: NapaxiConfigKeyValueStore,
        secretStore: NapaxiConfigSecretStore
    ) {
        self.keyValueStore = keyValueStore
        self.secretStore = secretStore
    }

    public static func memory() -> NapaxiConfigStore {
        let store = NapaxiMemoryConfigStore()
        return NapaxiConfigStore(keyValueStore: store, secretStore: store)
    }

    public func loadProfiles() async throws -> [NapaxiConfigProfile] {
        guard let raw = try await keyValueStore.read(Self.profilesKey),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        guard case .array(let values) = try NapaxiRawJSON(jsonString: raw).value else {
            return []
        }
        return try values.compactMap { value in
            guard let object = value.objectValue else { return nil }
            let profile = try NapaxiConfigProfile.fromFlutterPersistedMap(object)
            return profile.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : profile
        }
    }

    public func saveProfile(_ profile: NapaxiConfigProfile, apiKey: String? = nil) async throws {
        let profiles = try await loadProfiles()
        let nextProfiles = profiles.filter { $0.id != profile.id } + [profile]
        try await saveProfiles(nextProfiles)
        if let apiKey {
            if apiKey.isEmpty {
                try await secretStore.delete(apiKeyKey(profile.id))
            } else {
                try await secretStore.write(apiKeyKey(profile.id), value: apiKey)
            }
        }
    }

    public func deleteProfile(_ profileId: String) async throws {
        let existingProfiles = try await loadProfiles()
        let profiles = existingProfiles.filter { $0.id != profileId }
        try await saveProfiles(profiles)
        try await secretStore.delete(apiKeyKey(profileId))
        let selection = try await loadSelection()
        let nextCapabilitySelection = selection.selectedProfileIdByCapability.filter { $0.value != profileId }
        try await saveSelection(NapaxiConfigSelection(
            selectedProfileId: selection.selectedProfileId == profileId ? nil : selection.selectedProfileId,
            selectedProfileIdByCapability: nextCapabilitySelection,
            systemPrompt: selection.systemPrompt,
            maxToolIterations: selection.maxToolIterations
        ))
    }

    public func loadSelection() async throws -> NapaxiConfigSelection {
        let profiles = try await loadProfiles()
        let profileIds = Set(profiles.map(\.id))
        guard let raw = try await keyValueStore.read(Self.selectionKey),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NapaxiConfigSelection()
        }
        guard let object = try NapaxiRawJSON(jsonString: raw).value.objectValue else {
            return NapaxiConfigSelection()
        }
        let selection = try NapaxiConfigSelection.fromFlutterPersistedMap(object)
        return normalizeSelection(selection, profileIds: profileIds)
    }

    public func saveSelection(_ selection: NapaxiConfigSelection) async throws {
        let profiles = try await loadProfiles()
        let profileIds = Set(profiles.map(\.id))
        let normalized = normalizeSelection(selection, profileIds: profileIds)
        try await keyValueStore.write(Self.selectionKey, value: NapaxiRawJSON(.object(normalized.toMap())).jsonString())
    }

    public func resolveConfig(_ profileId: String) async throws -> NapaxiConfig? {
        guard let profile = try await loadProfiles().first(where: { $0.id == profileId }) else {
            return nil
        }
        let apiKey = (try? await secretStore.read(apiKeyKey(profileId))) ?? ""
        return profile.toConfig(apiKey: apiKey)
    }

    public func readApiKey(_ profileId: String) async -> String {
        (try? await secretStore.read(apiKeyKey(profileId))) ?? ""
    }

    private func saveProfiles(_ profiles: [NapaxiConfigProfile]) async throws {
        let value = NapaxiJSONValue.array(profiles.map { .object($0.toMap()) })
        try await keyValueStore.write(Self.profilesKey, value: NapaxiRawJSON(value).jsonString())
    }

    private func normalizeSelection(_ selection: NapaxiConfigSelection, profileIds: Set<String>) -> NapaxiConfigSelection {
        NapaxiConfigSelection(
            selectedProfileId: profileIds.contains(selection.selectedProfileId ?? "") ? selection.selectedProfileId : nil,
            selectedProfileIdByCapability: selection.selectedProfileIdByCapability.filter { profileIds.contains($0.value) },
            systemPrompt: selection.systemPrompt,
            maxToolIterations: selection.maxToolIterations
        )
    }

    private func apiKeyKey(_ profileId: String) -> String {
        "\(Self.apiKeyPrefix)\(profileId)"
    }
}

private func defaultSecretStore() -> NapaxiConfigSecretStore {
    #if canImport(Security)
    return NapaxiKeychainConfigSecretStore()
    #else
    return NapaxiMemoryConfigStore()
    #endif
}

private extension NapaxiJSONValue {
    var stringMapValue: [String: String]? {
        guard case .object(let object) = self else { return nil }
        return object.mapValues { $0.stringValue ?? "" }
    }
}
