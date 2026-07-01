import Foundation

#if canImport(Combine)
import Combine
#endif

#if canImport(WebKit)
@preconcurrency import WebKit
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public protocol NapaxiBrowserBackend: AnyObject {
    var capabilities: NapaxiBrowserBackendCapabilities { get }
    var loading: Bool { get }
    var progress: Int { get }
    var blockedNavigation: String? { get }

    func loadURL(_ url: String) async throws
    func setUserAgent(_ userAgent: String?) async throws
    func captureScreenshot(mode: NapaxiBrowserScreenshotMode) async throws -> NapaxiBrowserScreenshot?
    func reload() async throws
    func currentURL() async throws -> String?
    func title() async throws -> String?
    func canGoBack() async throws -> Bool
    func goBack() async throws
    func runJavaScript(_ javaScript: String) async throws
    func runJavaScriptReturningResult(_ javaScript: String) async throws -> Any?
    func clearCache() async throws
    func clearLocalStorage() async throws
}

public extension NapaxiBrowserBackend {
    var capabilities: NapaxiBrowserBackendCapabilities { NapaxiBrowserBackendCapabilities() }
    var loading: Bool { false }
    var progress: Int { 0 }
    var blockedNavigation: String? { nil }

    func loadUrl(_ url: String) async throws {
        try await loadURL(url)
    }

    func setUserAgent(_ userAgent: String?) async throws {}
    func captureScreenshot(mode: NapaxiBrowserScreenshotMode) async throws -> NapaxiBrowserScreenshot? { nil }

    func currentUrl() async throws -> String? {
        try await currentURL()
    }
}

public final class NapaxiBrowserRuntimeController: @unchecked Sendable, NapaxiBrowserController, NapaxiBrowserSnapshotProvider {
    public private(set) var latestBrowserSnapshot: NapaxiBrowserSnapshot?
    public var latestSnapshot: NapaxiBrowserSnapshot? { latestBrowserSnapshot }

    public var url: String? { currentURL }
    public var title: String? { currentTitle }
    public var blockedNavigation: String? { backend.blockedNavigation ?? currentBlockedNavigation }
    public var loading: Bool { backend.loading || currentLoading }
    public var progress: Int { backend.progress > 0 ? backend.progress : currentProgress }
    public var hasPage: Bool { currentHasPage }
    public var debugHighlightEnabled: Bool { currentDebugHighlightEnabled }
    public var browserMode: NapaxiBrowserViewportMode { currentBrowserMode }
    public var userAgent: String? { Self.userAgent(for: currentBrowserMode) }
    public var pageChangeToken: String? { lastPageChangeToken }

    private let backend: NapaxiBrowserBackend
    private let queue = NapaxiBrowserSerialQueue()
    private var latestElementById: [String: [String: NapaxiJSONValue]] = [:]
    private var currentURL: String?
    private var currentTitle: String?
    private var currentBlockedNavigation: String?
    private var lastActionEffect: [String: NapaxiJSONValue]?
    private var lastPageChangeToken: String?
    private var currentBrowserMode: NapaxiBrowserViewportMode = .mobile
    private var appliedBrowserMode: NapaxiBrowserViewportMode?
    private var currentLoading = false
    private var currentProgress = 0
    private var currentHasPage = false
    private var currentDebugHighlightEnabled = false

    public init(backend: NapaxiBrowserBackend) {
        self.backend = backend
    }

    public func executeBrowserTool(toolName: String, paramsJSON: String) async throws -> String {
        try await queue.run { [self] in
            do {
                let params = try NapaxiBrowserToolRequest(toolName: toolName, paramsJSON: paramsJSON).params
                let result: [String: NapaxiJSONValue]
                switch toolName {
                case "browser_open":
                    result = try await open(params)
                case "browser_snapshot":
                    result = try await snapshotResult(action: "snapshot", params: params)
                case "browser_click":
                    result = try await click(params)
                case "browser_type":
                    result = try await type(params)
                case "browser_scroll":
                    result = try await scroll(params)
                case "browser_wait":
                    result = try await wait(params)
                case "browser_find_text":
                    result = try await findText(params)
                case "browser_keys":
                    result = try await keys(params)
                case "browser_back":
                    result = try await back()
                case "browser_close":
                    result = try await close(params)
                default:
                    result = error(action: "unknown", message: "Unknown browser tool: \(toolName)")
                }
                return try result.jsonString()
            } catch {
                return try self.error(action: toolName, message: String(describing: error)).jsonString()
            }
        }
    }

    public func reload() async throws {
        try await queue.run { [self] in
            guard currentHasPage else { return }
            try await backend.reload()
            await settle()
        }
    }

    public func goBack() async throws {
        try await queue.run { [self] in
            guard try await backend.canGoBack() else { return }
            try await backend.goBack()
            await settle()
        }
    }

    public func clearSession() async throws {
        try await queue.run { [self] in
            try await backend.clearCache()
            try await backend.clearLocalStorage()
            try await backend.loadURL("about:blank")
            resetSessionState()
        }
    }

    public func setDebugHighlightEnabled(_ enabled: Bool) async throws {
        try await queue.run { [self] in
            currentDebugHighlightEnabled = enabled
            if currentHasPage {
                _ = try? await safeJavaScript(Self.debugHighlightScript(enabled: enabled))
            }
        }
    }

    public func notifyBackendStateChanged() {}

    private func open(_ params: [String: NapaxiJSONValue]) async throws -> [String: NapaxiJSONValue] {
        let url = params["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty else {
            return error(action: "open", message: "browser_open requires url")
        }
        guard let requestedMode = parseBrowserMode(params["mode"]) else {
            return error(
                action: "open",
                message: #"browser_open mode must be "desktop" or "mobile"."#,
                failureCode: "invalid_browser_mode"
            )
        }
        if looksLikeLocalFileTarget(url) {
            return error(
                action: "open",
                message: "browser_open only supports HTTP/HTTPS URLs. Local files, workspace paths, sandbox paths, file:// URLs, generated HTML files, and files you just created are not supported. Do not retry browser_open for this target; use file reading tools or the generated attachment instead.",
                failureCode: "local_file_not_supported"
            )
        }
        guard let components = URLComponents(string: url), let scheme = components.scheme, !scheme.isEmpty else {
            return error(
                action: "open",
                message: "browser_open requires an absolute HTTP or HTTPS URL.",
                failureCode: "invalid_url"
            )
        }
        guard scheme == "http" || scheme == "https" else {
            return error(
                action: "open",
                message: "browser_open only supports http and https URLs.",
                failureCode: "unsupported_scheme"
            )
        }

        let current = try await backend.currentURL()
        let forceReload = params["force_reload"]?.boolValue == true
        let modeChanged = requestedMode != currentBrowserMode || appliedBrowserMode != requestedMode
        if modeChanged {
            latestBrowserSnapshot = nil
            latestElementById = [:]
        }
        try await applyBrowserMode(requestedMode)
        if forceReload || modeChanged || !sameURL(current, url) {
            currentLoading = true
            currentHasPage = true
            currentURL = url
            currentBlockedNavigation = nil
            try await backend.loadURL(url)
            await settle()
        }
        return try await snapshotResult(action: "open")
    }

    private func click(_ params: [String: NapaxiJSONValue]) async throws -> [String: NapaxiJSONValue] {
        guard currentHasPage else {
            return error(action: "click", message: "browser session is not open")
        }
        let before = await rawObservationMap()
        let beforeState = pageState(from: before)
        let beforeToken = pageChangeToken(from: beforeState, raw: before)
        let resolvedParams = paramsWithElementFingerprint(params)
        let raw = try await backend.runJavaScriptReturningResult(
            Self.targetedScript(params: resolvedParams, action: "click")
        )
        let result = jsonObject(fromJavaScriptResult: raw)
        guard result["success"]?.boolValue == true else {
            return mergeResult(action: "click", result: result)
        }
        await settle()
        let after = await rawObservationMap()
        let afterState = pageState(from: after)
        let afterToken = pageChangeToken(from: afterState, raw: after)
        let effect = actionEffect(
            action: "click",
            beforeToken: beforeToken,
            afterToken: afterToken,
            before: before,
            after: after,
            result: result,
            recovered: false
        )
        lastActionEffect = effect
        if !effectHasMeaningfulChange(effect) {
            if let siteSignal = effect["site_signal"]?.stringValue, !siteSignal.isEmpty {
                return mergeResult(action: "click", result: [
                    "success": .bool(false),
                    "failure_code": .string(siteSignal),
                    "error": .string("click did not change the page and the page indicates \(siteSignal)"),
                    "target": result["target"] ?? .null,
                    "hit_test": result["hit_test"] ?? .null,
                    "last_action_effect": .object(effect),
                ])
            }
            if let recovery = try await recoverClick(params: resolvedParams, beforeToken: beforeToken) {
                if recovery["success"]?.boolValue == true {
                    return try await snapshotResult(action: "click")
                }
                var recovered = recovery
                recovered["failure_code"] = recovered["failure_code"] ?? .string("no_effect_after_click")
                recovered["error"] = recovered["error"] ?? .string("click completed but did not produce a detectable page change")
                recovered["last_action_effect"] = .object(lastActionEffect ?? [:])
                return mergeResult(action: "click", result: recovered)
            }
        }
        return try await snapshotResult(action: "click")
    }

