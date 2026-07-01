import Foundation

public protocol NapaxiToolExecutor: AnyObject {
    func execute(toolName: String, paramsJSON: String, context: NapaxiJSONValue?) async -> Result<String, Error>
}

public protocol McToolExecutor: AnyObject {
    func execute(_ toolName: String, _ paramsJSON: String) async throws -> String
}

public final class NapaxiToolExecutorAdapter: NapaxiToolExecutor {
    private let executor: McToolExecutor

    public init(executor: McToolExecutor) {
        self.executor = executor
    }

    public func execute(toolName: String, paramsJSON: String, context: NapaxiJSONValue?) async -> Result<String, Error> {
        do {
            return .success(try await executor.execute(toolName, paramsJSON))
        } catch {
            return .failure(error)
        }
    }
}

public protocol NapaxiToolApprovalHandler: AnyObject {
    func approve(toolName: String, requestJSON: String) async -> Bool
}

public struct NapaxiHostToolApprovalRequest: Codable, Equatable, Sendable {
    public var requestId: UInt64
    public var toolName: String
    public var description: String
    public var parametersJSON: String
    public var parametersJson: String {
        get { parametersJSON }
        set { parametersJSON = newValue }
    }
    public var allowAlways: Bool

    public init(
        requestId: UInt64,
        toolName: String,
        description: String,
        parametersJSON: String = "{}",
        allowAlways: Bool = false
    ) {
        self.requestId = requestId
        self.toolName = toolName
        self.description = description
        self.parametersJSON = parametersJSON
        self.allowAlways = allowAlways
    }

    public init(
        requestId: UInt64,
        toolName: String,
        description: String,
        parametersJson: String,
        allowAlways: Bool = false
    ) {
        self.init(
            requestId: requestId,
            toolName: toolName,
            description: description,
            parametersJSON: parametersJson,
            allowAlways: allowAlways
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: NapaxiJSONValue].self)
        self.init(
            requestId: Self.uint64Value(object["requestId"] ?? object["request_id"]) ?? 0,
            toolName: object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue ?? "",
            description: object["description"]?.stringValue ?? "",
            parametersJSON: Self.parametersJSONString(
                object["parametersJson"]
                    ?? object["parametersJSON"]
                    ?? object["parameters"]
                    ?? object["parameters_json"]
            ),
            allowAlways: Self.boolValue(object["allowAlways"] ?? object["allow_always"]) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object([
            "requestId": .number(Double(requestId)),
            "toolName": .string(toolName),
            "description": .string(description),
            "parametersJson": .string(parametersJSON),
            "allowAlways": .bool(allowAlways),
        ]).encode(to: encoder)
    }

    public var parameters: [String: NapaxiJSONValue] {
        (try? NapaxiRawJSON(jsonString: parametersJSON).value.objectValue) ?? [:]
    }

    private static func parametersJSONString(_ value: NapaxiJSONValue?) -> String {
        guard let value else {
            return "{}"
        }
        if let string = value.stringValue {
            return string
        }
        return (try? NapaxiRawJSON(value).jsonString()) ?? "{}"
    }

    private static func uint64Value(_ value: NapaxiJSONValue?) -> UInt64? {
        if let number = value?.numberValue {
            guard number >= 0, number <= Double(UInt64.max) else {
                return nil
            }
            return UInt64(number)
        }
        if let string = value?.stringValue {
            return UInt64(string)
        }
        return nil
    }

    private static func boolValue(_ value: NapaxiJSONValue?) -> Bool? {
        if let bool = value?.boolValue {
            return bool
        }
        if let string = value?.stringValue {
            return Bool(string)
        }
        return nil
    }
}

public struct NapaxiHostToolApprovalResponse: Codable, Equatable, Sendable {
    public var approved: Bool
    public var always: Bool
    public var message: String?

    public init(approved: Bool, always: Bool = false, message: String? = nil) {
        self.approved = approved
        self.always = always
        self.message = message
    }

    public func jsonString() throws -> String {
        var object: [String: NapaxiJSONValue] = [
            "approved": .bool(approved),
            "always": .bool(always),
        ]
        if let message {
            object["message"] = .string(message)
        }
        return try object.jsonString()
    }
}

public protocol NapaxiStructuredToolApprovalHandler: AnyObject {
    func approve(_ request: NapaxiHostToolApprovalRequest) async -> NapaxiHostToolApprovalResponse
}

public final class NapaxiToolApprovalHandlerAdapter: NapaxiStructuredToolApprovalHandler {
    private let handler: McToolApprovalHandler

    public init(handler: @escaping McToolApprovalHandler) {
        self.handler = handler
    }

    public func approve(_ request: NapaxiHostToolApprovalRequest) async -> NapaxiHostToolApprovalResponse {
        await handler(request)
    }
}

public protocol NapaxiAgentAppActionExecutor: AnyObject {
    func executeAgentAppAction(requestJSON: String) async -> String
}

public protocol AgentAppActionExecutor: AnyObject {
    func execute(_ request: NapaxiAgentAppActionRequest) async throws -> NapaxiAgentAppActionResult
}

@available(*, deprecated, message: "Use AgentAppActionExecutor instead.")
public typealias McAgentAppActionExecutor = AgentAppActionExecutor

public final class NapaxiAgentAppActionExecutorAdapter: NapaxiAgentAppActionExecutor {
    private let executor: AgentAppActionExecutor
    private let decoder = JSONDecoder()

    public init(executor: AgentAppActionExecutor) {
        self.executor = executor
    }

    public func executeAgentAppAction(requestJSON: String) async -> String {
        do {
            let request = try decoder.decode(NapaxiAgentAppActionRequest.self, from: Data(requestJSON.utf8))
            try validateAgentAppActionRequestObject(request.raw)
            return try await executor.execute(request).jsonString()
        } catch {
            return failedActionResultJSON(requestJSON: requestJSON, error: error)
        }
    }

    private func failedActionResultJSON(requestJSON: String, error: Error) -> String {
        let request = try? decoder.decode(NapaxiAgentAppActionRequest.self, from: Data(requestJSON.utf8))
        let result = NapaxiAgentAppActionResult(
            requestId: request?.proposal.requestId ?? "",
            status: "failed",
            error: String(describing: error),
            completedAt: ISO8601DateFormatter().string(from: Date())
        )
        return (try? result.jsonString()) ?? #"{"request_id":"","status":"failed","result":{},"error":"Agent app action failed","completed_at":""}"#
    }
}

