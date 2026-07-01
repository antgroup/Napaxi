import Foundation

public struct NapaxiNotificationConfig: Codable, Equatable, Sendable {
    public var channelName: String
    public var channelDescription: String
    public var ongoingTitle: String
    public var ongoingMessage: String
    public var hitlTitle: String
    public var hitlChannelSuffix: String
    public var hitlChannelDescription: String
    public var completionChannelSuffix: String
    public var completionChannelDescription: String
    public var completionMessage: String
    public var errorPrefix: String
    public var stopActionLabel: String
    public var openActionLabel: String

    public init(
        channelName: String = "Agent",
        channelDescription: String = "Napaxi Agent is running",
        ongoingTitle: String = "Napaxi Agent",
        ongoingMessage: String = "Agent is running...",
        hitlTitle: String = "Agent needs confirmation",
        hitlChannelSuffix: String = "Confirmation",
        hitlChannelDescription: String = "Notifications requiring your confirmation",
        completionChannelSuffix: String = "Completed",
        completionChannelDescription: String = "Task completion notifications",
        completionMessage: String = "Task completed",
        errorPrefix: String = "Error",
        stopActionLabel: String = "Stop",
        openActionLabel: String = "Open"
    ) {
        self.channelName = channelName
        self.channelDescription = channelDescription
        self.ongoingTitle = ongoingTitle
        self.ongoingMessage = ongoingMessage
        self.hitlTitle = hitlTitle
        self.hitlChannelSuffix = hitlChannelSuffix
        self.hitlChannelDescription = hitlChannelDescription
        self.completionChannelSuffix = completionChannelSuffix
        self.completionChannelDescription = completionChannelDescription
        self.completionMessage = completionMessage
        self.errorPrefix = errorPrefix
        self.stopActionLabel = stopActionLabel
        self.openActionLabel = openActionLabel
    }
}

public struct NapaxiBackgroundConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var notificationConfig: NapaxiNotificationConfig
    public var wakeLockTimeoutMilliseconds: Int
    public var wakeLockTimeout: TimeInterval {
        get { TimeInterval(wakeLockTimeoutMilliseconds) / 1_000.0 }
        set { wakeLockTimeoutMilliseconds = Int(newValue * 1_000.0) }
    }

    public init(
        enabled: Bool = true,
        notificationConfig: NapaxiNotificationConfig = NapaxiNotificationConfig(),
        wakeLockTimeoutMilliseconds: Int = 30 * 60 * 1_000
    ) {
        self.enabled = enabled
        self.notificationConfig = notificationConfig
        self.wakeLockTimeoutMilliseconds = wakeLockTimeoutMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: NapaxiJSONValue].self)
        self.init(
            enabled: object["enabled"]?.boolValue ?? true,
            notificationConfig: NapaxiNotificationConfig(
                channelName: object["channelName"]?.stringValue ?? "Agent",
                channelDescription: object["channelDescription"]?.stringValue ?? "Napaxi Agent is running",
                ongoingTitle: object["ongoingTitle"]?.stringValue ?? "Napaxi Agent",
                ongoingMessage: object["ongoingMessage"]?.stringValue ?? "Agent is running...",
                hitlTitle: object["hitlTitle"]?.stringValue ?? "Agent needs confirmation",
                hitlChannelSuffix: object["hitlChannelSuffix"]?.stringValue ?? "Confirmation",
                hitlChannelDescription: object["hitlChannelDescription"]?.stringValue ?? "Notifications requiring your confirmation",
                completionChannelSuffix: object["completionChannelSuffix"]?.stringValue ?? "Completed",
                completionChannelDescription: object["completionChannelDescription"]?.stringValue ?? "Task completion notifications",
                completionMessage: object["completionMessage"]?.stringValue ?? "Task completed",
                errorPrefix: object["errorPrefix"]?.stringValue ?? "Error",
                stopActionLabel: object["stopActionLabel"]?.stringValue ?? "Stop",
                openActionLabel: object["openActionLabel"]?.stringValue ?? "Open"
            ),
            wakeLockTimeoutMilliseconds: object["wakeLockTimeoutMs"]?.napaxiIntValue ?? 30 * 60 * 1_000
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NapaxiJSONValue.object(toMap()))
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        [
            "enabled": .bool(enabled),
            "channelName": .string(notificationConfig.channelName),
            "channelDescription": .string(notificationConfig.channelDescription),
            "ongoingTitle": .string(notificationConfig.ongoingTitle),
            "ongoingMessage": .string(notificationConfig.ongoingMessage),
            "hitlTitle": .string(notificationConfig.hitlTitle),
            "hitlChannelSuffix": .string(notificationConfig.hitlChannelSuffix),
            "hitlChannelDescription": .string(notificationConfig.hitlChannelDescription),
            "completionChannelSuffix": .string(notificationConfig.completionChannelSuffix),
            "completionChannelDescription": .string(notificationConfig.completionChannelDescription),
            "completionMessage": .string(notificationConfig.completionMessage),
            "errorPrefix": .string(notificationConfig.errorPrefix),
            "stopActionLabel": .string(notificationConfig.stopActionLabel),
            "openActionLabel": .string(notificationConfig.openActionLabel),
            "wakeLockTimeoutMs": .number(Double(wakeLockTimeoutMilliseconds)),
        ]
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toMap())
    }
}

