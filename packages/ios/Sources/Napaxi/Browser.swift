import Foundation

public enum NapaxiBrowserMutationPolicy: String, Codable, Equatable, Sendable {
    case requireApproval
    case allowAll
}

public enum NapaxiBrowserViewportMode: String, Codable, Equatable, Sendable {
    case desktop
    case mobile
}

public enum NapaxiBrowserScreenshotMode: String, Codable, Equatable, Sendable {
    case auto
    case never
    case always
}

public typealias BrowserMutationPolicy = NapaxiBrowserMutationPolicy
public typealias BrowserViewportMode = NapaxiBrowserViewportMode
public typealias BrowserScreenshotMode = NapaxiBrowserScreenshotMode
public typealias BrowserBackendCapabilities = NapaxiBrowserBackendCapabilities

public let NapaxiDesktopUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

public let napaxiDesktopUserAgent = NapaxiDesktopUserAgent

public struct NapaxiBrowserBackendCapabilities: Codable, Equatable, Sendable {
    public var supportsScreenshot: Bool
    public var supportsCoordinateClick: Bool
    public var supportsEarlyScriptInjection: Bool
    public var supportsCdpSelectorMap: Bool

    public init(
        supportsScreenshot: Bool = false,
        supportsCoordinateClick: Bool = true,
        supportsEarlyScriptInjection: Bool = false,
        supportsCdpSelectorMap: Bool = false
    ) {
        self.supportsScreenshot = supportsScreenshot
        self.supportsCoordinateClick = supportsCoordinateClick
        self.supportsEarlyScriptInjection = supportsEarlyScriptInjection
        self.supportsCdpSelectorMap = supportsCdpSelectorMap
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiBrowserJSON(decoder: decoder)
        self.init(
            supportsScreenshot: object.bool("supports_screenshot", "supportsScreenshot") ?? false,
            supportsCoordinateClick: object.bool("supports_coordinate_click", "supportsCoordinateClick") ?? true,
            supportsEarlyScriptInjection: object.bool("supports_early_script_injection", "supportsEarlyScriptInjection") ?? false,
            supportsCdpSelectorMap: object.bool("supports_cdp_selector_map", "supportsCdpSelectorMap") ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        try jsonValue().encode(to: encoder)
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        jsonValue().napaxiObjectValue
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object([
            "supports_screenshot": .bool(supportsScreenshot),
            "supports_coordinate_click": .bool(supportsCoordinateClick),
            "supports_early_script_injection": .bool(supportsEarlyScriptInjection),
            "supports_cdp_selector_map": .bool(supportsCdpSelectorMap),
        ])
    }
}

public struct NapaxiBrowserScreenshot: Codable, Equatable, Sendable {
    public var sandboxPath: String
    public var width: Int
    public var height: Int
    public var mimeType: String

    public init(sandboxPath: String, width: Int, height: Int, mimeType: String = "image/png") {
        self.sandboxPath = sandboxPath
        self.width = width
        self.height = height
        self.mimeType = mimeType
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiBrowserJSON(decoder: decoder)
        self.init(
            sandboxPath: object.string("sandbox_path", "sandboxPath") ?? "",
            width: object.int("width") ?? 0,
            height: object.int("height") ?? 0,
            mimeType: object.string("mime_type", "mimeType") ?? "image/png"
        )
    }

    public func encode(to encoder: Encoder) throws {
        try jsonValue().encode(to: encoder)
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        jsonValue().napaxiObjectValue
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object([
            "sandbox_path": .string(sandboxPath),
            "mime_type": .string(mimeType),
            "width": .number(Double(width)),
            "height": .number(Double(height)),
        ])
    }
}

public struct NapaxiBrowserSnapshot: Codable, Equatable, Sendable {
    public var url: String
    public var title: String
    public var loading: Bool
    public var browserMode: NapaxiBrowserViewportMode
    public var userAgent: String?
    public var text: String
    public var elements: [[String: NapaxiJSONValue]]
    public var pageState: [String: NapaxiJSONValue]
    public var viewportMap: [String: NapaxiJSONValue]
    public var pageChangeToken: String
    public var lastActionEffect: [String: NapaxiJSONValue]?
    public var backendCapabilities: NapaxiBrowserBackendCapabilities
    public var screenshot: NapaxiBrowserScreenshot?

