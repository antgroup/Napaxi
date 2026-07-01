import XCTest
@testable import Napaxi

#if canImport(SwiftUI)
import SwiftUI
#endif

final class BrowserTests: XCTestCase {
    func testBrowserToolRequestDecodesTypedFields() throws {
        let request = try NapaxiBrowserToolRequest(
            toolName: "browser_open",
            paramsJSON: #"{"url":"https://example.com","mode":"desktop","screenshot_mode":"always","element_id":"login"}"#
        )

        XCTAssertEqual(request.toolName, "browser_open")
        XCTAssertEqual(request.url, "https://example.com")
        XCTAssertEqual(request.mode, .desktop)
        XCTAssertEqual(request.screenshotMode, .always)
        XCTAssertEqual(request.elementId, "login")
    }

    func testBrowserToolRequestParsesModeLikeFlutterController() throws {
        let defaulted = try NapaxiBrowserToolRequest(
            toolName: "browser_snapshot",
            paramsJSON: "{}"
        )
        let normalized = try NapaxiBrowserToolRequest(
            toolName: "browser_snapshot",
            paramsJSON: #"{"mode":" DESKTOP ","screenshot_mode":" ALWAYS "}"#
        )
        let invalid = try NapaxiBrowserToolRequest(
            toolName: "browser_snapshot",
            paramsJSON: #"{"mode":7,"screenshot_mode":"sometimes"}"#
        )

        XCTAssertEqual(defaulted.mode, .mobile)
        XCTAssertEqual(defaulted.screenshotMode, .auto)
        XCTAssertEqual(normalized.mode, .desktop)
        XCTAssertEqual(normalized.screenshotMode, .always)
        XCTAssertNil(invalid.mode)
        XCTAssertNil(invalid.screenshotMode)
    }

    func testBrowserAliasesMirrorFlutterAPISurface() throws {
        let mutationPolicy: BrowserMutationPolicy = .requireApproval
        let viewportMode: BrowserViewportMode = .desktop
        let screenshotMode: BrowserScreenshotMode = .always
        let capabilities = BrowserBackendCapabilities(supportsScreenshot: true)
        let screenshot = NapaxiBrowserScreenshot(sandboxPath: "screenshots/page.png", width: 100, height: 50)
        let backend: NapaxiBrowserBackend = RecordingBrowserBackend()
        let snapshot = NapaxiBrowserSnapshot(
            url: "https://example.com",
            title: "Example",
            loading: false,
            browserMode: viewportMode,
            text: "Hello",
            pageChangeToken: "token",
            backendCapabilities: capabilities,
            screenshot: screenshot
        )
        let request = try NapaxiBrowserToolRequest(toolName: "browser_snapshot", paramsJSON: "{}")
        let result = NapaxiBrowserToolResult.success(action: "browser_snapshot")

        XCTAssertEqual(mutationPolicy, .requireApproval)
        XCTAssertEqual(screenshotMode, .always)
        XCTAssertEqual(backend.progress, 0)
        XCTAssertTrue(snapshot.backendCapabilities.supportsScreenshot)
        XCTAssertEqual(snapshot.screenshot?.sandboxPath, "screenshots/page.png")
        XCTAssertEqual(request.toolName, "browser_snapshot")
        XCTAssertEqual(result.raw["success"], .bool(true))
    }

    func testBrowserControllerFlutterNamedConveniencesMirrorPublicSurface() async throws {
        let controller = RecordingBrowserController()
        controller.latestBrowserSnapshot = NapaxiBrowserSnapshot(
            url: "https://example.com",
            title: "Example",
            loading: false,
            browserMode: .mobile,
            text: "Hello",
            pageChangeToken: "token-1"
        )

        let result = try await controller.executeTool("browser_snapshot", "{}")
        controller.notifyBackendStateChanged()

        XCTAssertEqual(controller.calls.map(\.toolName), ["browser_snapshot"])
        XCTAssertEqual(controller.latestSnapshot?.pageChangeToken, "token-1")
        XCTAssertEqual(try NapaxiRawJSON(jsonString: result).value, .object([
            "success": .bool(true),
            "action": .string("browser_snapshot"),
        ]))
    }