public enum NapaxiBackgroundAction: String, Codable, Equatable, Sendable {
    case stop
    case hitlApprove
    case hitlDeny
    case viewResult
    case agentTrigger
    /// A platform scheduler wake fired for a mobile automation job. Mirrors the
    /// Flutter `BackgroundAction.automationWake`. Inert on iOS (no platform
    /// scheduler), but kept for cross-adapter enum parity.
    case automationWake

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .stop
    }
}

public struct NapaxiBackgroundActionEvent: Codable, Equatable, Sendable {
    public var action: NapaxiBackgroundAction
    public var requestId: String?
    public var payload: String?

    public init(action: NapaxiBackgroundAction, requestId: String? = nil, payload: String? = nil) {
        self.action = action
        self.requestId = requestId
        self.payload = payload
    }
}

public func isBackgroundExecutionSupported() -> Bool {
    false
}

public protocol NapaxiBackgroundPermissionHost: AnyObject {
    func checkNapaxiNotificationPermission() async -> Bool
    func requestNapaxiNotificationPermission() async -> Bool
    func canRunNapaxiInBackground() async -> Bool
}

public struct NapaxiBackgroundPermissions {
    public let host: NapaxiBackgroundPermissionHost?

    public init(host: NapaxiBackgroundPermissionHost? = nil) {
        self.host = host
    }

    public static var isSupported: Bool { false }

    public var isSupported: Bool {
        Self.isSupported
    }

    public static func checkNotificationPermission() async -> Bool {
        true
    }

    public func checkNotificationPermission() async -> Bool {
        if let host {
            return await host.checkNapaxiNotificationPermission()
        }
        return await Self.checkNotificationPermission()
    }

    public static func requestNotificationPermission() async -> Bool {
        true
    }

    public func requestNotificationPermission() async -> Bool {
        if let host {
            return await host.requestNapaxiNotificationPermission()
        }
        return await Self.requestNotificationPermission()
    }

    public static func canRunInBackground() async -> Bool {
        false
    }

    public func canRunInBackground() async -> Bool {
        if let host {
            return await host.canRunNapaxiInBackground()
        }
        return await Self.canRunInBackground()
    }
}

public protocol NapaxiBackgroundHost: AnyObject {
    func startBackgroundExecution(config: NapaxiBackgroundConfig) async throws
    func stopBackgroundExecution() async throws
    func updateBackgroundNotification(message: String?, progress: Int?) async throws
    func showHitlNotification(requestId: String, question: String, options: [String]?) async throws
    func showCompletionNotification(title: String, message: String) async throws
    func showErrorNotification(title: String, message: String) async throws
    func cancelBackgroundNotification(notificationId: Int?) async throws
}

public final class NapaxiBackgroundController: @unchecked Sendable {
    public private(set) var isRunning = false
    public private(set) var currentConfig: NapaxiBackgroundConfig?

