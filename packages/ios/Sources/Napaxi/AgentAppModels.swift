import Foundation

public extension NapaxiStableModel {
    func jsonString() throws -> String {
        try raw.jsonString()
    }
}

public extension NapaxiStableModel where Tag == NapaxiAgentAppActionManifestTag {
    init(
        actionId: String,
        toolName: String,
        description: String,
        parameters: [String: NapaxiJSONValue] = ["type": .string("object"), "properties": .object([:])],
        resultSchema: [String: NapaxiJSONValue] = ["type": .string("object")],
        risk: String = "high",
        confirmationPolicy: String = "provider_required",
        executionModes: [String] = [],
        timeoutSeconds: Int = 600
    ) {
        self.init(raw: [
            "action_id": .string(actionId),
            "tool_name": .string(toolName),
            "description": .string(description),
            "parameters": .object(parameters),
            "result_schema": .object(resultSchema),
            "risk": .string(risk),
            "confirmation_policy": .string(confirmationPolicy),
            "execution_modes": .array(executionModes.map { .string($0) }),
            "timeout_seconds": .number(Double(timeoutSeconds)),
        ])
    }

    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            actionId: map.string("action_id") ?? "",
            toolName: map.string("tool_name") ?? "",
            description: map.string("description") ?? "",
            parameters: map.object("parameters") ?? ["type": .string("object"), "properties": .object([:])],
            resultSchema: map.object("result_schema") ?? ["type": .string("object")],
            risk: map.string("risk") ?? "high",
            confirmationPolicy: map.string("confirmation_policy") ?? "provider_required",
            executionModes: map.stringArray("execution_modes") ?? [],
            timeoutSeconds: map.int("timeout_seconds") ?? 600
        )
    }

    func toJson() -> [String: NapaxiJSONValue] {
        [
            "action_id": .string(actionId),
            "tool_name": .string(toolName),
            "description": .string(description),
            "parameters": .object(parameters),
            "result_schema": .object(resultSchema),
            "risk": .string(risk),
            "confirmation_policy": .string(confirmationPolicy),
            "execution_modes": .array(executionModes.map { .string($0) }),
            "timeout_seconds": .number(Double(timeoutSeconds)),
        ]
    }

    var actionId: String { string("action_id") ?? string("actionId") ?? "" }
    var toolName: String { string("tool_name") ?? string("toolName") ?? "" }
    var description: String { string("description") ?? "" }
    var parameters: [String: NapaxiJSONValue] { raw.object("parameters") ?? ["type": .string("object"), "properties": .object([:])] }
    var resultSchema: [String: NapaxiJSONValue] { raw.object("result_schema") ?? raw.object("resultSchema") ?? ["type": .string("object")] }
    var risk: String { string("risk") ?? "high" }
    var confirmationPolicy: String { string("confirmation_policy") ?? string("confirmationPolicy") ?? "provider_required" }
    var executionModes: [String] { raw.stringArray("execution_modes") ?? raw.stringArray("executionModes") ?? [] }
    var timeoutSeconds: Int { raw.int("timeout_seconds") ?? raw.int("timeoutSeconds") ?? 600 }
}