    func testBrowserBackendFlutterSpellingAliasesDelegateToSwiftBackend() async throws {
        let backend = RecordingBrowserBackend()

        try await backend.loadUrl("https://example.com/path")
        let current = try await backend.currentUrl()

        XCTAssertEqual(backend.loadedURLs, ["https://example.com/path"])
        XCTAssertEqual(current, "https://example.com/path")
    }

    func testWebKitBrowserControllerMirrorsFlutterControllerSurface() {
        #if canImport(WebKit)
        let url: (NapaxiWebKitBrowserController) -> String? = { $0.url }
        let title: (NapaxiWebKitBrowserController) -> String? = { $0.title }
        let loading: (NapaxiWebKitBrowserController) -> Bool = { $0.loading }
        let progress: (NapaxiWebKitBrowserController) -> Int = { $0.progress }
        let hasPage: (NapaxiWebKitBrowserController) -> Bool = { $0.hasPage }
        let debugHighlightEnabled: (NapaxiWebKitBrowserController) -> Bool = { $0.debugHighlightEnabled }
        let browserMode: (NapaxiWebKitBrowserController) -> BrowserViewportMode = { $0.browserMode }
        let userAgent: (NapaxiWebKitBrowserController) -> String? = { $0.userAgent }
        let pageChangeToken: (NapaxiWebKitBrowserController) -> String? = { $0.pageChangeToken }
        let buildWebView: (NapaxiWebKitBrowserController) -> AnyObject = { $0.buildWebView() }
        let backendBuildWidget: (NapaxiWebKitBrowserBackend) -> AnyObject = { $0.buildWidget() }
        #if canImport(SwiftUI)
        let browserSurface: (NapaxiWebKitBrowserController) -> NapaxiBrowserSurface<EmptyView> = { controller in
            NapaxiBrowserSurface(controller: controller)
        }
        let browserWidget: (NapaxiWebKitBrowserController) -> NapaxiBrowserSurface<EmptyView> = { controller in
            controller.buildWidget()
        }
        let browserSurfaceWithPlaceholder: (NapaxiWebKitBrowserController) -> NapaxiBrowserSurface<Text> = { controller in
            NapaxiBrowserSurface(controller: controller) {
                Text("No page")
            }
        }
        #endif

        XCTAssertNotNil(url)
        XCTAssertNotNil(title)
        XCTAssertNotNil(loading)
        XCTAssertNotNil(progress)
        XCTAssertNotNil(hasPage)
        XCTAssertNotNil(debugHighlightEnabled)
        XCTAssertNotNil(browserMode)
        XCTAssertNotNil(userAgent)
        XCTAssertNotNil(pageChangeToken)
        XCTAssertNotNil(buildWebView)
        XCTAssertNotNil(backendBuildWidget)
        #if canImport(SwiftUI)
        XCTAssertNotNil(browserSurface)
        XCTAssertNotNil(browserWidget)
        XCTAssertNotNil(browserSurfaceWithPlaceholder)
        #endif
        #endif
    }

    func testBrowserResultUsesFlutterCompatibleKeys() throws {
        let result = NapaxiBrowserToolResult.failure(
            action: "browser_open",
            message: "Only http URLs are supported",
            failureCode: "unsupported_scheme"
        )

        let raw = try NapaxiRawJSON(jsonString: result.jsonString()).value

        XCTAssertEqual(raw, .object([
            "success": .bool(false),
            "action": .string("browser_open"),
            "blocked_or_approval_reason": .string("Only http URLs are supported"),
            "error": .string("Only http URLs are supported"),
            "failure_code": .string("unsupported_scheme"),
        ]))
    }