    private let host: NapaxiBackgroundHost?
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<NapaxiBackgroundActionEvent>.Continuation] = [:]

    public init(config: NapaxiBackgroundConfig? = nil, host: NapaxiBackgroundHost? = nil) {
        self.currentConfig = config
        self.host = host
    }

    public var onAction: AsyncStream<NapaxiBackgroundActionEvent> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    public func updateConfig(_ config: NapaxiBackgroundConfig) {
        currentConfig = config
    }

    public func start(_ config: NapaxiBackgroundConfig) async throws {
        guard config.enabled else {
            isRunning = false
            return
        }
        guard let host else {
            isRunning = false
            return
        }
        currentConfig = config
        try await host.startBackgroundExecution(config: config)
        isRunning = true
    }

    public func stop() async throws {
        guard let host else {
            isRunning = false
            return
        }
        if isRunning {
            try await host.stopBackgroundExecution()
        }
        isRunning = false
        currentConfig = nil
    }

    public func updateNotification(message: String? = nil, progress: Int? = nil) async throws {
        guard isRunning, let host else { return }
        try await host.updateBackgroundNotification(message: message, progress: progress)
    }

    public func showHitlNotification(requestId: String, question: String, options: [String]? = nil) async throws {
        guard isRunning, let host else { return }
        try await host.showHitlNotification(requestId: requestId, question: question, options: options)
    }

    public func showCompletionNotification(title: String = "Napaxi Agent", message: String = "Task completed") async throws {
        guard isRunning, let host else { return }
        try await host.showCompletionNotification(title: title, message: message)
    }

    public func showErrorNotification(title: String = "Napaxi Agent", message: String = "An error occurred") async throws {
        guard isRunning, let host else { return }
        try await host.showErrorNotification(title: title, message: message)
    }

    @discardableResult
    public func handleChatEvent(
        _ event: NapaxiChatEvent,
        activeRunCount: Int = 1,
        waitingRunCount: Int = 0
    ) async -> Bool {
        guard isRunning else { return false }
        do {
            switch event.type {
            case "tool_call":
                try await updateNotificationOrSummary(
                    message: "Running: \(event.name)",
                    activeRunCount: activeRunCount,
                    waitingRunCount: waitingRunCount
                )
            case "tool_call_delta":
                let name = event.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    try await updateNotificationOrSummary(
                        message: "Preparing: \(name)",
                        activeRunCount: activeRunCount,
                        waitingRunCount: waitingRunCount
                    )
                }
            case "agent_tool_call":
                try await updateNotificationOrSummary(
                    message: "Agent \(event.agentId): \(event.name)",
                    activeRunCount: activeRunCount,
                    waitingRunCount: waitingRunCount
                )
            case "agent_tool_call_delta":
                let name = event.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    try await updateNotificationOrSummary(
                        message: "Agent \(event.agentId): preparing \(name)",
                        activeRunCount: activeRunCount,
                        waitingRunCount: waitingRunCount
                    )
                }
            case "asking_human":
                if waitingRunCount <= 1 {
                    try await showHitlNotification(
                        requestId: event.requestId,
                        question: event.question,
                        options: event.options.isEmpty ? nil : event.options
                    )
                } else {
                    try await updateNotification(message: "\(waitingRunCount) sessions need input")
                }
            case "error":
                try await showErrorNotification(
                    title: currentConfig?.notificationConfig.ongoingTitle ?? "Napaxi Agent",
                    message: event.message
                )
                try await stop()
                return true
            case "skill_activated":
                try await updateNotificationOrSummary(
                    message: skillActivity(event),
                    activeRunCount: activeRunCount,
                    waitingRunCount: waitingRunCount
                )
            default:
                break
            }
        } catch {
            return false
        }
        return false
    }

    public func finishChatStream(endedWithError: Bool, activeRunCount: Int = 0) async {
        guard isRunning, !endedWithError, activeRunCount == 0 else { return }
        do {
            try await showCompletionNotification(
                title: currentConfig?.notificationConfig.ongoingTitle ?? "Napaxi Agent",
                message: currentConfig?.notificationConfig.completionMessage ?? "Task completed"
            )
            try await stop()
        } catch {
            try? await stop()
        }
    }

    public func cancelNotification(notificationId: Int? = nil) async throws {
        guard let host else { return }
        try await host.cancelBackgroundNotification(notificationId: notificationId)
    }

    public func emitAction(_ event: NapaxiBackgroundActionEvent) {
        lock.lock()
        let sinks = Array(continuations.values)
        lock.unlock()
        for sink in sinks {
            sink.yield(event)
        }
    }

    public func dispose() {
        lock.lock()
        let sinks = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for sink in sinks {
            sink.finish()
        }
        isRunning = false
        currentConfig = nil
    }

    private func updateNotificationOrSummary(
        message: String,
        activeRunCount: Int,
        waitingRunCount: Int
    ) async throws {
        if activeRunCount > 1 {
            let suffix = waitingRunCount == 0 ? "" : " · \(waitingRunCount) waiting"
            try await updateNotification(message: "\(activeRunCount) sessions running\(suffix)")
        } else {
            try await updateNotification(message: message)
        }
    }

    private func skillActivity(_ event: NapaxiChatEvent) -> String {
        let skills = event.activatedSkills
        if skills.count == 1 {
            let name = skills[0].name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Using skill" : "Using skill: \(name)"
        }
        return "Using \(skills.count) skills"
    }
}

public struct NapaxiBackgroundAPI: Sendable {
    public let controller: NapaxiBackgroundController?

    public var onAction: AsyncStream<NapaxiBackgroundActionEvent> {
        controller?.onAction ?? AsyncStream { $0.finish() }
    }

    public func startService() async throws {
        guard let controller, let config = controller.currentConfig else { return }
        try await controller.start(config)
    }

    public func stopService() async throws {
        try await controller?.stop()
    }

    public func updateConfig(_ config: NapaxiBackgroundConfig) {
        controller?.updateConfig(config)
    }
}