public extension NapaxiStableModel where Tag == NapaxiAgentAppInstallBindingTag {
    init(
        platform: String,
        appPackageName: String,
        activityName: String,
        signingCertSha256: String,
        installedAt: String,
        installRequestId: String,
        protocolVersion: Int,
        hostPackageName: String = "",
        hostSigningCertSha256: String = "",
        hostInstanceId: String = "",
        hostSharedSecret: String = "",
        iosBundleId: String = "",
        iosTeamId: String = "",
        installUrl: String = "",
        actionUrl: String = "",
        universalLinkDomain: String = "",
        hostBundleId: String = "",
        hostTeamId: String = "",
        hostCallbackScheme: String = "",
        backgroundTriggerSupported: Bool = false,
        hostBackgroundTriggerService: String = ""
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "platform": .string(platform),
            "app_package_name": .string(appPackageName),
            "activity_name": .string(activityName),
            "signing_cert_sha256": .string(signingCertSha256),
            "installed_at": .string(installedAt),
            "install_request_id": .string(installRequestId),
            "protocol_version": .number(Double(protocolVersion)),
        ]
        raw.setNonEmpty("host_package_name", hostPackageName)
        raw.setNonEmpty("host_signing_cert_sha256", hostSigningCertSha256)
        raw.setNonEmpty("host_instance_id", hostInstanceId)
        raw.setNonEmpty("host_shared_secret", hostSharedSecret)
        raw.setNonEmpty("ios_bundle_id", iosBundleId)
        raw.setNonEmpty("ios_team_id", iosTeamId)
        raw.setNonEmpty("install_url", installUrl)
        raw.setNonEmpty("action_url", actionUrl)
        raw.setNonEmpty("universal_link_domain", universalLinkDomain)
        raw.setNonEmpty("host_bundle_id", hostBundleId)
        raw.setNonEmpty("host_team_id", hostTeamId)
        raw.setNonEmpty("host_callback_scheme", hostCallbackScheme)
        if backgroundTriggerSupported { raw["background_trigger_supported"] = .bool(true) }
        raw.setNonEmpty("host_background_trigger_service", hostBackgroundTriggerService)
        self.init(raw: raw)
    }

    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            platform: map.string("platform") ?? "",
            appPackageName: map.string("app_package_name") ?? "",
            activityName: map.string("activity_name") ?? "",
            signingCertSha256: map.string("signing_cert_sha256") ?? "",
            installedAt: map.string("installed_at") ?? "",
            installRequestId: map.string("install_request_id") ?? "",
            protocolVersion: map.int("protocol_version") ?? 1,
            hostPackageName: map.string("host_package_name") ?? "",
            hostSigningCertSha256: map.string("host_signing_cert_sha256") ?? "",
            hostInstanceId: map.string("host_instance_id") ?? "",
            hostSharedSecret: map.string("host_shared_secret") ?? "",
            iosBundleId: map.string("ios_bundle_id") ?? "",
            iosTeamId: map.string("ios_team_id") ?? "",
            installUrl: map.string("install_url") ?? "",
            actionUrl: map.string("action_url") ?? "",
            universalLinkDomain: map.string("universal_link_domain") ?? "",
            hostBundleId: map.string("host_bundle_id") ?? "",
            hostTeamId: map.string("host_team_id") ?? "",
            hostCallbackScheme: map.string("host_callback_scheme") ?? "",
            backgroundTriggerSupported: map.bool("background_trigger_supported") ?? false,
            hostBackgroundTriggerService: map.string("host_background_trigger_service") ?? ""
        )
    }

    func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "platform": .string(platform),
            "app_package_name": .string(appPackageName),
            "activity_name": .string(activityName),
            "signing_cert_sha256": .string(signingCertSha256),
            "installed_at": .string(installedAt),
            "install_request_id": .string(installRequestId),
            "protocol_version": .number(Double(protocolVersion)),
        ]
        object.setNonEmpty("host_package_name", hostPackageName)
        object.setNonEmpty("host_signing_cert_sha256", hostSigningCertSha256)
        object.setNonEmpty("host_instance_id", hostInstanceId)
        object.setNonEmpty("host_shared_secret", hostSharedSecret)
        object.setNonEmpty("ios_bundle_id", iosBundleId)
        object.setNonEmpty("ios_team_id", iosTeamId)
        object.setNonEmpty("install_url", installUrl)
        object.setNonEmpty("action_url", actionUrl)
        object.setNonEmpty("universal_link_domain", universalLinkDomain)
        object.setNonEmpty("host_bundle_id", hostBundleId)
        object.setNonEmpty("host_team_id", hostTeamId)
        object.setNonEmpty("host_callback_scheme", hostCallbackScheme)
        if backgroundTriggerSupported { object["background_trigger_supported"] = .bool(true) }
        object.setNonEmpty("host_background_trigger_service", hostBackgroundTriggerService)
        return object
    }

    var platform: String { string("platform") ?? "" }
    var appPackageName: String { string("app_package_name") ?? string("appPackageName") ?? "" }
    var activityName: String { string("activity_name") ?? string("activityName") ?? "" }
    var signingCertSha256: String { string("signing_cert_sha256") ?? string("signingCertSha256") ?? "" }
    var installedAt: String { string("installed_at") ?? string("installedAt") ?? "" }
    var installRequestId: String { string("install_request_id") ?? string("installRequestId") ?? "" }
    var protocolVersion: Int { raw.int("protocol_version") ?? raw.int("protocolVersion") ?? 1 }
    var hostPackageName: String { string("host_package_name") ?? string("hostPackageName") ?? "" }
    var hostSigningCertSha256: String { string("host_signing_cert_sha256") ?? string("hostSigningCertSha256") ?? "" }
    var hostInstanceId: String { string("host_instance_id") ?? string("hostInstanceId") ?? "" }
    var hostSharedSecret: String { string("host_shared_secret") ?? string("hostSharedSecret") ?? "" }
    var iosBundleId: String { string("ios_bundle_id") ?? string("iosBundleId") ?? "" }
    var iosTeamId: String { string("ios_team_id") ?? string("iosTeamId") ?? "" }
    var installUrl: String { string("install_url") ?? string("installUrl") ?? "" }
    var actionUrl: String { string("action_url") ?? string("actionUrl") ?? "" }
    var universalLinkDomain: String { string("universal_link_domain") ?? string("universalLinkDomain") ?? "" }
    var hostBundleId: String { string("host_bundle_id") ?? string("hostBundleId") ?? "" }
    var hostTeamId: String { string("host_team_id") ?? string("hostTeamId") ?? "" }
    var hostCallbackScheme: String { string("host_callback_scheme") ?? string("hostCallbackScheme") ?? "" }
    var backgroundTriggerSupported: Bool { bool("background_trigger_supported") ?? bool("backgroundTriggerSupported") ?? false }
    var hostBackgroundTriggerService: String { string("host_background_trigger_service") ?? string("hostBackgroundTriggerService") ?? "" }
}