    private func type(_ params: [String: NapaxiJSONValue]) async throws -> [String: NapaxiJSONValue] {
        guard currentHasPage else {
            return error(action: "type", message: "browser session is not open")
        }
        let raw = try await backend.runJavaScriptReturningResult(
            Self.targetedScript(
                params: paramsWithElementFingerprint(params),
                action: "type",
                text: params["text"]?.stringValue ?? "",
                submit: params["submit"]?.boolValue == true,
                clearFirst: params["clear_first"]?.boolValue != false
            )
        )
        let result = jsonObject(fromJavaScriptResult: raw)
        guard result["success"]?.boolValue == true else {
            return mergeResult(action: "type", result: result)
        }
        await settle()
        return try await snapshotResult(action: "type")
    }

    private func scroll(_ params: [String: NapaxiJSONValue]) async throws -> [String: NapaxiJSONValue] {
        guard currentHasPage else {
            return error(action: "scroll", message: "browser session is not open")
        }
        let direction = params["direction"]?.stringValue?.lowercased() ?? "down"
        let amount = Int(params["amount"]?.numberValue ?? 700)
        let x: Int
        let y: Int
        switch direction {
        case "left":
            x = -amount
            y = 0
        case "right":
            x = amount
            y = 0
        case "up":
            x = 0
            y = -amount
        default:
            x = 0
            y = amount
        }
        try await backend.runJavaScript("window.scrollBy(\(x), \(y));")
        await sleep(milliseconds: 250)
        return try await snapshotResult(action: "scroll")
    }

    private func wait(_ params: [String: NapaxiJSONValue]) async throws -> [String: NapaxiJSONValue] {
        let text = params["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let milliseconds = min(max(Int(params["milliseconds"]?.numberValue ?? 1000), 0), 30_000)
        if text.isEmpty {
            await sleep(milliseconds: milliseconds)
        } else {
            await waitForText(text, timeoutMilliseconds: milliseconds)
            if params["scroll_to_text"]?.boolValue == true {
                _ = try? await safeJavaScript(Self.findTextScript(text: text))
            }
        }
        return try await snapshotResult(action: "wait")
    }

    private func findText(_ params: [String: NapaxiJSONValue]) async throws -> [String: NapaxiJSONValue] {
        guard currentHasPage else {
            return error(action: "find_text", message: "browser session is not open")
        }
        let text = params["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            return error(action: "find_text", message: "browser_find_text requires text")
        }
        let result = jsonObject(fromJavaScriptResult: try await safeJavaScript(Self.findTextScript(text: text)))
        await sleep(milliseconds: 200)
        guard result["success"]?.boolValue == true else {
            return mergeResult(action: "find_text", result: result)
        }
        return try await snapshotResult(action: "find_text")
    }

    private func keys(_ params: [String: NapaxiJSONValue]) async throws -> [String: NapaxiJSONValue] {
        guard currentHasPage else {
            return error(action: "keys", message: "browser session is not open")
        }
        let keys = params["keys"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !keys.isEmpty else {
            return error(action: "keys", message: "browser_keys requires keys")
        }
        let result = jsonObject(fromJavaScriptResult: try await safeJavaScript(Self.keysScript(keys: keys)))
        guard result["success"]?.boolValue == true else {
            return mergeResult(action: "keys", result: result)
        }
        await settle()
        return try await snapshotResult(action: "keys")
    }

    private func back() async throws -> [String: NapaxiJSONValue] {
        guard try await backend.canGoBack() else {
            return mergeResult(action: "back", result: ["success": .bool(false), "error": .string("no back history")])
        }
        try await backend.goBack()
        await settle()
        return try await snapshotResult(action: "back")
    }

    private func close(_ params: [String: NapaxiJSONValue]) async throws -> [String: NapaxiJSONValue] {
        if params["clear_storage"]?.boolValue == true {
            try await backend.clearCache()
            try await backend.clearLocalStorage()
        }
        try await backend.loadURL("about:blank")
        resetSessionState()
        return ["success": .bool(true), "action": .string("close"), "closed": .bool(true)]
    }

    private func snapshotResult(
        action: String,
        params: [String: NapaxiJSONValue] = [:]
    ) async throws -> [String: NapaxiJSONValue] {
        guard let screenshotMode = parseScreenshotMode(params["screenshot_mode"]) else {
            return error(
                action: action,
                message: #"browser_snapshot screenshot_mode must be "auto", "never", or "always"."#,
                failureCode: "invalid_screenshot_mode"
            )
        }

        currentURL = try await backend.currentURL() ?? currentURL
        currentTitle = try await backend.title() ?? currentTitle

        if currentHasPage {
            _ = try? await safeJavaScript(Self.listenerRecorderScript)
        }
        let raw = currentHasPage ? await rawSnapshotMap() : [:]
        if currentHasPage && currentDebugHighlightEnabled {
            _ = try? await safeJavaScript(Self.debugHighlightScript(enabled: true))
        }
        let pageState = pageState(from: raw)
        let viewportMap = raw.object("viewport_map") ?? pageState.object("viewport_map") ?? [:]
        let elements = pageState.objectArray("elements")
        let observedUserAgent = raw["user_agent"]?.stringValue
            ?? pageState["user_agent"]?.stringValue
            ?? Self.userAgent(for: currentBrowserMode)
        let token = pageChangeToken(from: pageState, raw: raw)
        let screenshot = await maybeCaptureScreenshot(mode: screenshotMode, action: action)
        latestElementById = Dictionary(
            uniqueKeysWithValues: elements.compactMap { element in
                guard let elementId = element["element_id"]?.stringValue else { return nil }
                return (elementId, element)
            }
        )
        lastPageChangeToken = token
        let snapshot = NapaxiBrowserSnapshot(
            url: raw["url"]?.stringValue ?? currentURL ?? "",
            title: raw["title"]?.stringValue ?? currentTitle ?? "",
            loading: currentLoading,
            browserMode: currentBrowserMode,
            userAgent: observedUserAgent,
            text: truncate(raw["text"]?.stringValue ?? "", maxCharacters: 6000),
            elements: elements,
            pageState: pageState,
            viewportMap: viewportMap,
            pageChangeToken: token,
            lastActionEffect: lastActionEffect,
            backendCapabilities: backend.capabilities,
            screenshot: screenshot
        )
        latestBrowserSnapshot = snapshot
        currentHasPage = !snapshot.url.isEmpty || currentHasPage

        guard case .object(var object) = snapshot.jsonValue() else {
            return error(action: action, message: "Failed to encode browser snapshot")
        }
        object["success"] = .bool(true)
        object["action"] = .string(action)
        if let blockedNavigation = currentBlockedNavigation {
            object["blocked_or_approval_reason"] = .string("Blocked unsupported navigation: \(blockedNavigation)")
        }
        return object
    }

    private func mergeResult(
        action: String,
        result: [String: NapaxiJSONValue]
    ) -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "success": .bool(result["success"]?.boolValue == true),
            "action": .string(action),
            "browser_mode": .string(currentBrowserMode.rawValue),
            "loading": .bool(currentLoading),
        ]
        if let failureCode = result["failure_code"] { object["failure_code"] = failureCode }
        if let error = result["error"] { object["blocked_or_approval_reason"] = error }
        for key in ["candidates", "text_candidates", "target", "hit_test", "last_action_effect", "next_step"] {
            if let value = result[key] { object[key] = value }
        }
        if let currentURL { object["url"] = .string(currentURL) }
        if let currentTitle { object["title"] = .string(currentTitle) }
        if let userAgent = Self.userAgent(for: currentBrowserMode) {
            object["user_agent"] = .string(userAgent)
        }
        return object
    }