public protocol NapaxiBrowserController: AnyObject {
    func executeBrowserTool(toolName: String, paramsJSON: String) async throws -> String
}

public enum NapaxiChatDefaults {
    public static let maxIterations = 0
    public static let maxIterationsInt32: Int32 = 0

    static func bridgeMaxIterations(_ value: Int) -> Int32 {
        Int32(clamping: value)
    }
}

public final class NapaxiEngine: @unchecked Sendable {
    public static let defaultAgentId = "napaxi"
    public static let defaultAccountId = "default"
    public static let defaultHistoryPageLimit = 80
    public static let defaultWorkspaceAgentId = ""

    public let handle: Int64
    public let filesDir: String
    public private(set) var config: NapaxiConfig

    public let api: NapaxiRawAPI
    public let agentProviderHost: NapaxiAgentProviderHost
    public let channelProviders: NapaxiChannelProviderHost
    public let capabilityProfile: NapaxiCapabilityProfile?

    public var chat: NapaxiChatAPI { NapaxiChatAPI(engine: self) }
    public var tools: NapaxiToolAPI { NapaxiToolAPI(rawAPI: api) }
    public var capabilities: NapaxiCapabilityAPI { NapaxiCapabilityAPI(rawAPI: api, defaultProfile: capabilityProfile) }
    public var automation: NapaxiAutomationAPI { NapaxiAutomationAPI(rawAPI: api) }
    /// Host-carried scheduler for automation jobs. On iOS this always exists but
    /// reports an unsupported state for platform-scheduled wakes (no background
    /// execution); the core-backed catch-up path still runs. Mirrors the Flutter
    /// `NapaxiEngine.automationScheduler`.
    public var automationScheduler: NapaxiAutomationScheduler { NapaxiAutomationScheduler(automation: automation) }
    public var a2a: NapaxiA2AAPI { NapaxiA2AAPI(rawAPI: api) }
    public var sessionRuns: NapaxiSessionRunAPI { NapaxiSessionRunAPI(rawAPI: api) }
    public var agentApps: NapaxiAgentAppAPI { NapaxiAgentAppAPI(rawAPI: api) }
    public var agentApp: NapaxiAgentAppAPI { agentApps }
    public var agents: NapaxiAgentAPI { NapaxiAgentAPI(rawAPI: api, engine: self) }
    public var agentDefinitions: NapaxiAgentDefinitionAPI { NapaxiAgentDefinitionAPI(rawAPI: api) }
    public var sessions: NapaxiSessionAPI { NapaxiSessionAPI(rawAPI: api, engine: self) }
    public var skills: NapaxiSkillAPI { NapaxiSkillAPI(rawAPI: api, engine: self) }
    public var evolution: NapaxiEvolutionAPI { NapaxiEvolutionAPI(rawAPI: api, engine: self) }
    public var groups: NapaxiGroupAPI { NapaxiGroupAPI(rawAPI: api, engine: self) }
    public var channels: NapaxiChannelAPI { NapaxiChannelAPI(rawAPI: api) }
    public var channelAgents: NapaxiChannelAgentAPI { NapaxiChannelAgentAPI(rawAPI: api) }
    public var qqbotProtocol: NapaxiQqBotProtocolAPI { NapaxiQqBotProtocolAPI(rawAPI: api) }
    public var workspace: NapaxiWorkspaceAPI { NapaxiWorkspaceAPI(rawAPI: api, engine: self) }
    public var fileBridge: NapaxiFileBridgeAPI { NapaxiFileBridgeAPI(rawAPI: api, filesDir: filesDir) }
    public var mcp: NapaxiMcpAPI { NapaxiMcpAPI(rawAPI: api, defaultUserId: NapaxiEngine.defaultAccountId) }
    public var background: NapaxiBackgroundAPI { NapaxiBackgroundAPI(controller: backgroundController) }
    public var agentProviders: NapaxiAgentProviderAPI {
        NapaxiAgentProviderAPI(
            host: agentProviderHost,
            registerPackage: { [agentApps] packageJSON in
                try agentApps.registerPackageJSON(packageJSON: packageJSON)
            },
            getPackage: { [agentApps] agentId in
                let value = try agentApps.getPackageJSON(agentId: agentId)
                return value == .null ? nil : value
            }
        )
    }

    private let toolExecutor: NapaxiToolExecutor?
    private let agentAppActionExecutor: NapaxiAgentAppActionExecutor?
    private let browserController: NapaxiBrowserController?
    private let structuredToolApprovalHandler: NapaxiStructuredToolApprovalHandler?
    private let toolRequestRouter: NapaxiToolRequestRouter?
    private let sessionRunTracker: NapaxiSessionRunTracker
    public let backgroundController: NapaxiBackgroundController?
    private var backgroundActionTask: Task<Void, Never>?
    private let lifecycleLock = NSLock()
    private var disposed = false

    private init(
        handle: Int64,
        filesDir: String,
        config: NapaxiConfig,
        toolExecutor: NapaxiToolExecutor?,
        agentAppActionExecutor: NapaxiAgentAppActionExecutor?,
        browserController: NapaxiBrowserController?,
        structuredToolApprovalHandler: NapaxiStructuredToolApprovalHandler?,
        toolRequestRouter: NapaxiToolRequestRouter?,
        backgroundController: NapaxiBackgroundController?,
        agentProviderHost: NapaxiAgentProviderHost,
        capabilityProfile: NapaxiCapabilityProfile?
    ) {
        self.handle = handle
        self.filesDir = filesDir
        self.config = config
        self.toolExecutor = toolExecutor
        self.agentAppActionExecutor = agentAppActionExecutor
        self.browserController = browserController
        self.structuredToolApprovalHandler = structuredToolApprovalHandler
        self.toolRequestRouter = toolRequestRouter
        self.sessionRunTracker = NapaxiSessionRunTracker()
        self.backgroundController = backgroundController
        self.api = NapaxiRawAPI(handle: handle)
        self.agentProviderHost = agentProviderHost
        self.channelProviders = NapaxiChannelProviderHost(channels: NapaxiChannelAPI(rawAPI: self.api))
        self.capabilityProfile = capabilityProfile
    }

    deinit {
        disposeResources()
    }