public extension NapaxiStableModel where Tag == NapaxiAgentAppPackageTag {
    init(
        providerId: String,
        agentId: String,
        displayName: String,
        description: String = "",
        systemPrompt: String = "",
        actions: [NapaxiAgentAppActionManifest] = [],
        handoff: [String: NapaxiJSONValue] = [:],
        result: [String: NapaxiJSONValue] = [:],
        installBinding: NapaxiAgentAppInstallBinding? = nil,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "provider_id": .string(providerId),
            "agent_id": .string(agentId),
            "display_name": .string(displayName),
            "description": .string(description),
            "system_prompt": .string(systemPrompt),
            "actions": .array(actions.map { .object($0.raw) }),
            "handoff": .object(handoff),
            "result": .object(result),
        ]
        if let installBinding { raw["install_binding"] = .object(installBinding.raw) }
        raw.setNonEmpty("created_at", createdAt)
        raw.setNonEmpty("updated_at", updatedAt)
        self.init(raw: raw)
    }

    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        let actions: [NapaxiAgentAppActionManifest]
        if case .array(let values)? = map["actions"] {
            actions = values.compactMap { value in
                guard case .object(let object) = value else { return nil }
                return NapaxiAgentAppActionManifest.fromMap(object)
            }
        } else {
            actions = []
        }

        let installBinding: NapaxiAgentAppInstallBinding?
        if let binding = map.object("install_binding") {
            installBinding = NapaxiAgentAppInstallBinding.fromMap(binding)
        } else {
            installBinding = nil
        }

        return Self(
            providerId: map.string("provider_id") ?? "",
            agentId: map.string("agent_id") ?? "",
            displayName: map.string("display_name") ?? "",
            description: map.string("description") ?? "",
            systemPrompt: map.string("system_prompt") ?? "",
            actions: actions,
            handoff: map.object("handoff") ?? [:],
            result: map.object("result") ?? [:],
            installBinding: installBinding,
            createdAt: map.string("created_at") ?? "",
            updatedAt: map.string("updated_at") ?? ""
        )
    }

    func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "provider_id": .string(providerId),
            "agent_id": .string(agentId),
            "display_name": .string(displayName),
            "description": .string(description),
            "system_prompt": .string(systemPrompt),
            "actions": .array(actions.map { .object($0.toJson()) }),
            "handoff": .object(handoff),
            "result": .object(result),
        ]
        if let installBinding { object["install_binding"] = .object(installBinding.toJson()) }
        object.setNonEmpty("created_at", createdAt)
        object.setNonEmpty("updated_at", updatedAt)
        return object
    }

    func toJsonString() throws -> String {
        try NapaxiRawJSON(.object(toJson())).jsonString()
    }

    var providerId: String { string("provider_id") ?? string("providerId") ?? "" }
    var agentId: String { string("agent_id") ?? string("agentId") ?? "" }
    var displayName: String { string("display_name") ?? string("displayName") ?? "" }
    var description: String { string("description") ?? "" }
    var systemPrompt: String { string("system_prompt") ?? string("systemPrompt") ?? "" }
    var actions: [NapaxiAgentAppActionManifest] { raw.modelArray("actions") ?? [] }
    var handoff: [String: NapaxiJSONValue] { raw.object("handoff") ?? [:] }
    var result: [String: NapaxiJSONValue] { raw.object("result") ?? [:] }
    var installBinding: NapaxiAgentAppInstallBinding? { raw.model("install_binding") ?? raw.model("installBinding") }
    var createdAt: String { string("created_at") ?? string("createdAt") ?? "" }
    var updatedAt: String { string("updated_at") ?? string("updatedAt") ?? "" }
}