    func testBrowserSnapshotEncodesFlutterCompatibleShape() throws {
        let snapshot = NapaxiBrowserSnapshot(
            url: "https://example.com",
            title: "Example",
            loading: false,
            browserMode: .desktop,
            userAgent: NapaxiDesktopUserAgent,
            text: "Hello",
            elements: [["element_id": .string("login"), "text": .string("Log in")]],
            pageState: ["ready": .bool(true)],
            viewportMap: ["width": .number(1024), "height": .number(768)],
            pageChangeToken: "token-1",
            lastActionEffect: ["changed": .bool(true)],
            backendCapabilities: NapaxiBrowserBackendCapabilities(
                supportsScreenshot: true,
                supportsCoordinateClick: false,
                supportsEarlyScriptInjection: true,
                supportsCdpSelectorMap: true
            ),
            screenshot: NapaxiBrowserScreenshot(
                sandboxPath: "screenshots/page.png",
                width: 1024,
                height: 768
            )
        )

        let raw = try NapaxiRawJSON(jsonString: snapshot.jsonString()).value
        guard case .object(let object) = raw,
              case .array(let elements)? = object["elements"],
              case .object(let element)? = elements.first,
              case .object(let capabilities)? = object["backend_capabilities"],
              case .object(let screenshot)? = object["screenshot"] else {
            return XCTFail("Expected browser snapshot object")
        }

        XCTAssertEqual(object["url"], .string("https://example.com"))
        XCTAssertEqual(object["browser_mode"], .string("desktop"))
        XCTAssertEqual(object["user_agent"], .string(NapaxiDesktopUserAgent))
        XCTAssertEqual(element["element_id"], .string("login"))
        XCTAssertEqual(object["screenshot_available"], .bool(true))
        XCTAssertEqual(capabilities["supports_screenshot"], .bool(true))
        XCTAssertEqual(capabilities["supports_coordinate_click"], .bool(false))
        XCTAssertEqual(screenshot["sandbox_path"], .string("screenshots/page.png"))
        XCTAssertEqual(screenshot["mime_type"], .string("image/png"))
    }

    func testBrowserToJsonHelpersMirrorFlutterModels() {
        let capabilities = BrowserBackendCapabilities(
            supportsScreenshot: true,
            supportsCoordinateClick: false,
            supportsEarlyScriptInjection: true,
            supportsCdpSelectorMap: true
        )
        let screenshot = NapaxiBrowserScreenshot(
            sandboxPath: "screenshots/page.png",
            width: 1024,
            height: 768,
            mimeType: "image/jpeg"
        )
        let snapshot = NapaxiBrowserSnapshot(
            url: "https://example.com",
            title: "Example",
            loading: false,
            browserMode: .desktop,
            userAgent: napaxiDesktopUserAgent,
            text: "Hello",
            elements: [["element_id": .string("login")]],
            pageState: ["ready": .bool(true)],
            viewportMap: ["width": .number(1024)],
            pageChangeToken: "token-1",
            lastActionEffect: ["changed": .bool(true)],
            backendCapabilities: capabilities,
            screenshot: screenshot
        )

        XCTAssertEqual(capabilities.toJson(), [
            "supports_screenshot": .bool(true),
            "supports_coordinate_click": .bool(false),
            "supports_early_script_injection": .bool(true),
            "supports_cdp_selector_map": .bool(true),
        ])
        XCTAssertEqual(screenshot.toJson(), [
            "sandbox_path": .string("screenshots/page.png"),
            "mime_type": .string("image/jpeg"),
            "width": .number(1024),
            "height": .number(768),
        ])
        XCTAssertEqual(snapshot.toJson()["browser_mode"], .string("desktop"))
        XCTAssertEqual(snapshot.toJson()["user_agent"], .string(napaxiDesktopUserAgent))
        XCTAssertEqual(snapshot.toJson()["backend_capabilities"], .object(capabilities.toJson()))
        XCTAssertEqual(snapshot.toJson()["screenshot"], .object(screenshot.toJson()))
        XCTAssertEqual(snapshot.toJson()["screenshot_available"], .bool(true))
    }