    public init(
        url: String,
        title: String,
        loading: Bool,
        browserMode: NapaxiBrowserViewportMode,
        userAgent: String? = nil,
        text: String,
        elements: [[String: NapaxiJSONValue]] = [],
        pageState: [String: NapaxiJSONValue] = [:],
        viewportMap: [String: NapaxiJSONValue] = [:],
        pageChangeToken: String,
        lastActionEffect: [String: NapaxiJSONValue]? = nil,
        backendCapabilities: NapaxiBrowserBackendCapabilities = NapaxiBrowserBackendCapabilities(),
        screenshot: NapaxiBrowserScreenshot? = nil
    ) {
        self.url = url
        self.title = title
        self.loading = loading
        self.browserMode = browserMode
        self.userAgent = userAgent
        self.text = text
        self.elements = elements
        self.pageState = pageState
        self.viewportMap = viewportMap
        self.pageChangeToken = pageChangeToken
        self.lastActionEffect = lastActionEffect
        self.backendCapabilities = backendCapabilities
        self.screenshot = screenshot
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiBrowserJSON(decoder: decoder)
        self.init(
            url: object.string("url") ?? "",
            title: object.string("title") ?? "",
            loading: object.bool("loading") ?? false,
            browserMode: object.string("browser_mode", "browserMode").flatMap(NapaxiBrowserViewportMode.init(rawValue:)) ?? .mobile,
            userAgent: object.string("user_agent", "userAgent"),
            text: object.string("text") ?? "",
            elements: object.objectArray("elements"),
            pageState: object.object("page_state", "pageState") ?? [:],
            viewportMap: object.object("viewport_map", "viewportMap") ?? [:],
            pageChangeToken: object.string("page_change_token", "pageChangeToken") ?? "",
            lastActionEffect: object.object("last_action_effect", "lastActionEffect"),
            backendCapabilities: object.decode(NapaxiBrowserBackendCapabilities.self, "backend_capabilities", "backendCapabilities")
                ?? NapaxiBrowserBackendCapabilities(),
            screenshot: object.decode(NapaxiBrowserScreenshot.self, "screenshot")
        )
    }

    public func encode(to encoder: Encoder) throws {
        try jsonValue().encode(to: encoder)
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        jsonValue().napaxiObjectValue
    }

    public func jsonValue() -> NapaxiJSONValue {
        var object: [String: NapaxiJSONValue] = [
            "url": .string(url),
            "title": .string(title),
            "loading": .bool(loading),
            "browser_mode": .string(browserMode.rawValue),
            "text": .string(text),
            "elements": .array(elements.map { .object($0) }),
            "page_state": .object(pageState),
            "viewport_map": .object(viewportMap),
            "page_change_token": .string(pageChangeToken),
            "backend_capabilities": backendCapabilities.jsonValue(),
            "screenshot_available": .bool(screenshot != nil),
        ]
        if let userAgent {
            object["user_agent"] = .string(userAgent)
        }
        if let lastActionEffect {
            object["last_action_effect"] = .object(lastActionEffect)
        }
        if let screenshot {
            object["screenshot"] = screenshot.jsonValue()
        }
        return .object(object)
    }

    public func jsonString() throws -> String {
        try NapaxiRawJSON(jsonValue()).jsonString()
    }
}

public struct NapaxiBrowserToolRequest: Codable, Equatable, Sendable {
    public var toolName: String
    public var params: [String: NapaxiJSONValue]
    public var rawParamsJSON: String

    public init(toolName: String, params: [String: NapaxiJSONValue] = [:], rawParamsJSON: String? = nil) {
        self.toolName = toolName
        self.params = params
        self.rawParamsJSON = rawParamsJSON ?? (try? params.jsonString()) ?? "{}"
    }

    public init(toolName: String, paramsJSON: String) throws {
        let raw = paramsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = raw.isEmpty ? NapaxiJSONValue.object([:]) : try NapaxiRawJSON(jsonString: raw).value
        self.init(toolName: toolName, params: value.napaxiObjectValue, rawParamsJSON: raw.isEmpty ? "{}" : paramsJSON)
    }

    public var url: String? { params["url"]?.stringValue }
    public var elementId: String? { params["element_id"]?.stringValue }
    public var text: String? { params["text"]?.stringValue }
    public var mode: NapaxiBrowserViewportMode? {
        Self.parseBrowserMode(params["mode"])
    }
    public var screenshotMode: NapaxiBrowserScreenshotMode? {
        Self.parseScreenshotMode(params["screenshot_mode"])
    }