public extension NapaxiStableModel where Tag == NapaxiAgentAppActionProposalTag {
    init(
        requestId: String,
        providerId: String,
        agentId: String,
        actionId: String,
        toolName: String,
        arguments: [String: NapaxiJSONValue] = [:],
        userIntentSummary: String = "",
        createdAt: String,
        expiresAt: String,
        nonce: String,
        idempotencyKey: String,
        callback: [String: NapaxiJSONValue] = [:],
        risk: String = "high",
        confirmationPolicy: String = "provider_required",
        hostInstanceId: String = "",
        signatureAlgorithm: String = "",
        signature: String? = nil
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "request_id": .string(requestId),
            "provider_id": .string(providerId),
            "agent_id": .string(agentId),
            "action_id": .string(actionId),
            "tool_name": .string(toolName),
            "arguments": .object(arguments),
            "user_intent_summary": .string(userIntentSummary),
            "created_at": .string(createdAt),
            "expires_at": .string(expiresAt),
            "nonce": .string(nonce),
            "idempotency_key": .string(idempotencyKey),
            "callback": .object(callback),
            "risk": .string(risk),
            "confirmation_policy": .string(confirmationPolicy),
        ]
        raw.setNonEmpty("host_instance_id", hostInstanceId)
        raw.setNonEmpty("signature_algorithm", signatureAlgorithm)
        if let signature { raw["signature"] = .string(signature) }
        self.init(raw: raw)
    }

    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            requestId: map.string("request_id") ?? "",
            providerId: map.string("provider_id") ?? "",
            agentId: map.string("agent_id") ?? "",
            actionId: map.string("action_id") ?? "",
            toolName: map.string("tool_name") ?? "",
            arguments: map.object("arguments") ?? [:],
            userIntentSummary: map.string("user_intent_summary") ?? "",
            createdAt: map.string("created_at") ?? "",
            expiresAt: map.string("expires_at") ?? "",
            nonce: map.string("nonce") ?? "",
            idempotencyKey: map.string("idempotency_key") ?? "",
            callback: map.object("callback") ?? [:],
            risk: map.string("risk") ?? "high",
            confirmationPolicy: map.string("confirmation_policy") ?? "provider_required",
            hostInstanceId: map.string("host_instance_id") ?? "",
            signatureAlgorithm: map.string("signature_algorithm") ?? "",
            signature: map.string("signature")
        )
    }

    func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "request_id": .string(requestId),
            "provider_id": .string(providerId),
            "agent_id": .string(agentId),
            "action_id": .string(actionId),
            "tool_name": .string(toolName),
            "arguments": .object(arguments),
            "user_intent_summary": .string(userIntentSummary),
            "created_at": .string(createdAt),
            "expires_at": .string(expiresAt),
            "nonce": .string(nonce),
            "idempotency_key": .string(idempotencyKey),
            "callback": .object(callback),
            "risk": .string(risk),
            "confirmation_policy": .string(confirmationPolicy),
        ]
        object.setNonEmpty("host_instance_id", hostInstanceId)
        object.setNonEmpty("signature_algorithm", signatureAlgorithm)
        if let signature { object["signature"] = .string(signature) }
        return object
    }

    var requestId: String { string("request_id") ?? string("requestId") ?? "" }
    var providerId: String { string("provider_id") ?? string("providerId") ?? "" }
    var agentId: String { string("agent_id") ?? string("agentId") ?? "" }
    var actionId: String { string("action_id") ?? string("actionId") ?? "" }
    var toolName: String { string("tool_name") ?? string("toolName") ?? "" }
    var arguments: [String: NapaxiJSONValue] { raw.object("arguments") ?? [:] }
    var userIntentSummary: String { string("user_intent_summary") ?? string("userIntentSummary") ?? "" }
    var createdAt: String { string("created_at") ?? string("createdAt") ?? "" }
    var expiresAt: String { string("expires_at") ?? string("expiresAt") ?? "" }
    var nonce: String { string("nonce") ?? "" }
    var idempotencyKey: String { string("idempotency_key") ?? string("idempotencyKey") ?? "" }
    var callback: [String: NapaxiJSONValue] { raw.object("callback") ?? [:] }
    var risk: String { string("risk") ?? "high" }
    var confirmationPolicy: String { string("confirmation_policy") ?? string("confirmationPolicy") ?? "provider_required" }
    var hostInstanceId: String { string("host_instance_id") ?? string("hostInstanceId") ?? "" }
    var signatureAlgorithm: String { string("signature_algorithm") ?? string("signatureAlgorithm") ?? "" }
    var signature: String? { string("signature") }
}