    func testBrowserSnapshotDecodesFlutterCompatibleShape() throws {
        let json = #"{"url":"https://example.com","title":"Example","loading":true,"browser_mode":"mobile","user_agent":"ua","text":"Hello","elements":[{"element_id":"login"}],"page_state":{"ready":true},"viewport_map":{"width":390},"page_change_token":"token-1","last_action_effect":{"changed":true},"backend_capabilities":{"supports_screenshot":true,"supports_coordinate_click":false,"supports_early_script_injection":true,"supports_cdp_selector_map":true},"screenshot_available":true,"screenshot":{"sandbox_path":"screenshots/page.png","mime_type":"image/jpeg","width":390,"height":844}}"#
        let snapshot = try JSONDecoder().decode(NapaxiBrowserSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.url, "https://example.com")
        XCTAssertEqual(snapshot.title, "Example")
        XCTAssertTrue(snapshot.loading)
        XCTAssertEqual(snapshot.browserMode, .mobile)
        XCTAssertEqual(snapshot.userAgent, "ua")
        XCTAssertEqual(snapshot.elements.first?["element_id"], .string("login"))
        XCTAssertEqual(snapshot.pageState["ready"], .bool(true))
        XCTAssertEqual(snapshot.viewportMap["width"], .number(390))
        XCTAssertEqual(snapshot.pageChangeToken, "token-1")
        XCTAssertEqual(snapshot.lastActionEffect?["changed"], .bool(true))
        XCTAssertTrue(snapshot.backendCapabilities.supportsScreenshot)
        XCTAssertFalse(snapshot.backendCapabilities.supportsCoordinateClick)
        XCTAssertTrue(snapshot.backendCapabilities.supportsEarlyScriptInjection)
        XCTAssertTrue(snapshot.backendCapabilities.supportsCdpSelectorMap)
        XCTAssertEqual(snapshot.screenshot?.sandboxPath, "screenshots/page.png")
        XCTAssertEqual(snapshot.screenshot?.mimeType, "image/jpeg")
        XCTAssertEqual(snapshot.screenshot?.width, 390)
        XCTAssertEqual(snapshot.screenshot?.height, 844)
    }

    func testTypedBrowserExecutorAdapterReturnsJson() async throws {
        let executor = RecordingBrowserExecutor()
        let adapter = NapaxiBrowserControllerAdapter(executor: executor)

        let result = try await adapter.executeBrowserTool(
            toolName: "browser_snapshot",
            paramsJSON: #"{"screenshot_mode":"never"}"#
        )

        XCTAssertEqual(executor.lastRequest?.toolName, "browser_snapshot")
        XCTAssertEqual(executor.lastRequest?.screenshotMode, .never)
        XCTAssertEqual(try NapaxiRawJSON(jsonString: result).value, .object([
            "success": .bool(true),
            "action": .string("browser_snapshot"),
            "browser_mode": .string("mobile"),
        ]))
    }

    func testBrowserRuntimeControllerRejectsLocalFileOpenLikeFlutter() async throws {
        let backend = RecordingBrowserBackend()
        let controller = NapaxiBrowserRuntimeController(backend: backend)

        let result = try await controller.executeBrowserTool(
            toolName: "browser_open",
            paramsJSON: #"{"url":"report.html"}"#
        )
        let raw = try NapaxiRawJSON(jsonString: result).value

        XCTAssertEqual(backend.loadedURLs, [])
        guard case .object(let object) = raw else {
            return XCTFail("Expected browser result object")
        }
        XCTAssertEqual(object["success"], .bool(false))
        XCTAssertEqual(object["action"], .string("open"))
        XCTAssertEqual(object["failure_code"], .string("local_file_not_supported"))
    }