    private func markDisposed() -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        if disposed {
            return false
        }
        disposed = true
        return true
    }

    /// True once `dispose()`/`deinit` has run. Read under `lifecycleLock` so it
    /// is consistent with `markDisposed`.
    private var isDisposed: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return disposed
    }

    /// Throws if the engine has been disposed. Public methods that forward the
    /// raw `handle` into native MUST call this first: after disposal the native
    /// `Engine` has been freed (`disposeEngine` drops the last `Arc`), so passing
    /// `handle` on would be a use-after-free.
    ///
    /// This closes the dominant misuse — invoking a method after `dispose()` has
    /// returned. A method already past this check when a *concurrent* `dispose()`
    /// frees the engine is a narrower window that this guard cannot fully close
    /// from Swift (the native call runs outside `lifecycleLock`); eliminating it
    /// would require reference-counting the handle on the Rust side.
    private func ensureNotDisposed() throws {
        if isDisposed {
            throw NapaxiError.invalidState("NapaxiEngine has been disposed")
        }
    }

    private func disposeResources() {
        guard markDisposed() else { return }
        sessionRunTracker.finish()
        channelProviders.dispose()
        backgroundActionTask?.cancel()
        backgroundActionTask = nil
        backgroundController?.dispose()
        NapaxiA2ALocalTransport.clearInstance(handle: handle)
        NapaxiNativeBridge.clearToolRequestRouter()
        NapaxiNativeBridge.disposeEngine(handle: handle)
        NapaxiFileBridgeAPI.clearInstance(handle: handle)
    }

    public var sessionRunUpdates: AsyncStream<NapaxiSessionRunInfo> {
        sessionRunTracker.updates
    }

    public var activeSessionRuns: [NapaxiSessionRunInfo] {
        sessionRunTracker.activeRuns
    }

    public func hasActiveSessionRun(_ key: NapaxiSessionKey, agentId: String = NapaxiEngine.defaultAgentId) -> Bool {
        sessionRunTracker.hasActiveRun(agentId: agentId, key: key)
    }

    public func activeSessionRun(_ key: NapaxiSessionKey, agentId: String = NapaxiEngine.defaultAgentId) -> NapaxiSessionRunInfo? {
        sessionRunTracker.activeRun(agentId: agentId, key: key)
    }

    public func mcpForAccount(_ accountId: String) -> NapaxiMcpAPI {
        NapaxiMcpAPI(rawAPI: api, defaultUserId: accountId)
    }

    public static func create(
        config: NapaxiConfig,
        filesDir: String? = nil,
        toolExecutor: NapaxiToolExecutor? = nil,
        mcToolExecutor: McToolExecutor? = nil,
        agentAppActionExecutor: NapaxiAgentAppActionExecutor? = nil,
        typedAgentAppActionExecutor: AgentAppActionExecutor? = nil,
        browserController: NapaxiBrowserController? = nil,
        browserToolExecutor: NapaxiBrowserToolExecutor? = nil,
        browserMutationPolicy: NapaxiBrowserMutationPolicy = .requireApproval,
        enablePlatformTools: Bool = true,
        enableAutomation: Bool? = nil,
        capabilityProfile: NapaxiCapabilityProfile? = nil,
        capabilitySelection: NapaxiCapabilitySelection? = nil,
        platformToolExecutor: NapaxiPlatformToolExecutor? = nil,
        toolApprovalHandler: NapaxiToolApprovalHandler? = nil,
        structuredToolApprovalHandler: NapaxiStructuredToolApprovalHandler? = nil,
        mcToolApprovalHandler: McToolApprovalHandler? = nil,
        backgroundConfig: NapaxiBackgroundConfig? = nil,
        backgroundHost: NapaxiBackgroundHost? = nil,
        callbackScheme: String? = nil,
        agentProviderHost: NapaxiAgentProviderHost? = nil,
        enableAgentProviderActions: Bool = false,
        openAgentProviderURL: NapaxiAgentProviderHost.URLOpener? = nil
    ) throws -> NapaxiEngine {
        let ishRootfsAvailable = NapaxiIshSupport.registerBundledRootfsArchive()
        let automationEnabled = resolveAutomationEnabled(
            enableAutomation: enableAutomation,
            backgroundConfig: backgroundConfig
        )
        let baseBrowserController = browserController ?? browserToolExecutor.map(NapaxiBrowserControllerAdapter.init)
        let resolvedStructuredToolApprovalHandler = structuredToolApprovalHandler
            ?? mcToolApprovalHandler.map(NapaxiToolApprovalHandlerAdapter.init)
        let resolvedBrowserController = baseBrowserController.map {
            NapaxiBrowserApprovalController(
                controller: $0,
                mutationPolicy: browserMutationPolicy,
                approvalHandler: toolApprovalHandler,
                structuredApprovalHandler: resolvedStructuredToolApprovalHandler
            )
        }
        let resolvedAgentProviderHost = agentProviderHost ?? NapaxiAgentProviderHost(callbackScheme: callbackScheme)
        let typedAgentAppActionExecutorAdapter = typedAgentAppActionExecutor.map(NapaxiAgentAppActionExecutorAdapter.init)
        let resolvedAgentAppActionExecutor = agentAppActionExecutor
            ?? typedAgentAppActionExecutorAdapter
            ?? (enableAgentProviderActions
                ? NapaxiAgentProviderActionExecutor(
                    host: resolvedAgentProviderHost,
                    openURL: openAgentProviderURL ?? NapaxiAgentProviderAPI.defaultOpenURL
                )
                : nil)
        let resolvedToolExecutor = toolExecutor ?? mcToolExecutor.map(NapaxiToolExecutorAdapter.init)

        let resolvedFilesDir = filesDir ?? NapaxiPlatformContextResolver.defaultFilesDir
        let profile = capabilityProfile ?? defaultCapabilityProfile(
            hasCustomToolExecutor: resolvedToolExecutor != nil,
            hasAgentAppActionExecutor: resolvedAgentAppActionExecutor != nil,
            hasBrowserController: resolvedBrowserController != nil,
            enablePlatformTools: enablePlatformTools,
            enableAutomation: automationEnabled,
            ishRootfsAvailable: ishRootfsAvailable
        )
        let selection = capabilitySelection ?? NapaxiCapabilitySelection(
            enabledCapabilities: [
                NapaxiChannelCapability.im,
                NapaxiChannelCapability.device,
                resolvedToolExecutor == nil ? nil : "napaxi.tool.custom_host",
                resolvedAgentAppActionExecutor == nil ? nil : "napaxi.tool.agent_app_action",
                resolvedBrowserController == nil ? nil : NapaxiBrowserToolProvider.capabilityId,
                automationEnabled ? "napaxi.service.automation" : nil,
            ].compactMap { $0 }
        )
        let platformContext = try NapaxiPlatformContextResolver.resolve(
            filesDir: resolvedFilesDir,
            platform: "ios",
            capabilityProfile: profile,
            capabilitySelection: selection
        )
        let handle = try NapaxiNativeBridge.createEngine(
            configJSON: config.jsonString(),
            platformContextJSON: platformContext.platformContextJSON
        )
        initializeFileBridgeBestEffort(handle: handle, filesDir: resolvedFilesDir) {
            try NapaxiNativeBridge.call(
                handle: handle,
                namespace: "file_bridge",
                method: "init",
                payload: [:]
            ).requiredBool()
        }
        let router = NapaxiToolRequestRouter(
            platformExecutor: enablePlatformTools ? (platformToolExecutor ?? NapaxiDefaultPlatformToolExecutor(filesDir: resolvedFilesDir)) : nil,
            customExecutor: resolvedToolExecutor,
            approvalHandler: toolApprovalHandler,
            structuredApprovalHandler: resolvedStructuredToolApprovalHandler,
            agentAppActionExecutor: resolvedAgentAppActionExecutor,
            browserController: resolvedBrowserController
        )
        _ = try NapaxiNativeBridge.registerToolRequestRouter(router)
        return NapaxiEngine(
            handle: handle,
            filesDir: resolvedFilesDir,
            config: config,
            toolExecutor: resolvedToolExecutor,
            agentAppActionExecutor: resolvedAgentAppActionExecutor,
            browserController: resolvedBrowserController,
            structuredToolApprovalHandler: resolvedStructuredToolApprovalHandler,
            toolRequestRouter: router,
            backgroundController: makeBackgroundController(config: backgroundConfig, host: backgroundHost),
            agentProviderHost: resolvedAgentProviderHost,
            capabilityProfile: profile
        )
    }

    @discardableResult
    static func initializeFileBridgeBestEffort(
        handle: Int64,
        filesDir: String,
        initializer: () throws -> Bool
    ) -> Bool {
        do {
            guard try initializer() else { return false }
            NapaxiFileBridgeAPI.registerInitialized(filesDir: filesDir, handle: handle)
            return true
        } catch {
            return false
        }
    }

    static func makeBackgroundController(
        config: NapaxiBackgroundConfig?,
        host: NapaxiBackgroundHost?
    ) -> NapaxiBackgroundController? {
        guard let host else {
            return nil
        }
        if config?.enabled == false {
            return nil
        }
        return NapaxiBackgroundController(config: config, host: host)
    }

    static func resolveAutomationEnabled(
        enableAutomation: Bool?,
        backgroundConfig: NapaxiBackgroundConfig?
    ) -> Bool {
        enableAutomation ?? (backgroundConfig != nil)
    }

    public func updateConfig(_ newConfig: NapaxiConfig) throws -> Bool {
        try ensureNotDisposed()
        let updated = try NapaxiNativeBridge.updateConfig(handle: handle, configJSON: newConfig.jsonString())
        if updated {
            config = newConfig
        }
        return updated
    }

    public func ensureAgentReady() throws -> Bool {
        try ensureNotDisposed()
        return try NapaxiNativeBridge.ensureAgentReady(handle: handle, configJSON: config.jsonString())
    }

    public func ensureAgent() throws -> Bool {
        try ensureAgentReady()
    }

    public func send(
        _ message: String,
        attachments: [NapaxiAttachment] = [],
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) async throws -> NapaxiJSONValue {
        try ensureNotDisposed()
        let attachmentsJSON = try attachmentsJSON(attachments)
        return try NapaxiNativeBridge.sendMessage(
            handle: handle,
            configJSON: config.jsonString(),
            message: message,
            attachmentsJSON: attachmentsJSON,
            maxIterations: NapaxiChatDefaults.bridgeMaxIterations(maxIterations)
        )
    }

    public func sendStream(
        _ message: String,
        attachments: [NapaxiAttachment] = [],
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> AsyncThrowingStream<NapaxiChatEvent, Error> {
        try ensureNotDisposed()
        let rawStream = NapaxiNativeBridge.sendMessageStream(
            handle: handle,
            configJSON: try config.jsonString(),
            message: message,
            attachmentsJSON: try attachmentsJSON(attachments),
            maxIterations: NapaxiChatDefaults.bridgeMaxIterations(maxIterations)
        )
        return wrapWithBackground(rawStream)
    }

    public func sendToSession(
        agentId: String = NapaxiEngine.defaultAgentId,
        sessionKey: NapaxiSessionKey,
        message: String,
        attachments: [NapaxiAttachment] = [],
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) async throws -> NapaxiJSONValue {
        try ensureNotDisposed()
        let run = try sessionRunTracker.start(agentId: agentId, key: sessionKey)
        let sessionKeyJSON = String(data: try JSONEncoder().encode(sessionKey), encoding: .utf8) ?? "{}"
        do {
            let result = try NapaxiNativeBridge.sendToSession(
                handle: handle,
                configJSON: config.jsonString(),
                agentId: agentId,
                sessionKeyJSON: sessionKeyJSON,
                message: message,
                attachmentsJSON: attachmentsJSON(attachments),
                maxIterations: NapaxiChatDefaults.bridgeMaxIterations(maxIterations)
            )
            _ = sessionRunTracker.complete(run)
            return result
        } catch {
            _ = sessionRunTracker.fail(run, error: error)
            throw error
        }
    }

    public func sendToSession(
        _ sessionKey: NapaxiSessionKey,
        _ message: String,
        attachments: [NapaxiAttachment] = [],
        maxIterations: Int = NapaxiChatDefaults.maxIterations,
        agentId: String = NapaxiEngine.defaultAgentId
    ) async throws -> NapaxiJSONValue {
        try await sendToSession(
            agentId: agentId,
            sessionKey: sessionKey,
            message: message,
            attachments: attachments,
            maxIterations: maxIterations
        )
    }

    public func sendToSessionStream(
        agentId: String = NapaxiEngine.defaultAgentId,
        sessionKey: NapaxiSessionKey,
        message: String,
        attachments: [NapaxiAttachment] = [],
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> AsyncThrowingStream<NapaxiChatEvent, Error> {
        try ensureNotDisposed()
        let startedRun = try sessionRunTracker.start(agentId: agentId, key: sessionKey)
        let sessionKeyJSON = String(data: try JSONEncoder().encode(sessionKey), encoding: .utf8) ?? "{}"
        let rawStream = NapaxiNativeBridge.sendToSessionStream(
            handle: handle,
            configJSON: try config.jsonString(),
            agentId: agentId,
            sessionKeyJSON: sessionKeyJSON,
            message: message,
            attachmentsJSON: try attachmentsJSON(attachments),
            maxIterations: NapaxiChatDefaults.bridgeMaxIterations(maxIterations)
        )
        return wrapWithBackground(trackSessionRun(rawStream, initialRun: startedRun))
    }

    public func sendToSessionStream(
        _ sessionKey: NapaxiSessionKey,
        _ message: String,
        attachments: [NapaxiAttachment] = [],
        maxIterations: Int = NapaxiChatDefaults.maxIterations,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> AsyncThrowingStream<NapaxiChatEvent, Error> {
        try sendToSessionStream(
            agentId: agentId,
            sessionKey: sessionKey,
            message: message,
            attachments: attachments,
            maxIterations: maxIterations
        )
    }

    public func call(namespace: String, method: String, payload: [String: NapaxiJSONValue] = [:]) throws -> NapaxiJSONValue {
        try ensureNotDisposed()
        return try NapaxiNativeBridge.call(handle: handle, namespace: namespace, method: method, payload: payload)
    }

    public func updateCustomTools(_ toolsJSON: String) throws -> Bool {
        try ensureNotDisposed()
        return try NapaxiNativeBridge.updateCustomTools(handle: handle, toolsJSON: toolsJSON)
    }

    public func updateCustomTools(_ tools: [NapaxiCustomToolDefinition]) throws -> Bool {
        try updateCustomTools(NapaxiCustomToolDefinition.jsonString(for: tools))
    }

    public func startToolRequestListener() {
        // Swift registers host tool routing during create(...); this mirrors
        // Flutter's explicit stream-listener hook for migration callers.
    }

    public func createSession(
        agentId: String = NapaxiEngine.defaultAgentId,
        channelType: String = "app",
        accountId: String = NapaxiEngine.defaultAccountId,
        threadId: String? = nil
    ) throws -> NapaxiSessionKey {
        try sessions.create(agentId: agentId, channelType: channelType, accountId: accountId, threadId: threadId)
    }

    public func listSessions(
        agentId: String = NapaxiEngine.defaultAgentId,
        accountId: String = NapaxiEngine.defaultAccountId
    ) throws -> [NapaxiSessionInfo] {
        try sessions.list(agentId: agentId, accountId: accountId)
    }

    public func deleteSession(_ sessionKey: NapaxiSessionKey) throws -> Bool {
        try sessions.delete(sessionKey)
    }

    public func clearSession(_ sessionKey: NapaxiSessionKey) throws -> Bool {
        try sessions.clear(sessionKey)
    }

    public func getHistory(
        _ threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> [NapaxiChatMessage] {
        try sessions.history(threadId: threadId, agentId: agentId)
    }

    public func getHistoryPage(
        _ threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId,
        before: String? = nil,
        limit: Int = NapaxiEngine.defaultHistoryPageLimit
    ) throws -> NapaxiHistoryPage {
        try sessions.historyPage(threadId: threadId, agentId: agentId, before: before, limit: limit)
    }

    public func compactContext(
        _ sessionKey: NapaxiSessionKey,
        agentId: String = NapaxiEngine.defaultAgentId,
        focus: String? = nil
    ) throws -> NapaxiContextStatus {
        try sessions.compactContext(sessionKey, agentId: agentId, focus: focus)
    }

    public func contextStatus(
        _ threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> NapaxiContextStatus {
        try sessions.contextStatus(threadId: threadId, agentId: agentId)
    }

    public func listPendingEvolution() throws -> [[String: NapaxiJSONValue]] {
        try evolution.listPending()
    }

    public func applyPendingEvolution(_ pendingId: String) throws -> [String: NapaxiJSONValue] {
        try evolution.applyPending(pendingId)
    }

    public func rejectPendingEvolution(_ pendingId: String) throws -> [String: NapaxiJSONValue] {
        try evolution.rejectPending(pendingId)
    }

    public func listEvolutionRuns(runIds: [String] = []) throws -> [NapaxiEvolutionRun] {
        try evolution.listRuns(runIds: runIds)
    }

    public func listEvolutionDiagnostics() throws -> [NapaxiEvolutionDiagnostic] {
        try evolution.listDiagnostics()
    }

    public func runSkillConsolidationReview(
        agentId: String = NapaxiEngine.defaultAgentId,
        dryRun: Bool = true
    ) throws -> NapaxiSkillConsolidationReviewResult {
        try evolution.runSkillConsolidationReview(agentId: agentId, dryRun: dryRun)
    }

    public func listSkills(agentId: String = "") throws -> [NapaxiSkillInfo] {
        try skills.list(agentId: agentId)
    }

    public func listSkillStatus(agentId: String = "") throws -> NapaxiSkillStatusReport {
        try skills.status(agentId: agentId)
    }

    public func listSkillSources(agentId: String = "") throws -> NapaxiSkillSourceReport {
        try skills.sources(agentId: agentId)
    }

    public func recordSkillSourceChanged(
        _ sourceId: String,
        agentId: String = ""
    ) throws -> NapaxiSkillRefreshResult {
        try skills.recordSourceChanged(agentId: agentId, sourceId: sourceId)
    }

    public func getSkillStatus(_ skillName: String, agentId: String = "") throws -> NapaxiSkillStatusEntry? {
        try skills.getStatus(agentId: agentId, skillName: skillName)
    }

    public func checkSkills(agentId: String = "") throws -> NapaxiSkillStatusReport {
        try skills.check(agentId: agentId)
    }

    public func listSkillCommands(agentId: String = "") throws -> NapaxiSkillCommandReport {
        try skills.commands(agentId: agentId)
    }

    public func resolveSkillCommand(_ text: String, agentId: String = "") throws -> NapaxiSkillCommandResolution {
        try skills.resolveCommand(text, agentId: agentId)
    }

    public func runSkillCommand(
        _ commandName: String,
        agentId: String = "",
        args: String? = nil,
        sessionKey: NapaxiSessionKey? = nil
    ) throws -> NapaxiSkillCommandRun {
        try skills.runCommand(commandName, agentId: agentId, args: args, sessionKey: sessionKey)
    }

    public func setSkillEnabled(
        _ skillName: String,
        agentId: String = "",
        enabled: Bool
    ) throws -> String {
        try skills.setEnabled(agentId: agentId, skillName: skillName, enabled: enabled)
    }

    public func updateSkillConfig(
        _ skillKey: String,
        patch: [String: NapaxiJSONValue],
        agentId: String = ""
    ) throws -> String {
        try skills.updateConfig(agentId: agentId, skillKey: skillKey, patch: patch)
    }

    public func listSkillRemediationActions(
        _ skillName: String,
        agentId: String = ""
    ) throws -> [NapaxiSkillRemediationAction] {
        try skills.remediationActions(agentId: agentId, skillName: skillName)
    }

    public func listSkillSnapshots(
        agentId: String = "",
        limit: Int = 50,
        offset: Int = 0
    ) throws -> NapaxiSkillSnapshotList {
        try skills.snapshots(agentId: agentId, limit: limit, offset: offset)
    }

    public func getSkillSnapshot(_ snapshotId: String) throws -> NapaxiSkillSnapshot? {
        try skills.snapshot(snapshotId)
    }

    public func listSkillSecretRequirements(
        agentId: String = "",
        skillName: String? = nil
    ) throws -> NapaxiSkillSecretRequirementReport {
        try skills.secretRequirements(agentId: agentId, skillName: skillName)
    }

    public func recordSkillSecretAvailability(
        _ skillName: String,
        _ key: String,
        agentId: String = "",
        available: Bool,
        source: String = "host"
    ) throws -> NapaxiSkillStatusReport {
        try skills.recordSecretAvailability(
            agentId: agentId,
            skillName: skillName,
            key: key,
            available: available,
            source: source
        )
    }

    public func requestSkillRemediation(
        _ skillName: String,
        _ actionId: String,
        agentId: String = ""
    ) throws -> NapaxiSkillRemediationRun {
        try skills.requestRemediation(agentId: agentId, skillName: skillName, actionId: actionId)
    }

    public func updateSkillRemediationRun(
        _ runId: String,
        _ status: String,
        agentId: String = "",
        result: [String: NapaxiJSONValue]? = nil
    ) throws -> NapaxiSkillRemediationRun {
        try skills.updateRemediationRun(agentId: agentId, runId: runId, status: status, result: result)
    }

    public func listSkillRemediationRuns(
        agentId: String = "",
        skillName: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) throws -> NapaxiSkillRemediationRunList {
        try skills.remediationRuns(agentId: agentId, skillName: skillName, limit: limit, offset: offset)
    }

    public func recordSkillRequirementResolution(
        _ skillName: String,
        actionId: String,
        result: [String: NapaxiJSONValue],
        agentId: String = ""
    ) throws -> String {
        try skills.recordRequirementResolution(
            agentId: agentId,
            skillName: skillName,
            actionId: actionId,
            result: result
        )
    }

    public func getSkill(_ skillName: String, agentId: String = "") throws -> NapaxiSkillInfo? {
        try skills.get(agentId: agentId, skillName: skillName)
    }

    public func installSkill(_ skillContent: String, agentId: String = "") throws -> NapaxiSkillInstallResult {
        try skills.install(agentId: agentId, skillContent: skillContent)
    }

    public func installSkill(_ input: NapaxiSkillInstallInput, agentId: String = "") throws -> NapaxiSkillInstallResult {
        try skills.install(agentId: agentId, input: input)
    }

    public func removeSkill(_ skillName: String, agentId: String = "") throws -> Bool {
        try skills.remove(agentId: agentId, skillName: skillName)
    }

    public func reloadSkills(agentId: String = "") throws -> [String] {
        try skills.reload(agentId: agentId)
    }

    public func listSkillUsage(agentId: String = "") throws -> [NapaxiSkillUsageRecord] {
        try skills.usage(agentId: agentId)
    }

    public func pinSkill(
        _ skillName: String,
        agentId: String = "",
        pinned: Bool = true
    ) throws -> String {
        try skills.pin(agentId: agentId, skillName: skillName, pinned: pinned)
    }

    public func archiveSkill(_ skillName: String, agentId: String = "") throws -> String {
        try skills.archive(agentId: agentId, skillName: skillName)
    }

    public func restoreSkill(_ skillName: String, agentId: String = "") throws -> String {
        try skills.restore(agentId: agentId, skillName: skillName)
    }

    public func runSkillCurator(
        agentId: String = "",
        dryRun: Bool = true
    ) throws -> NapaxiCuratorRunSummary {
        try skills.runCurator(agentId: agentId, dryRun: dryRun)
    }

    public func readSkillSupportFile(
        _ skillName: String,
        _ filePath: String,
        agentId: String = ""
    ) throws -> NapaxiSkillSupportFileReadResult {
        try skills.readSupportFile(agentId: agentId, skillName: skillName, filePath: filePath)
    }

    public func searchCatalog(_ query: String) throws -> NapaxiCatalogSearchResult {
        try skills.searchCatalog(query: query)
    }

    public func listCatalogPackages(
        limit: Int = NapaxiClawHubSkillCatalogClient.defaultListLimit,
        cursor: String? = nil,
        catalogClient: NapaxiClawHubSkillCatalogClient = NapaxiClawHubSkillCatalogClient()
    ) async throws -> NapaxiCatalogPackagePage {
        try await skills.listCatalogPackages(limit: limit, cursor: cursor, catalogClient: catalogClient)
    }

    public func getCatalogSkill(_ slug: String) throws -> NapaxiCatalogSkillInfo {
        try skills.getCatalogSkill(slug: slug)
    }

    public func installFromCatalog(_ slug: String, agentId: String = "") throws -> NapaxiSkillInstallResult {
        try skills.installFromCatalog(agentId: agentId, slug: slug)
    }

    public func getOrCreateAgent(
        _ agentId: String,
        config: NapaxiConfig? = nil
    ) throws -> NapaxiAgentHandle {
        try agents.getOrCreate(agentId, config: config)
    }

    public func listAgents() throws -> [String] {
        try agents.list()
    }

    public func deleteAgent(_ agentId: String) throws -> Bool {
        try agents.delete(agentId)
    }

    public func agentSend(
        _ agent: NapaxiAgentHandle,
        _ sessionKey: NapaxiSessionKey,
        _ message: String,
        config: NapaxiConfig? = nil,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        if let config {
            return try agents.send(
                agentId: agent.agentId,
                config: config,
                sessionKey: sessionKey,
                message: message,
                maxIterations: maxIterations
            )
        }
        return try agents.send(
            agent: agent,
            sessionKey: sessionKey,
            message: message,
            maxIterations: maxIterations
        )
    }

    public func createAgentDefinition(_ definition: NapaxiAgentDefinition) throws -> NapaxiAgentDefinition {
        try agents.createDefinition(definition)
    }

    public func listAgentDefinitions() throws -> [NapaxiAgentDefinition] {
        try agents.listDefinitions()
    }

    public func getAgentDefinition(_ definitionId: String) throws -> NapaxiAgentDefinition? {
        try agents.getDefinition(definitionId)
    }

    public func updateAgentDefinition(_ definition: NapaxiAgentDefinition) throws -> Bool {
        try agents.updateDefinition(definition)
    }

    public func deleteAgentDefinition(_ definitionId: String) throws -> Bool {
        try agents.deleteDefinition(definitionId)
    }

    public func importAgentMd(_ content: String) throws -> NapaxiAgentDefinition {
        try agents.importMarkdown(content)
    }

    public func listAvailableTools() throws -> [NapaxiToolInfo] {
        try agents.listAvailableTools()
    }

    public func createAgentFromDefinition(
        _ definitionId: String,
        config: NapaxiConfig? = nil
    ) throws -> Bool {
        try agents.createFromDefinition(definitionId, config: config)
    }

    public func createGroup(_ name: String, memberAgentIds: [String]) throws -> String {
        try groups.create(name: name, members: memberAgentIds)
    }

    public func deleteGroup(_ groupId: String) throws -> Bool {
        try groups.delete(groupId)
    }

    public func listGroups() throws -> [NapaxiGroupInfo] {
        try groups.list()
    }

    public func getGroup(_ groupId: String) throws -> NapaxiGroupInfo? {
        try groups.get(groupId)
    }

    public func renameGroup(_ groupId: String, newName: String) throws -> Bool {
        try groups.rename(groupId, newName: newName)
    }

    public func updateGroupMembers(_ groupId: String, memberAgentIds: [String]) throws -> Bool {
        try groups.updateMembers(groupId, members: memberAgentIds)
    }

    public func setGroupCustomPrompt(_ groupId: String, prompt: String?) throws -> Bool {
        try groups.setCustomPrompt(groupId, prompt: prompt)
    }

    public func getGroupMessages(_ groupId: String) throws -> [NapaxiGroupMessage] {
        try groups.messages(groupId)
    }

    public func clearGroupHistory(_ groupId: String) throws -> Bool {
        try groups.clearHistory(groupId)
    }

    public func sendToGroup(
        _ groupId: String,
        _ message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        try groups.send(groupId: groupId, message: message, maxIterations: maxIterations)
    }

    public func sendToGroupAgent(
        _ groupId: String,
        agentId: String,
        sessionKey: NapaxiSessionKey,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        try groups.sendToAgent(
            groupId: groupId,
            agentId: agentId,
            sessionKey: sessionKey,
            message: message,
            maxIterations: maxIterations
        )
    }

    public func exportGroupState() throws -> String {
        try groups.exportState()
    }

    public func importGroupState(_ stateJSON: String) throws -> Bool {
        try groups.importState(stateJSON: stateJSON)
    }

    public func readWorkspaceFile(
        _ path: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> NapaxiWorkspaceFile? {
        try workspace.readFile(path, accountId: accountId, agentId: agentId)
    }

    public func writeWorkspaceFile(
        _ path: String,
        content: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> Bool {
        try workspace.writeFile(path, content: content, accountId: accountId, agentId: agentId)
    }

    public func writeWorkspaceFile(
        _ path: String,
        _ content: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> Bool {
        try writeWorkspaceFile(path, content: content, accountId: accountId, agentId: agentId)
    }

    public func appendWorkspaceFile(
        _ path: String,
        content: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> Bool {
        try workspace.appendFile(path, content: content, accountId: accountId, agentId: agentId)
    }

    public func appendWorkspaceFile(
        _ path: String,
        _ content: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> Bool {
        try appendWorkspaceFile(path, content: content, accountId: accountId, agentId: agentId)
    }

    public func deleteWorkspaceFile(
        _ path: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> Bool {
        try workspace.deleteFile(path, accountId: accountId, agentId: agentId)
    }

    public func listWorkspaceFiles(
        _ directory: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> [NapaxiWorkspaceEntry] {
        try workspace.listFiles(directory: directory, accountId: accountId, agentId: agentId)
    }

    public func searchMemory(
        _ query: String,
        limit: Int = NapaxiWorkspaceAPI.defaultMemorySearchLimit,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> [NapaxiMemorySearchResult] {
        try workspace.searchMemory(query, limit: limit, accountId: accountId, agentId: agentId)
    }

    public func recallSessions(
        _ query: String,
        limit: Int = NapaxiWorkspaceAPI.defaultRecallSessionLimit,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId,
        currentThreadId: String = ""
    ) throws -> [NapaxiMemoryRecallSession] {
        try workspace.recallSessions(
            query,
            limit: limit,
            accountId: accountId,
            agentId: agentId,
            currentThreadId: currentThreadId
        )
    }

    public func rebuildRecallIndex(
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> NapaxiRecallIndexStats {
        try workspace.rebuildRecallIndex(accountId: accountId, agentId: agentId)
    }

    public func recallIndexStats(
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> NapaxiRecallIndexStats {
        try workspace.recallIndexStats(accountId: accountId, agentId: agentId)
    }

    public func listJournalDays(
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> [NapaxiJournalDay] {
        try workspace.listJournalDays(accountId: accountId, agentId: agentId)
    }

    public func readJournalDay(
        _ date: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> [NapaxiJournalTurnRecord] {
        try workspace.readJournalDay(date, accountId: accountId, agentId: agentId)
    }

    public func getSystemPrompt(
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> String {
        try workspace.systemPrompt(accountId: accountId, agentId: agentId)
    }

    public func reseedWorkspace(
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = NapaxiEngine.defaultWorkspaceAgentId
    ) throws -> Int {
        try workspace.reseed(accountId: accountId, agentId: agentId)
    }

    public func injectMessage(
        _ sessionKey: NapaxiSessionKey,
        _ message: String,
        agentId: String = NapaxiEngine.defaultAgentId,
        attachments: [NapaxiAttachment] = []
    ) throws -> Bool {
        try sessions.injectMessage(sessionKey, message, agentId: agentId, attachments: attachments)
    }

    public func saveAttachmentMetadata(
        threadId: String,
        userMessageIndex: Int,
        attachments: [NapaxiChatAttachment]
    ) throws -> Bool {
        try fileBridge.saveMessageAttachments(
            threadId: threadId,
            userMessageIndex: userMessageIndex,
            attachments: attachments
        )
    }

    public func retractInjectedMessage(_ sessionKey: NapaxiSessionKey, message: String) throws -> Bool {
        try sessions.retractInjectedMessage(sessionKey, message: message)
    }

    public func answerHumanRequest(requestId: String, response: String) throws -> Bool {
        try sessions.answerHumanRequest(requestId: requestId, response: response)
    }

    public func cancelSession(_ sessionKey: NapaxiSessionKey, agentId: String = NapaxiEngine.defaultAgentId) throws -> Bool {
        let cancellingRun = sessionRunTracker.cancelling(agentId: agentId, key: sessionKey)
        let cancelled = try sessions.cancelJSON(sessionKeyJSON: sessionKey.jsonString()).requiredBool()
        if cancelled, let cancellingRun {
            _ = sessionRunTracker.cancelled(cancellingRun)
        }
        return cancelled
    }

    public func resolveToolExecution(requestId: UInt64, resultJSON: String, isError: Bool) throws -> Bool {
        try NapaxiNativeBridge.resolveToolExecution(requestId: requestId, resultJSON: resultJSON, isError: isError)
    }

    public func dispose() {
        disposeResources()
    }

    public func updateBackgroundConfig(_ config: NapaxiBackgroundConfig) {
        backgroundController?.updateConfig(config)
    }

    public var onBackgroundAction: AsyncStream<NapaxiBackgroundActionEvent> {
        backgroundController?.onAction ?? AsyncStream { $0.finish() }
    }

    public func startBackgroundService() async throws {
        guard let backgroundController, let config = backgroundController.currentConfig else { return }
        try await backgroundController.start(config)
        startBackgroundActionListener()
    }

    public func stopBackgroundService() async throws {
        backgroundActionTask?.cancel()
        backgroundActionTask = nil
        try await backgroundController?.stop()
    }

    private func wrapWithBackground(
        _ rawStream: AsyncThrowingStream<NapaxiChatEvent, Error>
    ) -> AsyncThrowingStream<NapaxiChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let controller = backgroundController
                var endedWithError = false
                if let controller, let config = controller.currentConfig, !controller.isRunning {
                    try? await controller.start(config)
                    startBackgroundActionListener()
                }
                do {
                    for try await event in rawStream {
                        if let controller {
                            let runs = activeSessionRuns
                            let activeCount = max(runs.count, 1)
                            let waitingCount = runs.filter(\.needsInput).count
                            if await controller.handleChatEvent(
                                event,
                                activeRunCount: activeCount,
                                waitingRunCount: waitingCount
                            ) {
                                endedWithError = true
                            }
                        }
                        continuation.yield(event)
                    }
                    await controller?.finishChatStream(
                        endedWithError: endedWithError,
                        activeRunCount: activeSessionRuns.count
                    )
                    continuation.finish()
                } catch {
                    endedWithError = true
                    if let controller {
                        let title = controller.currentConfig?.notificationConfig.ongoingTitle ?? "Napaxi Agent"
                        let prefix = controller.currentConfig?.notificationConfig.errorPrefix ?? "Error"
                        try? await controller.showErrorNotification(
                            title: title,
                            message: "\(prefix): \(String(describing: error))"
                        )
                        try? await controller.stop()
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func startBackgroundActionListener() {
        guard backgroundActionTask == nil, let backgroundController else { return }
        backgroundActionTask = Task { [weak self, backgroundController] in
            for await event in backgroundController.onAction {
                await self?.handleBackgroundAction(event)
            }
        }
    }

    private func handleBackgroundAction(_ event: NapaxiBackgroundActionEvent) async {
        switch event.action {
        case .stop:
            let runs = activeSessionRuns
            for run in runs {
                _ = try? cancelSession(run.key, agentId: run.agentId)
            }
            try? await backgroundController?.stop()
        case .hitlApprove:
            if let requestId = event.requestId?.nilIfEmpty ?? singleWaitingRequestId() {
                _ = try? answerHumanRequest(requestId: requestId, response: event.payload ?? "approved")
            }
        case .hitlDeny:
            if let requestId = event.requestId?.nilIfEmpty ?? singleWaitingRequestId() {
                _ = try? answerHumanRequest(requestId: requestId, response: event.payload ?? "denied")
            }
        case .viewResult, .agentTrigger, .automationWake:
            break
        }
    }

    private func singleWaitingRequestId() -> String? {
        let waiting = activeSessionRuns
            .filter(\.needsInput)
            .compactMap { $0.humanRequestId?.nilIfEmpty }
        return waiting.count == 1 ? waiting[0] : nil
    }

    private func trackSessionRun(
        _ rawStream: AsyncThrowingStream<NapaxiChatEvent, Error>,
        initialRun: NapaxiSessionRunInfo
    ) -> AsyncThrowingStream<NapaxiChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var currentRun = initialRun
                do {
                    for try await event in rawStream {
                        currentRun = sessionRunTracker.apply(event: event, to: currentRun)
                        continuation.yield(event)
                    }
                    if !currentRun.isTerminal {
                        _ = sessionRunTracker.complete(currentRun)
                    }
                    continuation.finish()
                } catch {
                    _ = sessionRunTracker.fail(currentRun, error: error)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func defaultCapabilityProfile(
        hasCustomToolExecutor: Bool,
        hasAgentAppActionExecutor: Bool,
        hasBrowserController: Bool,
        enablePlatformTools: Bool,
        enableAutomation: Bool,
        ishRootfsAvailable: Bool
    ) -> NapaxiCapabilityProfile {
        NapaxiCapabilityProfile(
            platform: "ios",
            supportedCapabilities: [
                NapaxiChannelCapability.im,
                NapaxiChannelCapability.device,
                hasCustomToolExecutor ? "napaxi.tool.custom_host" : nil,
                hasAgentAppActionExecutor ? "napaxi.tool.agent_app_action" : nil,
                enablePlatformTools ? "napaxi.platform_tool.*" : nil,
                hasBrowserController ? "napaxi.tool.browser" : nil,
                enableAutomation ? "napaxi.service.automation" : nil,
            ].compactMap { $0 },
            disabledCapabilities: NapaxiIshSupport.disabledCapabilities(rootfsAvailable: ishRootfsAvailable)
        )
    }

    private func attachmentsJSON(_ attachments: [NapaxiAttachment]) throws -> String {
        try NapaxiAttachment.jsonString(for: attachments)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