    private func error(
        action: String,
        message: String,
        failureCode: String? = nil
    ) -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "success": .bool(false),
            "action": .string(action),
            "blocked_or_approval_reason": .string(message),
            "error": .string(message),
            "browser_mode": .string(currentBrowserMode.rawValue),
            "loading": .bool(currentLoading),
        ]
        if let failureCode { object["failure_code"] = .string(failureCode) }
        if let userAgent = Self.userAgent(for: currentBrowserMode) {
            object["user_agent"] = .string(userAgent)
        }
        if let currentURL { object["url"] = .string(currentURL) }
        if let currentTitle { object["title"] = .string(currentTitle) }
        return object
    }

    private func rawObservationMap() async -> [String: NapaxiJSONValue] {
        guard currentHasPage else { return [:] }
        _ = try? await safeJavaScript(Self.listenerRecorderScript)
        return await rawSnapshotMap()
    }

    private func rawSnapshotMap() async -> [String: NapaxiJSONValue] {
        guard let raw = try? await safeJavaScript(Self.snapshotScript(mode: currentBrowserMode)) else { return [:] }
        return jsonObject(fromJavaScriptResult: raw)
    }

    private func recoverClick(
        params: [String: NapaxiJSONValue],
        beforeToken: String
    ) async throws -> [String: NapaxiJSONValue]? {
        var recoveryParams = params
        recoveryParams["recovery"] = .bool(true)
        recoveryParams["prefer_click_point"] = .bool(true)
        let raw = try await backend.runJavaScriptReturningResult(
            Self.targetedScript(params: recoveryParams, action: "click")
        )
        var result = jsonObject(fromJavaScriptResult: raw)
        if result["success"]?.boolValue != true {
            result["next_step"] = .string("Inspect viewport_map/text_candidates, ask the user to handle login or site restrictions if indicated, or choose a different element_id.")
            return result
        }
        await settle()
        let after = await rawObservationMap()
        let afterState = pageState(from: after)
        let afterToken = pageChangeToken(from: afterState, raw: after)
        let effect = actionEffect(
            action: "click",
            beforeToken: beforeToken,
            afterToken: afterToken,
            before: [:],
            after: after,
            result: result,
            recovered: true
        )
        lastActionEffect = effect
        if effectHasMeaningfulChange(effect) {
            return result
        }
        return [
            "success": .bool(false),
            "failure_code": .string(siteRestrictionCode(afterState) ?? "no_effect_after_click"),
            "error": .string("click retry completed but did not produce a detectable page change"),
            "target": result["target"] ?? .null,
            "hit_test": result["hit_test"] ?? .null,
            "last_action_effect": .object(effect),
            "next_step": .string("Use browser_snapshot to review viewport_map and page text before trying another target."),
        ]
    }

    private func actionEffect(
        action: String,
        beforeToken: String,
        afterToken: String,
        before: [String: NapaxiJSONValue],
        after: [String: NapaxiJSONValue],
        result: [String: NapaxiJSONValue],
        recovered: Bool
    ) -> [String: NapaxiJSONValue] {
        let beforeURL = before["url"]?.stringValue
        let afterURL = after["url"]?.stringValue
        let beforeTitle = before["title"]?.stringValue
        let afterTitle = after["title"]?.stringValue
        let afterState = pageState(from: after)
        var effect: [String: NapaxiJSONValue] = [
            "action": .string(action),
            "changed": .bool(beforeToken != afterToken),
            "recovered": .bool(recovered),
            "before_token": .string(beforeToken),
            "after_token": .string(afterToken),
            "url_changed": .bool(beforeURL != nil && afterURL != nil && beforeURL != afterURL),
            "title_changed": .bool(beforeTitle != nil && afterTitle != nil && beforeTitle != afterTitle),
        ]
        if let restriction = siteRestrictionCode(afterState) { effect["site_signal"] = .string(restriction) }
        for key in ["match_method", "warning", "target", "hit_test"] {
            if let value = result[key] { effect[key] = value }
        }
        return effect
    }

    private func effectHasMeaningfulChange(_ effect: [String: NapaxiJSONValue]) -> Bool {
        effect["changed"]?.boolValue == true
            || effect["url_changed"]?.boolValue == true
            || effect["title_changed"]?.boolValue == true
    }

    private func settle() async {
        for _ in 0..<30 {
            await sleep(milliseconds: 150)
            let state = jsonObject(fromJavaScriptResult: try? await safeJavaScript("JSON.stringify({ready:document.readyState,url:location.href,title:document.title})"))
            currentURL = state["url"]?.stringValue ?? currentURL
            currentTitle = state["title"]?.stringValue ?? currentTitle
            if state["ready"]?.stringValue == "complete" { break }
        }
        if currentBrowserMode == .desktop {
            _ = try? await safeJavaScript(Self.desktopViewportScript)
        }
        _ = try? await safeJavaScript(Self.listenerRecorderScript)
        currentLoading = false
        currentProgress = 100
    }

    private func waitForText(_ text: String, timeoutMilliseconds: Int) async {
        let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000.0)
        while Date() < deadline {
            let script = "document.body && document.body.innerText.includes(\(Self.javascriptLiteral(.string(text))))"
            let found = try? await backend.runJavaScriptReturningResult(script)
            if let bool = found as? Bool, bool { return }
            if let string = found as? String, string == "true" { return }
            await sleep(milliseconds: 250)
        }
    }

    private func looksLikeLocalFileTarget(_ url: String) -> Bool {
        let lower = url.lowercased()
        if URLComponents(string: url)?.scheme?.lowercased() == "file" { return true }
        if url.hasPrefix("/") || url.hasPrefix("./") || url.hasPrefix("../") { return true }
        if lower.hasPrefix("workspace/") || lower.hasPrefix("sandbox/") || lower.hasPrefix("file:") { return true }
        if !url.contains("://") && (lower.hasSuffix(".html") || lower.hasSuffix(".htm")) { return true }
        return false
    }

    private func paramsWithElementFingerprint(_ params: [String: NapaxiJSONValue]) -> [String: NapaxiJSONValue] {
        guard let elementId = params["element_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !elementId.isEmpty,
              let element = latestElementById[elementId] else {
            return params
        }
        var output = params
        var fingerprint: [String: NapaxiJSONValue] = [:]
        fingerprint["element_id"] = .string(elementId)
        fingerprint["tag"] = element["tag"] ?? .null
        fingerprint["role"] = element["role"] ?? .null
        fingerprint["kind"] = element["kind"] ?? .null
        fingerprint["label"] = element["label"] ?? .null
        fingerprint["text"] = element["text"] ?? .null
        fingerprint["value_hint"] = element["value_hint"] ?? .null
        fingerprint["name"] = element["name"] ?? .null
        fingerprint["type"] = element["type"] ?? .null
        output["target_fingerprint"] = .object(fingerprint)
        return output
    }

    private func pageState(from raw: [String: NapaxiJSONValue]) -> [String: NapaxiJSONValue] {
        var pageState = raw.object("page_state") ?? [
            "url": raw["url"] ?? .string(currentURL ?? ""),
            "title": raw["title"] ?? .string(currentTitle ?? ""),
            "text": raw["text"] ?? .string(""),
            "elements": raw["elements"] ?? .array([]),
        ]
        pageState["url"] = pageState["url"] ?? raw["url"] ?? .string(currentURL ?? "")
        pageState["title"] = pageState["title"] ?? raw["title"] ?? .string(currentTitle ?? "")
        pageState["text"] = .string(truncate(pageState["text"]?.stringValue ?? "", maxCharacters: 6000))
        pageState["elements"] = .array(pageState.objectArray("elements").map { .object($0) })
        pageState["viewport_map"] = .object(pageState.object("viewport_map") ?? raw.object("viewport_map") ?? [:])
        pageState["page_change_token"] = pageState["page_change_token"] ?? raw["page_change_token"]
        pageState["browser_mode"] = .string(currentBrowserMode.rawValue)
        pageState["user_agent"] = pageState["user_agent"] ?? Self.userAgent(for: currentBrowserMode).map(NapaxiJSONValue.string)
        return pageState
    }

    private func parseScreenshotMode(_ value: NapaxiJSONValue?) -> NapaxiBrowserScreenshotMode? {
        guard let value else { return .auto }
        guard let string = value.stringValue else { return nil }
        return NapaxiBrowserScreenshotMode(rawValue: string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func parseBrowserMode(_ value: NapaxiJSONValue?) -> NapaxiBrowserViewportMode? {
        guard let value else { return .mobile }
        guard let string = value.stringValue else { return nil }
        return NapaxiBrowserViewportMode(rawValue: string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func applyBrowserMode(_ mode: NapaxiBrowserViewportMode) async throws {
        if appliedBrowserMode == mode {
            currentBrowserMode = mode
            return
        }
        try await backend.setUserAgent(Self.userAgent(for: mode))
        currentBrowserMode = mode
        appliedBrowserMode = mode
    }

    private func maybeCaptureScreenshot(
        mode: NapaxiBrowserScreenshotMode,
        action: String
    ) async -> NapaxiBrowserScreenshot? {
        guard currentHasPage, mode != .never, backend.capabilities.supportsScreenshot else { return nil }
        guard mode != .auto || action == "snapshot" else { return nil }
        return try? await backend.captureScreenshot(mode: mode)
    }

    private func pageChangeToken(
        from pageState: [String: NapaxiJSONValue],
        raw: [String: NapaxiJSONValue]
    ) -> String {
        if let existing = pageState["page_change_token"]?.stringValue ?? raw["page_change_token"]?.stringValue,
           !existing.isEmpty {
            return existing
        }
        let elements = pageState.objectArray("elements")
        let summary: [String: NapaxiJSONValue] = [
            "url": pageState["url"] ?? raw["url"] ?? .string(""),
            "title": pageState["title"] ?? raw["title"] ?? .string(""),
            "scroll": pageState["scroll"] ?? .null,
            "text": .string(truncate(pageState["text"]?.stringValue ?? "", maxCharacters: 1200)),
            "elements": .array(elements.prefix(40).map { element in
                .array([
                    element["element_id"] ?? .null,
                    element["text"] ?? .null,
                    element["label"] ?? .null,
                    element["action_hint"] ?? .null,
                    element["bbox"] ?? .null,
                ])
            }),
        ]
        return stableHash((try? summary.jsonString()) ?? "")
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(hash, radix: 36)
    }

    private func siteRestrictionCode(_ pageState: [String: NapaxiJSONValue]) -> String? {
        let text = (pageState["text"]?.stringValue ?? "").lowercased()
        if ["login", "sign in", "登录", "请登录", "账号"].contains(where: text.contains) {
            return "login_required"
        }
        if ["captcha", "verification", "验证码", "安全验证", "打开app", "打开 app", "客户端", "无法访问", "访问受限", "风险"].contains(where: text.contains) {
            return "site_restricted"
        }
        return nil
    }

    private func sameURL(_ left: String?, _ right: String) -> Bool {
        guard let left, !left.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard var leftComponents = URLComponents(string: left),
              var rightComponents = URLComponents(string: right) else {
            return left == right
        }
        leftComponents.fragment = nil
        rightComponents.fragment = nil
        return leftComponents == rightComponents
    }

    private func jsonObject(fromJavaScriptResult raw: Any?) -> [String: NapaxiJSONValue] {
        guard let value = Self.jsonValue(fromJavaScriptResult: raw),
              case .object(let object) = value else {
            return [:]
        }
        return object
    }

    private func truncate(_ value: String, maxCharacters: Int) -> String {
        value.count <= maxCharacters ? value : String(value.prefix(maxCharacters)) + "..."
    }

    private func safeJavaScript(_ javaScript: String) async throws -> Any? {
        try await backend.runJavaScriptReturningResult(javaScript)
    }

    private func resetSessionState() {
        latestBrowserSnapshot = nil
        latestElementById = [:]
        currentURL = nil
        currentTitle = nil
        currentBlockedNavigation = nil
        lastActionEffect = nil
        lastPageChangeToken = nil
        currentHasPage = false
        currentLoading = false
        currentProgress = 0
    }

    private func sleep(milliseconds: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    private static func userAgent(for mode: NapaxiBrowserViewportMode) -> String? {
        mode == .desktop ? NapaxiDesktopUserAgent : nil
    }

    private static func targetedScript(
        params: [String: NapaxiJSONValue],
        action: String,
        text: String = "",
        submit: Bool = false,
        clearFirst: Bool = true
    ) -> String {
        """
        (function() {
          const params = \(javascriptLiteral(.object(params)));
          const action = \(javascriptLiteral(.string(action)));
          const text = \(javascriptLiteral(.string(text)));
          const submit = \(javascriptLiteral(.bool(submit)));
          const clearFirst = \(javascriptLiteral(.bool(clearFirst)));
          \(browserRuntimeScript)
          return JSON.stringify(window.__napaxiBrowser.runTarget(params, action, {text, submit, clearFirst}));
        })()
        """
    }

    private static func findTextScript(text: String) -> String {
        """
        (function() {
          const text = \(javascriptLiteral(.string(text)));
          \(browserRuntimeScript)
          return JSON.stringify(window.__napaxiBrowser.findText(text));
        })()
        """
    }

    private static func keysScript(keys: String) -> String {
        """
        (function() {
          const keys = \(javascriptLiteral(.string(keys)));
          \(browserRuntimeScript)
          return JSON.stringify(window.__napaxiBrowser.sendKeys(keys));
        })()
        """
    }

    private static func debugHighlightScript(enabled: Bool) -> String {
        """
        (function() {
          const enabled = \(javascriptLiteral(.bool(enabled)));
          const styleId = 'napaxi-browser-debug-highlight-style';
          let style = document.getElementById(styleId);
          if (!enabled) {
            if (style) style.remove();
            document.querySelectorAll('[data-napaxi-element-id]').forEach((el) => {
              el.removeAttribute('data-napaxi-debug-highlight');
            });
            return true;
          }
          if (!style) {
            style = document.createElement('style');
            style.id = styleId;
            document.head && document.head.appendChild(style);
          }
          style.textContent = [
            '[data-napaxi-element-id]{outline:2px solid rgba(37,99,235,.75)!important;outline-offset:2px!important;}',
            '[data-napaxi-element-id][data-napaxi-debug-highlight="risk"]{outline-color:rgba(220,38,38,.8)!important;}'
          ].join('\\n');
          document.querySelectorAll('[data-napaxi-element-id]').forEach((el) => {
            const risk = (el.getAttribute('data-napaxi-risk-hint') || '').trim();
            el.setAttribute('data-napaxi-debug-highlight', risk ? 'risk' : 'normal');
          });
          return true;
        })()
        """
    }

    private static func snapshotScript(mode: NapaxiBrowserViewportMode) -> String {
        """
        (function() {
          const browserMode = \(javascriptLiteral(.string(mode.rawValue)));
          const configuredUserAgent = \(userAgent(for: mode).map { javascriptLiteral(.string($0)) } ?? "null");
          \(browserRuntimeScript)
          const result = window.__napaxiBrowser.snapshot();
          result.browser_mode = browserMode;
          result.user_agent = configuredUserAgent || navigator.userAgent;
          result.page_state = result.page_state || {};
          result.page_state.browser_mode = browserMode;
          result.page_state.user_agent = configuredUserAgent || navigator.userAgent;
          result.page_state.viewport = result.page_state.viewport || {};
          result.page_state.viewport.browser_mode = browserMode;
          if (browserMode === 'desktop') result.page_state.viewport.emulated_width = 1280;
          return JSON.stringify(result);
        })()
        """
    }

    private static let desktopViewportScript = #"""
    (function() {
      const width = '1280';
      let viewport = document.querySelector('meta[name="viewport"]');
      if (!viewport) {
        viewport = document.createElement('meta');
        viewport.setAttribute('name', 'viewport');
        document.head && document.head.appendChild(viewport);
      }
      if (viewport) {
        viewport.setAttribute('content', 'width=' + width + ', initial-scale=1.0');
      }
      return true;
    })()
    """#

    private static let listenerRecorderScript = #"""
    (function() {
      const events = new Set(['click', 'mousedown', 'mouseup', 'pointerdown', 'pointerup', 'touchstart', 'touchend']);
      const existing = window.__napaxiBrowserListenerRecorder;
      if (existing && existing.version === 1) return true;
      const listenerElements = existing && existing._elements ? existing._elements : new WeakSet();
      const originalAdd = existing && existing._originalAdd
        ? existing._originalAdd
        : EventTarget.prototype.addEventListener;
      function mark(target, type) {
        try {
          if (events.has(String(type).toLowerCase()) && target && target.nodeType === Node.ELEMENT_NODE) {
            listenerElements.add(target);
          }
        } catch (_) {}
      }
      if (!existing || existing.version !== 1) {
        EventTarget.prototype.addEventListener = function(type) {
          mark(this, type);
          return originalAdd.apply(this, arguments);
        };
      }
      window.__napaxiBrowserListenerRecorder = {
        version: 1,
        _elements: listenerElements,
        _originalAdd: originalAdd,
        has: function(el) {
          try {
            return listenerElements.has(el);
          } catch (_) {
            return false;
          }
        }
      };
      return true;
    })()
    """#

    private static let browserRuntimeScript = #"""
    (function() {
      const version = 2;
      const listenerEvents = new Set(['click', 'mousedown', 'mouseup', 'pointerdown', 'pointerup', 'touchstart', 'touchend']);
      function installListenerRecorder() {
        const existing = window.__napaxiBrowserListenerRecorder;
        if (existing && existing.version === 1) return existing;
        const listenerElements = existing && existing._elements ? existing._elements : new WeakSet();
        const originalAdd = existing && existing._originalAdd
          ? existing._originalAdd
          : EventTarget.prototype.addEventListener;
        function mark(target, type) {
          try {
            if (listenerEvents.has(String(type).toLowerCase()) && target && target.nodeType === Node.ELEMENT_NODE) {
              listenerElements.add(target);
            }
          } catch (_) {}
        }
        if (!existing || existing.version !== 1) {
          EventTarget.prototype.addEventListener = function(type) {
            mark(this, type);
            return originalAdd.apply(this, arguments);
          };
        }
        window.__napaxiBrowserListenerRecorder = {
          version: 1,
          _elements: listenerElements,
          _originalAdd: originalAdd,
          has: function(el) {
            try {
              return listenerElements.has(el);
            } catch (_) {
              return false;
            }
          }
        };
        return window.__napaxiBrowserListenerRecorder;
      }
      installListenerRecorder();
      if (window.__napaxiBrowser && window.__napaxiBrowser.version === version) return;
      const dataAttr = 'data-napaxi-element-id';
      const roleSet = new Set(['button','link','textbox','searchbox','combobox','checkbox','radio','switch','menuitem','option','tab','slider','spinbutton','row','cell','gridcell']);
      const actionTerms = ['add to cart','cart','basket','buy','purchase','checkout','submit','confirm','order','action','button','加入购物车','加入购物袋','加购','购物车','立即购买','马上购买','购买','下单','提交','确认','去结算','结算'];
      const actionAttrTerms = [...actionTerms,'add','addcart','add-cart','buybtn','buy-button','cart-button','submit-btn','confirm-btn','data-click','data-action'];
      const riskyTerms = ['pay','purchase','buy','order','delete','remove','submit','send','post','confirm','checkout','login','sign in','立即购买','付款','支付','提交订单','删除','确认'];
      const sensitiveTerms = ['password','passwd','passcode','otp','captcha','verification','verify code','security code','密码','验证码','动态码'];
      function compact(value) { return (value || '').toString().replace(/\s+/g, ' ').trim(); }
      function norm(value) { return compact(value).toLowerCase(); }
      function hasAny(haystack, terms) {
        const normalized = norm(haystack);
        return terms.find((term) => normalized.includes(norm(term))) || '';
      }
      function hash(value) {
        let h = 2166136261;
        for (let i = 0; i < value.length; i++) {
          h ^= value.charCodeAt(i);
          h = Math.imul(h, 16777619);
        }
        return (h >>> 0).toString(36);
      }
      function visible(el) {
        if (!el || el.nodeType !== Node.ELEMENT_NODE) return false;
        const style = window.getComputedStyle(el);
        const rect = el.getBoundingClientRect();
        return !!style && style.visibility !== 'hidden' && style.display !== 'none' &&
          Number(style.opacity || '1') > 0.01 && rect.width > 0 && rect.height > 0 &&
          rect.bottom >= 0 && rect.right >= 0 && rect.top <= window.innerHeight && rect.left <= window.innerWidth;
      }
      function allRoots() {
        const roots = [document];
        const seen = new Set(roots);
        function scan(root) {
          let nodes = [];
          try { nodes = Array.from(root.querySelectorAll('*')); } catch (_) { return; }
          for (const node of nodes) {
            if (node.shadowRoot && !seen.has(node.shadowRoot)) {
              seen.add(node.shadowRoot);
              roots.push(node.shadowRoot);
              scan(node.shadowRoot);
            }
            if (node.tagName === 'IFRAME') {
              try {
                const doc = node.contentDocument;
                if (doc && !seen.has(doc)) {
                  seen.add(doc);
                  roots.push(doc);
                  scan(doc);
                }
              } catch (_) {}
            }
          }
        }
        scan(document);
        return roots;
      }
      function allElements() {
        const out = [];
        const seen = new Set();
        for (const root of allRoots()) {
          let nodes = [];
          try { nodes = Array.from(root.querySelectorAll('*')); } catch (_) {}
          for (const node of nodes) {
            if (!seen.has(node)) {
              seen.add(node);
              out.push(node);
            }
          }
        }
        return out;
      }
      function queryFirst(selector) {
        for (const root of allRoots()) {
          try {
            const found = root.querySelector(selector);
            if (found) return found;
          } catch (_) {}
        }
        return null;
      }
      function explicitLabel(el) {
        const parts = [el.getAttribute('aria-label'), el.getAttribute('placeholder'), el.getAttribute('title'), el.getAttribute('alt'), el.getAttribute('name')];
        if (el.id) {
          try {
            const labels = Array.from(document.querySelectorAll('label[for="' + CSS.escape(el.id) + '"]'));
            parts.push(...labels.map((label) => label.innerText));
          } catch (_) {}
        }
        if (el.labels) {
          try { parts.push(...Array.from(el.labels).map((label) => label.innerText)); } catch (_) {}
        }
        return compact(parts.filter(Boolean).join(' '));
      }
      function textOf(el) {
        const aria = explicitLabel(el);
        const own = compact(el.innerText || el.textContent || '');
        const value = 'value' in el ? compact(el.value) : '';
        return compact([aria, own || value].filter(Boolean).join(' '));
      }
      function attributeText(el) {
        const parts = [el.id, el.className && typeof el.className === 'string' ? el.className : '', el.getAttribute('role'), el.getAttribute('aria-label'), el.getAttribute('title'), el.getAttribute('name'), el.getAttribute('type'), el.getAttribute('data-action'), el.getAttribute('data-click'), el.getAttribute('data-testid'), el.getAttribute('data-test'), el.getAttribute('href')];
        try {
          for (const attr of Array.from(el.attributes || [])) {
            if (attr.name.startsWith('data-')) parts.push(attr.name, attr.value);
          }
        } catch (_) {}
        return compact(parts.filter(Boolean).join(' '));
      }
      function roleOf(el) {
        const role = compact(el.getAttribute('role')).toLowerCase();
        if (role) return role;
        const tag = el.tagName.toLowerCase();
        const type = (el.getAttribute('type') || '').toLowerCase();
        if (tag === 'a') return 'link';
        if (tag === 'button' || type === 'button' || type === 'submit') return 'button';
        if (tag === 'textarea') return 'textbox';
        if (tag === 'select') return 'combobox';
        if (tag === 'input') {
          if (type === 'checkbox') return 'checkbox';
          if (type === 'radio') return 'radio';
          if (type === 'search') return 'searchbox';
          return 'textbox';
        }
        if (el.isContentEditable) return 'textbox';
        return tag;
      }
      function kindOf(el) {
        const role = roleOf(el);
        const type = (el.getAttribute('type') || '').toLowerCase();
        if (type === 'password') return 'password';
        if (role === 'textbox' || role === 'searchbox') return 'text';
        if (role === 'button') return 'button';
        if (role === 'link') return 'link';
        return role;
      }
      function cssPath(el) {
        const parts = [];
        let cur = el;
        while (cur && cur.nodeType === Node.ELEMENT_NODE && cur !== document.documentElement) {
          let part = cur.tagName.toLowerCase();
          if (cur.id) {
            part += '#' + cur.id;
            parts.unshift(part);
            break;
          }
          let index = 1;
          let sib = cur;
          while ((sib = sib.previousElementSibling)) {
            if (sib.tagName === cur.tagName) index += 1;
          }
          part += ':nth-of-type(' + index + ')';
          parts.unshift(part);
          cur = cur.parentElement;
        }
        return parts.join('>');
      }
      function isSensitive(el, labelText) {
        const haystack = norm([el.getAttribute('type'), el.getAttribute('name'), el.getAttribute('autocomplete'), labelText].filter(Boolean).join(' '));
        return sensitiveTerms.some((term) => haystack.includes(term));
      }
      function riskHint(labelText) {
        const haystack = norm(labelText);
        return riskyTerms.find((term) => haystack.includes(term)) || '';
      }
      function listenerRecorderHas(el) {
        try {
          const recorder = window.__napaxiBrowserListenerRecorder;
          return !!(recorder && typeof recorder.has === 'function' && recorder.has(el));
        } catch (_) {
          return false;
        }
      }
      function actionHintFor(el, combinedText, attrText) {
        const haystack = compact([combinedText, attrText].join(' '));
        const term = hasAny(haystack, actionTerms);
        if (term) return term;
        const role = roleOf(el);
        if (role === 'button') return 'button';
        if (role === 'link') return 'link';
        if (role === 'searchbox') return 'search';
        return '';
      }
      function clickabilityInfo(el) {
        if (!visible(el)) return {interactive: false, score: 0, source: '', reason: '', action_hint: ''};
        const tag = el.tagName.toLowerCase();
        const role = roleOf(el);
        const style = window.getComputedStyle(el);
        const combinedText = textOf(el);
        const attrText = attributeText(el);
        const ownAndNearbyText = compact([combinedText, el.parentElement ? el.parentElement.innerText : ''].join(' '));
        const actionHint = actionHintFor(el, ownAndNearbyText, attrText);
        const reasons = [];
        let score = 0;
        let source = '';
        if (['a','button','input','textarea','select','summary','details','option'].includes(tag)) {
          score += 100; source = source || 'native'; reasons.push('native_control');
        }
        if (el.isContentEditable) {
          score += 80; source = source || 'editable'; reasons.push('contenteditable');
        }
        if (roleSet.has(role)) {
          score += 75; source = source || 'aria_role'; reasons.push('aria_role:' + role);
        }
        if (['onclick','onmousedown','onmouseup','onpointerdown','onpointerup','ontouchstart','ontouchend','onkeydown','onkeyup'].some((attr) => el.hasAttribute(attr))) {
          score += 75; source = source || 'event_attribute'; reasons.push('event_attribute');
        }
        if (listenerRecorderHas(el)) {
          score += 85; source = source || 'js_listener'; reasons.push('js_listener');
        }
        const tabindex = el.getAttribute('tabindex');
        if (tabindex !== null && tabindex !== '-1') {
          score += 45; source = source || 'tabindex'; reasons.push('tabindex');
        }
        if (style && style.cursor === 'pointer') {
          score += 55; source = source || 'cursor'; reasons.push('cursor:pointer');
        }
        if (hasAny(attrText, actionAttrTerms)) {
          score += 40; source = source || 'action_attribute'; reasons.push('action_attribute');
        }
        if (actionHint && ['div','span','label','li','section','p'].includes(tag)) {
          score += 35; source = source || 'action_text'; reasons.push('action_text:' + actionHint);
        }
        return {interactive: score >= 35, score, source, reason: reasons.join(','), action_hint: actionHint};
      }
      function isInteractive(el) { return clickabilityInfo(el).interactive; }
      function elementRecord(el, index) {
        const rect = el.getBoundingClientRect();
        const labelText = explicitLabel(el);
        const combinedText = textOf(el);
        const sensitive = isSensitive(el, combinedText);
        const kind = kindOf(el);
        const info = clickabilityInfo(el);
        const fingerprint = {
          tag: el.tagName.toLowerCase(),
          role: roleOf(el),
          kind,
          type: (el.getAttribute('type') || '').toLowerCase(),
          name: el.getAttribute('name') || '',
          label: labelText.slice(0, 180),
          text: sensitive ? '[redacted sensitive field]' : combinedText.slice(0, 220),
          path: cssPath(el)
        };
        const elementId = 'e_' + hash(JSON.stringify(fingerprint));
        try { el.setAttribute(dataAttr, elementId); } catch (_) {}
        const parentText = compact(el.parentElement ? el.parentElement.innerText : '');
        const risk = riskHint(combinedText);
        try {
          if (risk) el.setAttribute('data-napaxi-risk-hint', risk);
          else el.removeAttribute('data-napaxi-risk-hint');
        } catch (_) {}
        return {
          index, element_id: elementId, role: fingerprint.role, kind, tag: fingerprint.tag,
          type: fingerprint.type, name: fingerprint.name, label: fingerprint.label, text: fingerprint.text,
          value_hint: sensitive ? '[redacted sensitive field]' : (('value' in el) ? compact(el.value).slice(0, 120) : ''),
          enabled: !(el.disabled || el.getAttribute('aria-disabled') === 'true'),
          visible: visible(el),
          bbox: {x: Math.round(rect.left), y: Math.round(rect.top), width: Math.round(rect.width), height: Math.round(rect.height)},
          clickable_point: {x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2)},
          nearby_text: sensitive ? '' : parentText.slice(0, 260),
          risk_hint: risk,
          action_hint: info.action_hint,
          interaction_source: info.source,
          clickable_score: info.score,
          clickable_reason: info.reason,
          fingerprint
        };
      }
      function interactiveElements() {
        return allElements().filter(isInteractive).sort((a, b) => clickabilityInfo(b).score - clickabilityInfo(a).score).slice(0, 160);
      }
      function viewportObservation(elements) {
        const textBlocks = visibleTextBlocks();
        const overlays = overlayCandidates();
        return {
          width: window.innerWidth,
          height: window.innerHeight,
          scroll_x: Math.round(window.scrollX || 0),
          scroll_y: Math.round(window.scrollY || 0),
          visible_text_blocks: textBlocks,
          visible_clickable_elements: elements.slice(0, 80).map((item) => ({
            element_id: item.element_id,
            role: item.role,
            kind: item.kind,
            tag: item.tag,
            text: item.text,
            label: item.label,
            action_hint: item.action_hint,
            interaction_source: item.interaction_source,
            clickable_score: item.clickable_score,
            clickable_reason: item.clickable_reason,
            bbox: item.bbox,
            center: item.clickable_point,
            nearby_text: item.nearby_text,
            risk_hint: item.risk_hint
          })),
          overlays,
          diagnostics: pageDiagnostics(textBlocks, overlays)
        };
      }
      function visibleTextBlocks() {
        const out = [];
        const seen = new Set();
        const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
        let node = walker.nextNode();
        while (node && out.length < 120) {
          const text = compact(node.nodeValue);
          const parent = node.parentElement;
          if (text && parent && visible(parent) && !seen.has(text + cssPath(parent))) {
            const rect = parent.getBoundingClientRect();
            seen.add(text + cssPath(parent));
            out.push({
              text: text.slice(0, 180),
              bbox: {x: Math.round(rect.left), y: Math.round(rect.top), width: Math.round(rect.width), height: Math.round(rect.height)},
              center: {x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2)},
              near_action: actionHintFor(parent, text, attributeText(parent))
            });
          }
          node = walker.nextNode();
        }
        return out;
      }
      function overlayCandidates() {
        return allElements().filter((el) => {
          if (!visible(el)) return false;
          const style = window.getComputedStyle(el);
          const rect = el.getBoundingClientRect();
          const z = Number.parseInt(style.zIndex || '0', 10) || 0;
          const fixed = style.position === 'fixed' || style.position === 'sticky';
          const large = rect.width >= window.innerWidth * 0.45 && rect.height >= window.innerHeight * 0.12;
          return (fixed || z >= 10) && large;
        }).slice(0, 12).map((el) => {
          const rect = el.getBoundingClientRect();
          return {
            tag: el.tagName.toLowerCase(),
            role: roleOf(el),
            text: textOf(el).slice(0, 220),
            z_index: window.getComputedStyle(el).zIndex || '',
            position: window.getComputedStyle(el).position || '',
            bbox: {x: Math.round(rect.left), y: Math.round(rect.top), width: Math.round(rect.width), height: Math.round(rect.height)}
          };
        });
      }
      function pageDiagnostics(textBlocks, overlays) {
        const text = norm(textBlocks.map((item) => item.text).join(' '));
        const diagnostics = [];
        if (['登录','请登录','login','sign in'].some((term) => text.includes(norm(term)))) diagnostics.push('login_required');
        if (['验证码','安全验证','captcha','verification','打开app','客户端','访问受限','风险'].some((term) => text.includes(norm(term)))) diagnostics.push('site_restricted');
        if (overlays.length) diagnostics.push('overlay_or_fixed_layer_present');
        return diagnostics;
      }
      function snapshot() {
        const elements = interactiveElements().map(elementRecord);
        const pageText = compact(document.body ? document.body.innerText : '').slice(0, 10000);
        const viewportMap = viewportObservation(elements);
        const pageChangeToken = hash(JSON.stringify({
          url: location.href,
          title: document.title || '',
          scrollY: Math.round(window.scrollY || 0),
          text: pageText.slice(0, 1800),
          elements: elements.slice(0, 80).map((item) => [item.element_id, item.text, item.label, item.action_hint, item.bbox])
        }));
        const pageState = {
          url: location.href,
          title: document.title || '',
          viewport: {width: window.innerWidth, height: window.innerHeight, device_pixel_ratio: window.devicePixelRatio || 1},
          scroll: {x: Math.round(window.scrollX || 0), y: Math.round(window.scrollY || 0), max_y: Math.max(document.body ? document.body.scrollHeight : 0, document.documentElement ? document.documentElement.scrollHeight : 0)},
          text: pageText,
          elements,
          viewport_map: viewportMap,
          page_change_token: pageChangeToken
        };
        return {url: pageState.url, title: pageState.title, text: pageText, elements, viewport_map: viewportMap, page_change_token: pageChangeToken, page_state: pageState};
      }
      function scoreElement(el, target) {
        const fp = target || {};
        const labelText = explicitLabel(el);
        const combinedText = textOf(el);
        let score = 0;
        if (fp.tag && fp.tag === el.tagName.toLowerCase()) score += 8;
        if (fp.role && fp.role === roleOf(el)) score += 12;
        if (fp.kind && fp.kind === kindOf(el)) score += 8;
        if (fp.name && fp.name === (el.getAttribute('name') || '')) score += 8;
        if (fp.type && fp.type === (el.getAttribute('type') || '').toLowerCase()) score += 6;
        if (fp.label && norm(labelText).includes(norm(fp.label))) score += 24;
        if (fp.text && fp.text.indexOf('[redacted') !== 0 && norm(combinedText).includes(norm(fp.text))) score += 22;
        return score;
      }
      function candidatesFor(params) {
        const target = params.target_fingerprint || {};
        return interactiveElements().map((el, index) => ({el, index, score: scoreElement(el, target)}))
          .filter((item) => item.score > 0)
          .sort((a, b) => b.score - a.score)
          .slice(0, 5)
          .map((item, index) => {
            const record = elementRecord(item.el, item.index);
            record.match_score = item.score;
            record.candidate_rank = index;
            return record;
          });
      }
      function textActionCandidates(text) {
        const wanted = norm(text);
        if (!wanted) return [];
        const out = [];
        const seen = new Set();
        const root = document.body || document.documentElement;
        if (!root) return out;
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        let node = walker.nextNode();
        while (node) {
          if (norm(node.nodeValue).includes(wanted)) {
            const parent = node.parentElement;
            const el = parent ? findActionAncestor(parent, wanted) : null;
            if (el && !seen.has(el)) {
              seen.add(el);
              const record = elementRecord(el, -1);
              record.match_method = 'text_ancestor';
              record.match_text = compact(node.nodeValue).slice(0, 180);
              out.push(record);
              if (out.length >= 6) break;
            }
          }
          node = walker.nextNode();
        }
        return out;
      }
      function findActionAncestor(start, wantedNorm) {
        let cur = start;
        let depth = 0;
        let fallback = null;
        while (cur && cur.nodeType === Node.ELEMENT_NODE && depth < 7) {
          if (visible(cur)) {
            const info = clickabilityInfo(cur);
            const haystack = norm([textOf(cur), attributeText(cur)].join(' '));
            const textMatches = !wantedNorm || haystack.includes(wantedNorm);
            if (info.interactive && textMatches) return cur;
            if (!fallback && textMatches && info.action_hint) fallback = cur;
          }
          cur = cur.parentElement;
          depth += 1;
        }
        return fallback;
      }
      function findTarget(params) {
        let el = null;
        if (params.click_point) {
          const point = params.click_point;
          const x = Number(point.x);
          const y = Number(point.y);
          if (Number.isFinite(x) && Number.isFinite(y)) {
            try { el = document.elementFromPoint(x, y); } catch (_) {}
            if (el && visible(el)) return {el, method: 'click_point', point: {x, y}};
          }
        }
        if (params.element_id) {
          try { el = queryFirst('[' + dataAttr + '="' + CSS.escape(params.element_id) + '"]'); } catch (_) {}
          if (el && visible(el)) return {el, method: 'element_id'};
        }
        if (params.selector) {
          try { el = queryFirst(params.selector); } catch (_) {}
          if (el && visible(el)) return {el, method: 'selector'};
        }
        const candidates = interactiveElements();
        if (Number.isInteger(params.index) && candidates[params.index]) {
          return {el: candidates[params.index], method: 'index'};
        }
        if (params.text) {
          const wanted = norm(params.text);
          el = candidates.find((item) => norm(item.innerText || item.textContent || item.value).includes(wanted));
          if (el) return {el, method: 'text'};
          const textAncestor = textActionCandidates(params.text)[0];
          if (textAncestor && textAncestor.element_id) {
            try { el = queryFirst('[' + dataAttr + '="' + CSS.escape(textAncestor.element_id) + '"]'); } catch (_) {}
            if (el && visible(el)) return {el, method: 'text_ancestor'};
          }
        }
        if (params.label) {
          const wanted = norm(params.label);
          el = candidates.find((item) => norm(explicitLabel(item)).includes(wanted));
          if (el) return {el, method: 'label'};
          const labelAncestor = textActionCandidates(params.label)[0];
          if (labelAncestor && labelAncestor.element_id) {
            try { el = queryFirst('[' + dataAttr + '="' + CSS.escape(labelAncestor.element_id) + '"]'); } catch (_) {}
            if (el && visible(el)) return {el, method: 'label_text_ancestor'};
          }
        }
        if (params.target_fingerprint) {
          const ranked = candidates.map((item) => ({el: item, score: scoreElement(item, params.target_fingerprint)})).sort((a, b) => b.score - a.score);
          if (ranked.length && ranked[0].score >= 18) return {el: ranked[0].el, method: 'fingerprint', score: ranked[0].score};
        }
        return {el: null, method: 'none'};
      }
      function hitTest(el) {
        const rect = el.getBoundingClientRect();
        const x = Math.min(Math.max(rect.left + rect.width / 2, 1), window.innerWidth - 1);
        const y = Math.min(Math.max(rect.top + rect.height / 2, 1), window.innerHeight - 1);
        return hitTestPoint(x, y, el);
      }
      function hitTestPoint(x, y, el) {
        let hit = null;
        try { hit = document.elementFromPoint(x, y); } catch (_) {}
        return {
          x, y, hit,
          hit_tag: hit && hit.tagName ? hit.tagName.toLowerCase() : '',
          hit_text: hit ? textOf(hit).slice(0, 160) : '',
          unobscured: !el || !hit || hit === el || el.contains(hit) || hit.contains(el)
        };
      }
      function publicHitTest(hit) {
        return {x: Math.round(hit.x), y: Math.round(hit.y), hit_tag: hit.hit_tag, hit_text: hit.hit_text, unobscured: hit.unobscured};
      }
      function dispatchPointerClick(el, point) {
        const hit = point ? hitTestPoint(point.x, point.y, el) : hitTest(el);
        const eventTarget = point && hit.hit ? hit.hit : el;
        const init = {bubbles: true, cancelable: true, view: window, clientX: hit.x, clientY: hit.y, button: 0, buttons: 1};
        for (const type of ['pointerover','pointerenter','mouseover','mouseenter','pointerdown','mousedown','pointerup','mouseup','click']) {
          let event;
          try {
            event = type.startsWith('pointer') ? new PointerEvent(type, Object.assign({pointerId: 1, pointerType: 'mouse', isPrimary: true}, init)) : new MouseEvent(type, init);
          } catch (_) {
            event = new MouseEvent(type.replace(/^pointer/, 'mouse'), init);
          }
          eventTarget.dispatchEvent(event);
        }
        return hit;
      }
      function clickElement(el, point) {
        if (!el) return {success: false, failure_code: 'target_not_found', error: 'target element not found'};
        if (el.disabled || el.getAttribute('aria-disabled') === 'true') return {success: false, failure_code: 'disabled', error: 'target element is disabled'};
        if (!point) el.scrollIntoView({block: 'center', inline: 'center'});
        const hit = dispatchPointerClick(el, point);
        const publicHit = publicHitTest(hit);
        const target = elementRecord(el, -1);
        if (!hit.unobscured) {
          try {
            el.click();
            return {success: true, warning: 'target was visually obscured; used programmatic click fallback', target, hit_test: publicHit};
          } catch (_) {
            return {success: false, failure_code: 'obscured', error: 'target element is obscured by another element', target, hit_test: publicHit};
          }
        }
        return {success: true, target, hit_test: publicHit};
      }
      function typeElement(el, options) {
        if (!el) return {success: false, failure_code: 'target_not_found', error: 'target element not found'};
        el.scrollIntoView({block: 'center', inline: 'center'});
        el.focus();
        const text = options.text || '';
        const clearFirst = options.clearFirst !== false;
        if ('value' in el) {
          if (clearFirst) el.value = '';
          el.value = (clearFirst ? '' : el.value) + text;
          el.dispatchEvent(new InputEvent('input', {bubbles: true, data: text, inputType: 'insertText'}));
          el.dispatchEvent(new Event('change', {bubbles: true}));
        } else if (el.isContentEditable) {
          if (clearFirst) el.textContent = '';
          document.execCommand('insertText', false, text);
          el.dispatchEvent(new InputEvent('input', {bubbles: true, data: text, inputType: 'insertText'}));
        } else {
          return {success: false, failure_code: 'not_editable', error: 'target element is not editable'};
        }
        if (options.submit) sendKeys('Enter');
        return {success: true};
      }
      function runTarget(params, action, options) {
        const found = findTarget(params || {});
        if (!found.el) {
          const textCandidates = textActionCandidates((params && (params.text || params.label)) || '');
          return {
            success: false,
            failure_code: textCandidates.length ? 'interactive_text_not_indexed' : 'target_not_found',
            error: 'target element not found',
            candidates: candidatesFor(params || {}),
            text_candidates: textCandidates
          };
        }
        if (action === 'click') {
          let point = found.point || null;
          if (!point && params && params.prefer_click_point) {
            const rect = found.el.getBoundingClientRect();
            point = {x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2)};
          }
          const result = clickElement(found.el, point);
          result.match_method = found.method;
          return result;
        }
        if (action === 'type') {
          const result = typeElement(found.el, options || {});
          result.match_method = found.method;
          return result;
        }
        return {success: false, failure_code: 'unsupported_action', error: 'unsupported browser action'};
      }
      function findText(text) {
        const wanted = norm(text);
        if (!wanted) return {success: false, failure_code: 'empty_text', error: 'text is required'};
        const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
        let node = walker.nextNode();
        while (node) {
          if (norm(node.nodeValue).includes(wanted)) {
            const parent = node.parentElement;
            if (parent) parent.scrollIntoView({block: 'center', inline: 'nearest'});
            return {success: true, text: compact(node.nodeValue).slice(0, 240)};
          }
          node = walker.nextNode();
        }
        return {success: false, failure_code: 'text_not_found', error: 'text not found'};
      }
      function sendKeys(keys) {
        const allowed = new Set(['Enter','Escape','Tab','ArrowUp','ArrowDown','ArrowLeft','ArrowRight']);
        const parts = compact(keys).split('+').map((part) => part.trim()).filter(Boolean);
        if (!parts.length) return {success: false, failure_code: 'empty_keys', error: 'keys is required'};
        const target = document.activeElement || document.body;
        for (const key of parts) {
          if (!allowed.has(key)) return {success: false, failure_code: 'unsupported_key', error: 'unsupported key: ' + key};
          target.dispatchEvent(new KeyboardEvent('keydown', {bubbles: true, cancelable: true, key}));
          target.dispatchEvent(new KeyboardEvent('keyup', {bubbles: true, cancelable: true, key}));
          if (key === 'Enter') {
            const form = target.form || (target.closest ? target.closest('form') : null);
            if (form && typeof form.requestSubmit === 'function') form.requestSubmit();
          }
        }
        return {success: true, keys: parts};
      }
      window.__napaxiBrowser = {version, snapshot, runTarget, findText, sendKeys};
    })()
    """#

    private static func javascriptLiteral(_ value: NapaxiJSONValue) -> String {
        (try? NapaxiRawJSON(value).jsonString()) ?? "null"
    }

    private static func jsonValue(fromJavaScriptResult raw: Any?) -> NapaxiJSONValue? {
        guard let raw else { return nil }
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let parsed = try? NapaxiRawJSON(jsonString: trimmed).value {
                if case .string(let nested) = parsed,
                   let nestedValue = try? NapaxiRawJSON(jsonString: nested).value {
                    return nestedValue
                }
                return parsed
            }
            return .string(value)
        }
        if let value = raw as? Bool { return .bool(value) }
        if let value = raw as? NSNumber { return .number(value.doubleValue) }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let value = try? NapaxiRawJSON(data: data).value else {
            return nil
        }
        return value
    }
}

private actor NapaxiBrowserSerialQueue {
    private var previous = Task<Void, Never> {}

    func run<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let dependency = previous
        let task = Task<T, Error> {
            await dependency.value
            return try await operation()
        }
        previous = Task { _ = try? await task.value }
        return try await task.value
    }
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func object(_ key: String) -> [String: NapaxiJSONValue]? {
        guard case .object(let object)? = self[key] else { return nil }
        return object
    }

    func objectArray(_ key: String) -> [[String: NapaxiJSONValue]] {
        guard case .array(let values)? = self[key] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value else { return nil }
            return object
        }
    }
}

#if canImport(WebKit)
public final class NapaxiWebKitBrowserController: NapaxiBrowserController, NapaxiBrowserSnapshotProvider {
    public let backend: NapaxiWebKitBrowserBackend
    private let runtime: NapaxiBrowserRuntimeController

    public var webView: WKWebView { backend.webView }
    public var url: String? { runtime.url }
    public var title: String? { runtime.title }
    public var blockedNavigation: String? { runtime.blockedNavigation }
    public var loading: Bool { runtime.loading }
    public var progress: Int { runtime.progress }
    public var hasPage: Bool { runtime.hasPage }
    public var debugHighlightEnabled: Bool { runtime.debugHighlightEnabled }
    public var browserMode: NapaxiBrowserViewportMode { runtime.browserMode }
    public var userAgent: String? { runtime.userAgent }
    public var pageChangeToken: String? { runtime.pageChangeToken }
    public var latestBrowserSnapshot: NapaxiBrowserSnapshot? { runtime.latestBrowserSnapshot }
    public var latestSnapshot: NapaxiBrowserSnapshot? { runtime.latestSnapshot }

    public init(webView: WKWebView? = nil, screenshotDirectory: URL? = nil) {
        let backend = NapaxiWebKitBrowserBackend(webView: webView, screenshotDirectory: screenshotDirectory)
        self.backend = backend
        self.runtime = NapaxiBrowserRuntimeController(backend: backend)
    }

    public func executeBrowserTool(toolName: String, paramsJSON: String) async throws -> String {
        try await runtime.executeBrowserTool(toolName: toolName, paramsJSON: paramsJSON)
    }

    public func reload() async throws { try await runtime.reload() }
    public func goBack() async throws { try await runtime.goBack() }
    public func clearSession() async throws { try await runtime.clearSession() }
    public func setDebugHighlightEnabled(_ enabled: Bool) async throws {
        try await runtime.setDebugHighlightEnabled(enabled)
    }

    public func notifyBackendStateChanged() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
        runtime.notifyBackendStateChanged()
    }

    public func buildWebView() -> WKWebView {
        webView
    }
}


#if canImport(Combine)
extension NapaxiWebKitBrowserController: ObservableObject {}
#endif

public final class NapaxiWebKitBrowserBackend: NSObject, NapaxiBrowserBackend, WKNavigationDelegate {
    public let webView: WKWebView
    public let screenshotDirectory: URL

    public var capabilities: NapaxiBrowserBackendCapabilities {
        NapaxiBrowserBackendCapabilities(
            supportsScreenshot: true,
            supportsCoordinateClick: true,
            supportsEarlyScriptInjection: true,
            supportsCdpSelectorMap: false
        )
    }

    public var loading: Bool { webView.isLoading }
    public var progress: Int { Int(webView.estimatedProgress * 100.0) }
    public private(set) var blockedNavigation: String?

    public init(webView: WKWebView? = nil, screenshotDirectory: URL? = nil) {
        self.screenshotDirectory = screenshotDirectory
            ?? URL(fileURLWithPath: NapaxiPlatformContextResolver.defaultFilesDir)
                .appendingPathComponent("screenshots/browser", isDirectory: true)
        if let webView {
            self.webView = webView
        } else {
            let configuration = WKWebViewConfiguration()
            if #available(iOS 14.0, macOS 11.0, *) {
                configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            } else {
                configuration.preferences.javaScriptEnabled = true
            }
            self.webView = WKWebView(frame: .zero, configuration: configuration)
        }
        super.init()
        self.webView.navigationDelegate = self
    }

    public func loadURL(_ url: String) async throws {
        try await MainActor.run {
            if url == "about:blank" {
                webView.loadHTMLString("", baseURL: nil)
                return
            }
            guard let parsed = URL(string: url) else {
                throw NapaxiError.invalidState("Invalid browser URL: \(url)")
            }
            blockedNavigation = nil
            webView.load(URLRequest(url: parsed))
        }
    }

    public func buildWidget() -> WKWebView {
        webView
    }

    public func setUserAgent(_ userAgent: String?) async throws {
        await MainActor.run {
            webView.customUserAgent = userAgent
        }
    }

    public func captureScreenshot(mode: NapaxiBrowserScreenshotMode) async throws -> NapaxiBrowserScreenshot? {
        let snapshot = try await webViewSnapshot()
        guard let data = snapshot.pngData else { return nil }
        try FileManager.default.createDirectory(
            at: screenshotDirectory,
            withIntermediateDirectories: true
        )
        let filename = "browser-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).png"
        let fileURL = screenshotDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: [.atomic])
        let root = URL(fileURLWithPath: NapaxiPlatformContextResolver.defaultFilesDir)
        let sandboxPath: String
        if fileURL.path.hasPrefix(root.path + "/") {
            sandboxPath = String(fileURL.path.dropFirst(root.path.count + 1))
        } else {
            sandboxPath = fileURL.lastPathComponent
        }
        return NapaxiBrowserScreenshot(
            sandboxPath: sandboxPath,
            width: snapshot.width,
            height: snapshot.height,
            mimeType: "image/png"
        )
    }

    public func reload() async throws {
        await MainActor.run { _ = webView.reload() }
    }

    public func currentURL() async throws -> String? {
        await MainActor.run { webView.url?.absoluteString }
    }

    public func title() async throws -> String? {
        await MainActor.run { webView.title }
    }

    public func canGoBack() async throws -> Bool {
        await MainActor.run { webView.canGoBack }
    }

    public func goBack() async throws {
        await MainActor.run { _ = webView.goBack() }
    }

    public func runJavaScript(_ javaScript: String) async throws {
        _ = try await runJavaScriptReturningResult(javaScript)
    }

    public func runJavaScriptReturningResult(_ javaScript: String) async throws -> Any? {
        try await evaluateJavaScriptOnMain(javaScript)
    }

    public func clearCache() async throws {
        await MainActor.run {
            URLCache.shared.removeAllCachedResponses()
        }
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
                continuation.resume()
            }
        }
    }

    public func clearLocalStorage() async throws {
        _ = try? await runJavaScriptReturningResult("try { localStorage.clear(); sessionStorage.clear(); true; } catch (_) { false; }")
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let scheme = navigationAction.request.url?.scheme?.lowercased(),
           scheme != "http",
           scheme != "https",
           scheme != "about" {
            blockedNavigation = navigationAction.request.url?.absoluteString
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    @MainActor
    private func evaluateJavaScriptOnMain(_ javaScript: String) async throws -> Any? {
        try await webView.evaluateJavaScript(javaScript)
    }

    private func webViewSnapshot() async throws -> NapaxiWebKitSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let configuration = WKSnapshotConfiguration()
                configuration.rect = webView.bounds
                webView.takeSnapshot(with: configuration) { image, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let image,
                          let snapshot = NapaxiWebKitSnapshot(image: image) else {
                        continuation.resume(throwing: NapaxiError.unavailable("Unable to capture browser screenshot"))
                        return
                    }
                    continuation.resume(returning: snapshot)
                }
            }
        }
    }
}

private struct NapaxiWebKitSnapshot {
    var pngData: Data?
    var width: Int
    var height: Int

    #if canImport(UIKit)
    init?(image: UIImage) {
        self.pngData = image.pngData()
        self.width = Int(image.size.width * image.scale)
        self.height = Int(image.size.height * image.scale)
    }
    #elseif canImport(AppKit)
    init?(image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        self.pngData = bitmap.representation(using: .png, properties: [:])
        self.width = bitmap.pixelsWide
        self.height = bitmap.pixelsHigh
    }
    #else
    init?<Image>(image: Image) {
        return nil
    }
    #endif
}
#endif