    func testBrowserRuntimeControllerSurfacesMalformedParamsLikeFlutter() async throws {
        let backend = RecordingBrowserBackend()
        let controller = NapaxiBrowserRuntimeController(backend: backend)

        let malformed = try await controller.executeBrowserTool(
            toolName: "browser_open",
            paramsJSON: "{"
        )
        let arrayParams = try await controller.executeBrowserTool(
            toolName: "browser_open",
            paramsJSON: "[]"
        )

        guard case .object(let malformedObject) = try NapaxiRawJSON(jsonString: malformed).value,
              case .object(let arrayObject) = try NapaxiRawJSON(jsonString: arrayParams).value else {
            return XCTFail("Expected browser result objects")
        }
        XCTAssertEqual(backend.loadedURLs, [])
        XCTAssertEqual(malformedObject["success"], .bool(false))
        XCTAssertEqual(malformedObject["action"], .string("browser_open"))
        XCTAssertNotNil(malformedObject["error"]?.stringValue)
        XCTAssertEqual(arrayObject["success"], .bool(false))
        XCTAssertEqual(arrayObject["action"], .string("open"))
        XCTAssertEqual(arrayObject["error"], .string("browser_open requires url"))
    }

    func testBrowserRuntimeControllerOpensAndSnapshotsWithBackend() async throws {
        let backend = RecordingBrowserBackend()
        let controller = NapaxiBrowserRuntimeController(backend: backend)

        let result = try await controller.executeBrowserTool(
            toolName: "browser_open",
            paramsJSON: #"{"url":"https://example.com","mode":"desktop"}"#
        )
        let raw = try NapaxiRawJSON(jsonString: result).value

        guard case .object(let object) = raw,
              case .array(let elements)? = object["elements"],
              case .object(let firstElement)? = elements.first,
              case .object(let viewportMap)? = object["viewport_map"],
              case .array(let textBlocks)? = viewportMap["visible_text_blocks"],
              case .array(let overlays)? = viewportMap["overlays"] else {
            return XCTFail("Expected browser open snapshot")
        }
        XCTAssertEqual(backend.loadedURLs, ["https://example.com"])
        XCTAssertEqual(backend.userAgents, [NapaxiDesktopUserAgent])
        XCTAssertEqual(object["success"], .bool(true))
        XCTAssertEqual(object["action"], .string("open"))
        XCTAssertEqual(object["browser_mode"], .string("desktop"))
        XCTAssertEqual(object["url"], .string("https://example.com"))
        XCTAssertEqual(firstElement["element_id"], .string("e_login"))
        XCTAssertEqual(textBlocks.first, .object([
            "text": .string("Welcome"),
            "near_action": .string("button"),
        ]))
        XCTAssertEqual(overlays.first, .object([
            "tag": .string("div"),
            "text": .string("Cookie notice"),
            "position": .string("fixed"),
        ]))
        XCTAssertEqual(viewportMap["diagnostics"], .array([.string("overlay_or_fixed_layer_present")]))
        XCTAssertEqual(controller.latestBrowserSnapshot?.elements.first?["text"], .string("Log in"))
    }

    func testBrowserRuntimeControllerCapturesScreenshotForSnapshotMode() async throws {
        let backend = RecordingBrowserBackend()
        backend.supportsScreenshot = true
        backend.screenshot = NapaxiBrowserScreenshot(
            sandboxPath: "screenshots/browser/page.png",
            width: 640,
            height: 480
        )
        let controller = NapaxiBrowserRuntimeController(backend: backend)

        _ = try await controller.executeBrowserTool(
            toolName: "browser_open",
            paramsJSON: #"{"url":"https://example.com"}"#
        )
        let result = try await controller.executeBrowserTool(
            toolName: "browser_snapshot",
            paramsJSON: #"{"screenshot_mode":"always"}"#
        )
        let raw = try NapaxiRawJSON(jsonString: result).value

        guard case .object(let object) = raw,
              case .object(let screenshot)? = object["screenshot"] else {
            return XCTFail("Expected screenshot metadata")
        }
        XCTAssertEqual(object["screenshot_available"], .bool(true))
        XCTAssertEqual(screenshot["sandbox_path"], .string("screenshots/browser/page.png"))
        XCTAssertEqual(screenshot["width"], .number(640))
        XCTAssertEqual(screenshot["height"], .number(480))
        XCTAssertEqual(backend.screenshotModes, [.always])
    }