    private static func parseBrowserMode(_ value: NapaxiJSONValue?) -> NapaxiBrowserViewportMode? {
        guard let value else { return .mobile }
        guard let string = value.stringValue else { return nil }
        return NapaxiBrowserViewportMode(rawValue: string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func parseScreenshotMode(_ value: NapaxiJSONValue?) -> NapaxiBrowserScreenshotMode? {
        guard let value else { return .auto }
        guard let string = value.stringValue else { return nil }
        return NapaxiBrowserScreenshotMode(rawValue: string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

private struct NapaxiBrowserJSON {
    private let object: [String: NapaxiJSONValue]

    init(decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        object = try container.decode([String: NapaxiJSONValue].self)
    }

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = object[key]?.stringValue {
                return value
            }
        }
        return nil
    }

    func bool(_ keys: String...) -> Bool? {
        for key in keys {
            if let value = object[key]?.boolValue {
                return value
            }
        }
        return nil
    }

    func int(_ keys: String...) -> Int? {
        for key in keys {
            if let number = object[key]?.numberValue {
                return Int(number)
            }
            if let string = object[key]?.stringValue, let parsed = Int(string) {
                return parsed
            }
        }
        return nil
    }

    func object(_ keys: String...) -> [String: NapaxiJSONValue]? {
        for key in keys {
            if case .object(let value)? = object[key] {
                return value
            }
        }
        return nil
    }

    func objectArray(_ key: String) -> [[String: NapaxiJSONValue]] {
        guard case .array(let values)? = object[key] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value else { return nil }
            return object
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ keys: String...) -> T? {
        for key in keys {
            guard let value = object[key],
                  let data = try? NapaxiRawJSON(value).data(),
                  let decoded = try? JSONDecoder().decode(T.self, from: data) else {
                continue
            }
            return decoded
        }
        return nil
    }
}

public struct NapaxiBrowserToolResult: Codable, Equatable, Sendable {
    public var raw: [String: NapaxiJSONValue]

    public init(raw: [String: NapaxiJSONValue]) {
        self.raw = raw
    }

    public static func success(
        action: String,
        values: [String: NapaxiJSONValue] = [:]
    ) -> NapaxiBrowserToolResult {
        var object = values
        object["success"] = .bool(true)
        object["action"] = .string(action)
        return NapaxiBrowserToolResult(raw: object)
    }

    public static func failure(
        action: String,
        message: String,
        failureCode: String? = nil
    ) -> NapaxiBrowserToolResult {
        var object: [String: NapaxiJSONValue] = [
            "success": .bool(false),
            "action": .string(action),
            "blocked_or_approval_reason": .string(message),
            "error": .string(message),
        ]
        if let failureCode {
            object["failure_code"] = .string(failureCode)
        }
        return NapaxiBrowserToolResult(raw: object)
    }

    public static func approvalDenied(
        action: String,
        message: String = "Browser action requires user approval"
    ) -> NapaxiBrowserToolResult {
        NapaxiBrowserToolResult(raw: [
            "success": .bool(false),
            "action": .string(action),
            "blocked_or_approval_reason": .string(message),
        ])
    }

    public func jsonString() throws -> String {
        try raw.jsonString()
    }
}

public protocol NapaxiBrowserToolExecutor: AnyObject {
    func executeBrowserTool(_ request: NapaxiBrowserToolRequest) async throws -> NapaxiBrowserToolResult
}

public protocol NapaxiBrowserSnapshotProvider: AnyObject {
    var latestBrowserSnapshot: NapaxiBrowserSnapshot? { get }
}

public enum NapaxiBrowserToolProvider {
    public static let capabilityId = "napaxi.tool.browser"

    public static let toolNames: Set<String> = [
        "browser_open",
        "browser_snapshot",
        "browser_click",
        "browser_type",
        "browser_scroll",
        "browser_wait",
        "browser_find_text",
        "browser_keys",
        "browser_back",
        "browser_close",
    ]

    public static func isBrowserTool(_ name: String) -> Bool {
        toolNames.contains(name)
    }

    public static func getToolDefinitions() -> [NapaxiCustomToolDefinition] {
        toolDefinitions
    }

    private static let toolDefinitions: [NapaxiCustomToolDefinition] = [
        NapaxiCustomToolDefinition(
            name: "browser_open",
            description: "Open an absolute http:// or https:// URL in the persistent visible browser session.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "url": .object(["type": .string("string"), "pattern": .string("^https?://")]),
                    "mode": .object(["type": .string("string"), "enum": .array([.string("desktop"), .string("mobile")])]),
                    "force_reload": .object(["type": .string("boolean")]),
                ]),
                "required": .array([.string("url")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(
            name: "browser_snapshot",
            description: "Read the current browser page state.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "screenshot_mode": .object([
                        "type": .string("string"),
                        "enum": .array([.string("auto"), .string("never"), .string("always")]),
                    ]),
                ]),
            ],
            effect: "read"
        ),
        NapaxiCustomToolDefinition(
            name: "browser_click",
            description: "Click an element in the current browser page.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "element_id": .object(["type": .string("string")]),
                    "index": .object(["type": .string("integer")]),
                    "selector": .object(["type": .string("string")]),
                    "text": .object(["type": .string("string")]),
                    "label": .object(["type": .string("string")]),
                    "click_point": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "x": .object(["type": .string("number")]),
                            "y": .object(["type": .string("number")]),
                        ]),
                        "required": .array([.string("x"), .string("y")]),
                    ]),
                ]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(
            name: "browser_type",
            description: "Type text into the current browser page.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string")]),
                    "element_id": .object(["type": .string("string")]),
                    "index": .object(["type": .string("integer")]),
                    "selector": .object(["type": .string("string")]),
                    "label": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("text")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(name: "browser_scroll", description: "Scroll the current browser page.", effect: "external"),
        NapaxiCustomToolDefinition(
            name: "browser_wait",
            description: "Wait for the browser page to load or contain text.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "milliseconds": .object(["type": .string("integer")]),
                    "text": .object(["type": .string("string")]),
                    "scroll_to_text": .object(["type": .string("boolean")]),
                ]),
            ],
            effect: "read"
        ),
        NapaxiCustomToolDefinition(
            name: "browser_find_text",
            description: "Find visible text and scroll it into view.",
            parameters: [
                "type": .string("object"),
                "properties": .object(["text": .object(["type": .string("string")])]),
                "required": .array([.string("text")]),
            ],
            effect: "read"
        ),
        NapaxiCustomToolDefinition(
            name: "browser_keys",
            description: "Send simple keyboard keys to the focused browser element.",
            parameters: [
                "type": .string("object"),
                "properties": .object(["keys": .object(["type": .string("string")])]),
                "required": .array([.string("keys")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(name: "browser_back", description: "Navigate the browser session back if possible.", effect: "external"),
        NapaxiCustomToolDefinition(name: "browser_close", description: "Close or clear the persistent browser session.", effect: "external"),
    ]
}

public typealias BrowserToolProvider = NapaxiBrowserToolProvider

public extension NapaxiBrowserController {
    func executeTool(_ toolName: String, _ paramsJson: String) async throws -> String {
        try await executeBrowserTool(toolName: toolName, paramsJSON: paramsJson)
    }

    func notifyBackendStateChanged() {}
}

public extension NapaxiBrowserController where Self: NapaxiBrowserSnapshotProvider {
    var latestSnapshot: NapaxiBrowserSnapshot? { latestBrowserSnapshot }
}

public final class NapaxiBrowserToolHost {
    public let controller: NapaxiBrowserController
    public let approvalHandler: NapaxiToolApprovalHandler?
    public let structuredApprovalHandler: NapaxiStructuredToolApprovalHandler?
    public let mutationPolicy: NapaxiBrowserMutationPolicy

    private let gatedController: NapaxiBrowserApprovalController

    public init(
        controller: NapaxiBrowserController,
        approvalHandler: NapaxiToolApprovalHandler? = nil,
        structuredApprovalHandler: NapaxiStructuredToolApprovalHandler? = nil,
        mutationPolicy: NapaxiBrowserMutationPolicy = .requireApproval
    ) {
        self.controller = controller
        self.approvalHandler = approvalHandler
        self.structuredApprovalHandler = structuredApprovalHandler
        self.mutationPolicy = mutationPolicy
        self.gatedController = NapaxiBrowserApprovalController(
            controller: controller,
            mutationPolicy: mutationPolicy,
            approvalHandler: approvalHandler,
            structuredApprovalHandler: structuredApprovalHandler
        )
    }

    public func canHandle(_ toolName: String) -> Bool {
        NapaxiBrowserToolProvider.isBrowserTool(toolName)
    }

    public func execute(_ toolName: String, paramsJSON: String) async throws -> String {
        try await gatedController.executeBrowserTool(toolName: toolName, paramsJSON: paramsJSON)
    }
}

public typealias FlutterBrowserToolHost = NapaxiBrowserToolHost

final class NapaxiBrowserApprovalController: NapaxiBrowserController {
    private let controller: NapaxiBrowserController
    private let mutationPolicy: NapaxiBrowserMutationPolicy
    private let approvalHandler: NapaxiToolApprovalHandler?
    private let structuredApprovalHandler: NapaxiStructuredToolApprovalHandler?

    init(
        controller: NapaxiBrowserController,
        mutationPolicy: NapaxiBrowserMutationPolicy,
        approvalHandler: NapaxiToolApprovalHandler?,
        structuredApprovalHandler: NapaxiStructuredToolApprovalHandler?
    ) {
        self.controller = controller
        self.mutationPolicy = mutationPolicy
        self.approvalHandler = approvalHandler
        self.structuredApprovalHandler = structuredApprovalHandler
    }

    func executeBrowserTool(toolName: String, paramsJSON: String) async throws -> String {
        if let approvalReason = approvalReason(toolName: toolName, paramsJSON: paramsJSON) {
            let approved = await requestApproval(
                toolName: toolName,
                description: approvalReason,
                paramsJSON: paramsJSON
            )
            if !approved {
                return try NapaxiBrowserToolResult.approvalDenied(action: toolName).jsonString()
            }
        }
        do {
            return try await controller.executeBrowserTool(toolName: toolName, paramsJSON: paramsJSON)
        } catch {
            return try NapaxiBrowserToolResult.failure(
                action: toolName,
                message: String(describing: error)
            ).jsonString()
        }
    }

    private func approvalReason(toolName: String, paramsJSON: String) -> String? {
        guard mutationPolicy != .allowAll else { return nil }
        let request = try? NapaxiBrowserToolRequest(toolName: toolName, paramsJSON: paramsJSON)
        let params = request?.params ?? [:]

        if toolName == "browser_type", params["submit"]?.boolValue == true {
            return "Approve browser typing and submit"
        }
        guard toolName == "browser_click" else { return nil }
        if isPresent(params["click_point"]), !isPresent(params["element_id"]) {
            return "Approve coordinate browser click"
        }

        let target = [
            params["text"]?.stringValue,
            params["label"]?.stringValue,
            params["selector"]?.stringValue,
            elementRiskText(params["element_id"]?.stringValue),
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let riskyTerms = [
            "pay",
            "purchase",
            "buy",
            "order",
            "delete",
            "remove",
            "submit",
            "send",
            "post",
            "confirm",
            "checkout",
            "login",
            "sign in",
        ]
        return riskyTerms.contains { target.contains($0) } ? "Approve high-risk browser click" : nil
    }

    private func elementRiskText(_ elementId: String?) -> String? {
        guard let elementId, !elementId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let snapshotProvider = controller as? NapaxiBrowserSnapshotProvider else {
            return nil
        }
        let element = snapshotProvider.latestBrowserSnapshot?.elements.first {
            $0["element_id"]?.stringValue == elementId
        }
        return [
            element?["text"]?.stringValue,
            element?["label"]?.stringValue,
            element?["risk_hint"]?.stringValue,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func requestApproval(
        toolName: String,
        description: String,
        paramsJSON: String
    ) async -> Bool {
        let request = NapaxiHostToolApprovalRequest(
            requestId: UInt64(Date().timeIntervalSince1970 * 1_000_000),
            toolName: toolName,
            description: description,
            parametersJSON: paramsJSON,
            allowAlways: false
        )
        if let structuredApprovalHandler {
            return await structuredApprovalHandler.approve(request).approved
        }
        guard let approvalHandler else { return false }
        return await approvalHandler.approve(toolName: request.toolName, requestJSON: request.parametersJSON)
    }

    private func isPresent(_ value: NapaxiJSONValue?) -> Bool {
        guard let value else { return false }
        return value != .null
    }
}

final class NapaxiBrowserControllerAdapter: NapaxiBrowserController, NapaxiBrowserSnapshotProvider {
    private weak var executor: NapaxiBrowserToolExecutor?

    init(executor: NapaxiBrowserToolExecutor) {
        self.executor = executor
    }

    var latestBrowserSnapshot: NapaxiBrowserSnapshot? {
        (executor as? NapaxiBrowserSnapshotProvider)?.latestBrowserSnapshot
    }

    func executeBrowserTool(toolName: String, paramsJSON: String) async throws -> String {
        guard let executor else {
            throw NapaxiError.unavailable("Browser tool executor was released")
        }
        let request = try NapaxiBrowserToolRequest(toolName: toolName, paramsJSON: paramsJSON)
        return try await executor.executeBrowserTool(request).jsonString()
    }
}