public extension NapaxiStableModel where Tag == NapaxiAgentAppActionResultTag {
    init(
        requestId: String,
        status: String,
        result: [String: NapaxiJSONValue] = [:],
        error: String? = nil,
        providerTraceId: String? = nil,
        completedAt: String,
        signature: String? = nil
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "request_id": .string(requestId),
            "status": .string(status),
            "result": .object(result),
            "completed_at": .string(completedAt),
        ]
        if let error { raw["error"] = .string(error) }
        if let providerTraceId { raw["provider_trace_id"] = .string(providerTraceId) }
        if let signature { raw["signature"] = .string(signature) }
        self.init(raw: raw)
    }

    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        return Self(
            requestId: map.string("request_id") ?? "",
            status: map.string("status") ?? "",
            result: map.object("result") ?? [:],
            error: map.displayString("error"),
            providerTraceId: map.string("provider_trace_id"),
            completedAt: map.string("completed_at") ?? "",
            signature: map.string("signature")
        )
    }

    func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "request_id": .string(requestId),
            "status": .string(status),
            "result": .object(result),
            "completed_at": .string(completedAt),
        ]
        if let error { object["error"] = .string(error) }
        if let providerTraceId { object["provider_trace_id"] = .string(providerTraceId) }
        if let signature { object["signature"] = .string(signature) }
        return object
    }

    func toJsonString() throws -> String {
        try NapaxiRawJSON(.object(toJson())).jsonString()
    }

    var requestId: String { string("request_id") ?? string("requestId") ?? "" }
    var status: String { string("status") ?? "" }
    var result: [String: NapaxiJSONValue] { raw.object("result") ?? [:] }
    var error: String? { raw.displayString("error") }
    var providerTraceId: String? { string("provider_trace_id") ?? string("providerTraceId") }
    var completedAt: String { string("completed_at") ?? string("completedAt") ?? "" }
    var signature: String? { string("signature") }
}

public extension NapaxiStableModel where Tag == NapaxiAgentAppActionRecordTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        let proposal = NapaxiAgentAppActionProposal.fromMap(map.object("proposal") ?? [:])
        let result = map.object("result").map(NapaxiAgentAppActionResult.fromMap)
        var raw: [String: NapaxiJSONValue] = [
            "proposal": .object(proposal.toJson()),
            "status": .string(map.string("status") ?? ""),
            "created_at": .string(map.string("created_at") ?? ""),
            "updated_at": .string(map.string("updated_at") ?? ""),
        ]
        if let result { raw["result"] = .object(result.toJson()) }
        return Self(raw: raw)
    }

    var proposal: NapaxiAgentAppActionProposal {
        raw.model("proposal") ?? NapaxiAgentAppActionProposal(requestId: "", providerId: "", agentId: "", actionId: "", toolName: "", createdAt: "", expiresAt: "", nonce: "", idempotencyKey: "")
    }
    var status: String { string("status") ?? "" }
    var result: NapaxiAgentAppActionResult? { raw.model("result") }
    var createdAt: String { string("created_at") ?? string("createdAt") ?? "" }
    var updatedAt: String { string("updated_at") ?? string("updatedAt") ?? "" }
}