    func testBrowserApprovalDeniesCoordinateClickWithoutExecuting() async throws {
        let controller = RecordingBrowserController()
        let approvals = BrowserApprovalRecorder(response: NapaxiHostToolApprovalResponse(approved: false))
        let gated = NapaxiBrowserApprovalController(
            controller: controller,
            mutationPolicy: .requireApproval,
            approvalHandler: nil,
            structuredApprovalHandler: approvals
        )

        let result = try await gated.executeBrowserTool(
            toolName: "browser_click",
            paramsJSON: #"{"click_point":{"x":20,"y":40}}"#
        )

        XCTAssertEqual(controller.calls.count, 0)
        XCTAssertEqual(approvals.requests.map(\.description), ["Approve coordinate browser click"])
        XCTAssertEqual(try NapaxiRawJSON(jsonString: result).value, .object([
            "success": .bool(false),
            "action": .string("browser_click"),
            "blocked_or_approval_reason": .string("Browser action requires user approval"),
        ]))
    }

    func testBrowserToolHostMirrorsFlutterHostFacade() async throws {
        let controller = RecordingBrowserController()
        let approvals = BrowserApprovalRecorder(response: NapaxiHostToolApprovalResponse(approved: false))
        let host = FlutterBrowserToolHost(
            controller: controller,
            structuredApprovalHandler: approvals
        )

        let result = try await host.execute(
            "browser_click",
            paramsJSON: #"{"click_point":{"x":20,"y":40}}"#
        )

        XCTAssertTrue(host.canHandle("browser_open"))
        XCTAssertFalse(host.canHandle("open_url"))
        XCTAssertEqual(controller.calls.count, 0)
        XCTAssertEqual(approvals.requests.map(\.description), ["Approve coordinate browser click"])
        XCTAssertEqual(try NapaxiRawJSON(jsonString: result).value, .object([
            "success": .bool(false),
            "action": .string("browser_click"),
            "blocked_or_approval_reason": .string("Browser action requires user approval"),
        ]))
    }

    func testBrowserToolHostWrapsControllerErrorsLikeFlutterController() async throws {
        let host = FlutterBrowserToolHost(
            controller: ThrowingBrowserController(),
            mutationPolicy: .allowAll
        )

        let result = try await host.execute("browser_snapshot", paramsJSON: "{}")

        XCTAssertEqual(try NapaxiRawJSON(jsonString: result).value, .object([
            "success": .bool(false),
            "action": .string("browser_snapshot"),
            "blocked_or_approval_reason": .string("invalidState(\"backend unavailable\")"),
            "error": .string("invalidState(\"backend unavailable\")"),
        ]))
    }

    func testBrowserApprovalAllowsRiskyElementClick() async throws {
        let controller = RecordingBrowserController()
        controller.latestBrowserSnapshot = NapaxiBrowserSnapshot(
            url: "https://example.com",
            title: "Checkout",
            loading: false,
            browserMode: .mobile,
            text: "Pay now",
            elements: [["element_id": .string("pay-button"), "text": .string("Pay now")]],
            pageChangeToken: "token-1"
        )
        let approvals = BrowserApprovalRecorder(response: NapaxiHostToolApprovalResponse(approved: true))
        let gated = NapaxiBrowserApprovalController(
            controller: controller,
            mutationPolicy: .requireApproval,
            approvalHandler: nil,
            structuredApprovalHandler: approvals
        )

        let result = try await gated.executeBrowserTool(
            toolName: "browser_click",
            paramsJSON: #"{"element_id":"pay-button"}"#
        )

        XCTAssertEqual(approvals.requests.map(\.description), ["Approve high-risk browser click"])
        XCTAssertEqual(controller.calls.map { $0.toolName }, ["browser_click"])
        XCTAssertEqual(try NapaxiRawJSON(jsonString: result).value, .object([
            "success": .bool(true),
            "action": .string("browser_click"),
        ]))
    }

    func testBrowserApprovalAllowsPolicyBypass() async throws {
        let controller = RecordingBrowserController()
        let approvals = BrowserApprovalRecorder(response: NapaxiHostToolApprovalResponse(approved: false))
        let gated = NapaxiBrowserApprovalController(
            controller: controller,
            mutationPolicy: .allowAll,
            approvalHandler: nil,
            structuredApprovalHandler: approvals
        )

        let result = try await gated.executeBrowserTool(
            toolName: "browser_click",
            paramsJSON: #"{"click_point":{"x":20,"y":40}}"#
        )

        XCTAssertTrue(approvals.requests.isEmpty)
        XCTAssertEqual(controller.calls.map { $0.toolName }, ["browser_click"])
        XCTAssertEqual(try NapaxiRawJSON(jsonString: result).value, .object([
            "success": .bool(true),
            "action": .string("browser_click"),
        ]))
    }

    func testBrowserApprovalGatesTypeSubmit() async throws {
        let controller = RecordingBrowserController()
        let approvals = BrowserApprovalRecorder(response: NapaxiHostToolApprovalResponse(approved: true))
        let gated = NapaxiBrowserApprovalController(
            controller: controller,
            mutationPolicy: .requireApproval,
            approvalHandler: nil,
            structuredApprovalHandler: approvals
        )

        _ = try await gated.executeBrowserTool(
            toolName: "browser_type",
            paramsJSON: #"{"text":"hello","submit":true}"#
        )

        XCTAssertEqual(approvals.requests.map(\.description), ["Approve browser typing and submit"])
        XCTAssertEqual(controller.calls.map { $0.toolName }, ["browser_type"])
    }

    func testBrowserApprovalUsesLegacyHandlerWhenStructuredUnavailable() async throws {
        let controller = RecordingBrowserController()
        let approvals = LegacyBrowserApprovalRecorder(approved: true)
        let gated = NapaxiBrowserApprovalController(
            controller: controller,
            mutationPolicy: .requireApproval,
            approvalHandler: approvals,
            structuredApprovalHandler: nil
        )

        _ = try await gated.executeBrowserTool(
            toolName: "browser_click",
            paramsJSON: #"{"label":"Delete"}"#
        )

        XCTAssertEqual(approvals.toolNames, ["browser_click"])
        XCTAssertEqual(controller.calls.map { $0.toolName }, ["browser_click"])
    }

    func testBrowserProviderRecognizesFallbackTools() {
        XCTAssertTrue(NapaxiBrowserToolProvider.isBrowserTool("browser_open"))
        XCTAssertFalse(NapaxiBrowserToolProvider.isBrowserTool("browser_custom"))
        XCTAssertFalse(NapaxiBrowserToolProvider.isBrowserTool("open_url"))
        XCTAssertEqual(NapaxiBrowserToolProvider.capabilityId, "napaxi.tool.browser")

        let definitions = BrowserToolProvider.getToolDefinitions()
        XCTAssertEqual(Set(definitions.map(\.name)), NapaxiBrowserToolProvider.toolNames)
        XCTAssertEqual(definitions.first(where: { $0.name == "browser_snapshot" })?.effect, "read")
    }
}

private final class RecordingBrowserController: NapaxiBrowserController, NapaxiBrowserSnapshotProvider {
    var latestBrowserSnapshot: NapaxiBrowserSnapshot?
    var calls: [(toolName: String, paramsJSON: String)] = []

    func executeBrowserTool(toolName: String, paramsJSON: String) async throws -> String {
        calls.append((toolName: toolName, paramsJSON: paramsJSON))
        return try NapaxiBrowserToolResult.success(action: toolName).jsonString()
    }
}

private final class ThrowingBrowserController: NapaxiBrowserController {
    func executeBrowserTool(toolName: String, paramsJSON: String) async throws -> String {
        throw NapaxiError.invalidState("backend unavailable")
    }
}

private final class RecordingBrowserExecutor: NapaxiBrowserToolExecutor {
    var lastRequest: NapaxiBrowserToolRequest?

    func executeBrowserTool(_ request: NapaxiBrowserToolRequest) async throws -> NapaxiBrowserToolResult {
        lastRequest = request
        return .success(action: request.toolName, values: ["browser_mode": .string("mobile")])
    }
}