public extension NapaxiStableModel where Tag == NapaxiAgentAppActionRequestTag {
    init(
        proposal: NapaxiAgentAppActionProposal,
        action: NapaxiAgentAppActionManifest,
        package: [String: NapaxiJSONValue]
    ) {
        self.init(raw: [
            "proposal": .object(proposal.raw),
            "action": .object(action.raw),
            "package": .object(package),
        ])
    }

    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            proposal: NapaxiAgentAppActionProposal.fromMap(map.object("proposal") ?? [:]),
            action: NapaxiAgentAppActionManifest.fromMap(map.object("action") ?? [:]),
            package: map.object("package") ?? [:]
        )
    }

    var proposal: NapaxiAgentAppActionProposal {
        raw.model("proposal") ?? NapaxiAgentAppActionProposal(requestId: "", providerId: "", agentId: "", actionId: "", toolName: "", createdAt: "", expiresAt: "", nonce: "", idempotencyKey: "")
    }
    var action: NapaxiAgentAppActionManifest {
        raw.model("action") ?? NapaxiAgentAppActionManifest(actionId: "", toolName: "", description: "")
    }
    var package: [String: NapaxiJSONValue] { raw.object("package") ?? [:] }
}

public extension NapaxiStableModel where Tag == NapaxiAgentInstallResultTag {
    init(
        status: String,
        requestId: String,
        nonce: String,
        package: NapaxiAgentAppPackage? = nil,
        error: [String: NapaxiJSONValue]? = nil,
        completedAt: String
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "status": .string(status),
            "request_id": .string(requestId),
            "nonce": .string(nonce),
            "completed_at": .string(completedAt),
        ]
        if let package { raw["package"] = .object(package.raw) }
        if let error { raw["error"] = .object(error) }
        self.init(raw: raw)
    }

    init(jsonString: String) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(jsonString.utf8))
    }

    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var status: String { string("status") ?? "" }
    var requestId: String { string("request_id") ?? string("requestId") ?? "" }
    var nonce: String { string("nonce") ?? "" }
    var package: NapaxiAgentAppPackage? { raw.model("package") }
    var packageRaw: [String: NapaxiJSONValue]? { raw.object("package") }
    var error: [String: NapaxiJSONValue]? { raw.object("error") }
    var errorValue: NapaxiJSONValue? { raw["error"] }
    var errorMessage: String? {
        errorValue?.stringValue ?? error?["message"]?.stringValue ?? error?["error"]?.stringValue
    }
    var completedAt: String { string("completed_at") ?? string("completedAt") ?? "" }
}

public func decodeAgentAppPackages(_ raw: String) throws -> [NapaxiAgentAppPackage] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value) { object in
        NapaxiAgentAppPackage(raw: object)
    }
}

public func decodeAgentAppActionRecords(_ raw: String) throws -> [NapaxiAgentAppActionRecord] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value) { object in
        try validateAgentAppActionRecordObject(object)
        return NapaxiAgentAppActionRecord(raw: object)
    }
}

func validateAgentAppActionRecordObject(_ object: [String: NapaxiJSONValue]) throws {
    try validateAgentAppObjectOrNull(object, key: "proposal", context: "agent app action record proposal")
}

func validateAgentAppActionRequestObject(_ object: [String: NapaxiJSONValue]) throws {
    try validateAgentAppObjectOrNull(object, key: "proposal", context: "agent app action request proposal")
    try validateAgentAppObjectOrNull(object, key: "action", context: "agent app action request action")
}

private func validateAgentAppObjectOrNull(
    _ object: [String: NapaxiJSONValue],
    key: String,
    context: String
) throws {
    guard let value = object[key] else { return }
    switch value {
    case .object, .null:
        return
    default:
        throw NapaxiError.invalidJSON("Expected \(context) object")
    }
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    mutating func setNonEmpty(_ key: String, _ value: String) {
        if !value.isEmpty {
            self[key] = .string(value)
        }
    }

    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    func displayString(_ key: String) -> String? {
        guard let value = self[key], value != .null else { return nil }
        return value.jsonCodecDisplayString
    }

    func bool(_ key: String) -> Bool? {
        self[key]?.boolValue
    }

    func object(_ key: String) -> [String: NapaxiJSONValue]? {
        if case .object(let object)? = self[key] {
            return object
        }
        return nil
    }

    func int(_ key: String) -> Int? {
        self[key]?.numberValue.map(Int.init)
    }

    func stringArray(_ key: String) -> [String]? {
        if case .array(let values)? = self[key] {
            return values.map(\.jsonCodecDisplayString)
        }
        return nil
    }

    func model<T: Decodable>(_ key: String) -> T? {
        guard let value = self[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    func modelArray<T: Decodable>(_ key: String) -> [T]? {
        guard let value = self[key] else { return nil }
        return try? JSONDecoder().decode([T].self, from: JSONEncoder().encode(value))
    }
}