private final class RecordingBrowserBackend: NapaxiBrowserBackend {
    var loadedURLs: [String] = []
    var userAgents: [String?] = []
    var current = "https://example.com"
    var pageTitle = "Example"
    var supportsScreenshot = false
    var screenshot: NapaxiBrowserScreenshot?
    var screenshotModes: [NapaxiBrowserScreenshotMode] = []

    var capabilities: NapaxiBrowserBackendCapabilities {
        NapaxiBrowserBackendCapabilities(supportsScreenshot: supportsScreenshot)
    }

    func loadURL(_ url: String) async throws {
        loadedURLs.append(url)
        current = url
    }

    func setUserAgent(_ userAgent: String?) async throws {
        userAgents.append(userAgent)
    }

    func captureScreenshot(mode: NapaxiBrowserScreenshotMode) async throws -> NapaxiBrowserScreenshot? {
        screenshotModes.append(mode)
        return screenshot
    }

    func reload() async throws {}

    func currentURL() async throws -> String? {
        current
    }

    func title() async throws -> String? {
        pageTitle
    }

    func canGoBack() async throws -> Bool {
        false
    }

    func goBack() async throws {}

    func runJavaScript(_ javaScript: String) async throws {}

    func runJavaScriptReturningResult(_ javaScript: String) async throws -> Any? {
        if javaScript.contains("document.readyState") {
            return #"{"ready":"complete","url":"https://example.com","title":"Example"}"#
        }
        if javaScript.contains("window.__napaxiBrowser.snapshot()") {
            return """
            {
              "url": "https://example.com",
              "title": "Example",
              "text": "Welcome",
              "elements": [
                {"element_id":"e_login","text":"Log in","label":"Log in","tag":"button","role":"button"}
              ],
              "viewport_map": {
                "width": 1280,
                "height": 720,
                "visible_text_blocks": [
                  {"text":"Welcome","near_action":"button"}
                ],
                "visible_clickable_elements": [
                  {"element_id":"e_login","text":"Log in","action_hint":"button"}
                ],
                "overlays": [
                  {"tag":"div","text":"Cookie notice","position":"fixed"}
                ],
                "diagnostics": ["overlay_or_fixed_layer_present"]
              },
              "page_change_token": "token-1",
              "page_state": {
                "url": "https://example.com",
                "title": "Example",
                "text": "Welcome",
                "elements": [
                  {"element_id":"e_login","text":"Log in","label":"Log in","tag":"button","role":"button"}
                ],
                "viewport_map": {
                  "width": 1280,
                  "height": 720,
                  "visible_text_blocks": [
                    {"text":"Welcome","near_action":"button"}
                  ],
                  "visible_clickable_elements": [
                    {"element_id":"e_login","text":"Log in","action_hint":"button"}
                  ],
                  "overlays": [
                    {"tag":"div","text":"Cookie notice","position":"fixed"}
                  ],
                  "diagnostics": ["overlay_or_fixed_layer_present"]
                },
                "page_change_token": "token-1"
              }
            }
            """
        }
        return nil
    }

    func clearCache() async throws {}

    func clearLocalStorage() async throws {}
}

private final class BrowserApprovalRecorder: NapaxiStructuredToolApprovalHandler {
    private let response: NapaxiHostToolApprovalResponse
    private(set) var requests: [NapaxiHostToolApprovalRequest] = []

    init(response: NapaxiHostToolApprovalResponse) {
        self.response = response
    }

    func approve(_ request: NapaxiHostToolApprovalRequest) async -> NapaxiHostToolApprovalResponse {
        requests.append(request)
        return response
    }
}

private final class LegacyBrowserApprovalRecorder: NapaxiToolApprovalHandler {
    private let approved: Bool
    private(set) var toolNames: [String] = []
    private(set) var requestJSONValues: [String] = []

    init(approved: Bool) {
        self.approved = approved
    }

    func approve(toolName: String, requestJSON: String) async -> Bool {
        toolNames.append(toolName)
        requestJSONValues.append(requestJSON)
        return approved
    }
}
