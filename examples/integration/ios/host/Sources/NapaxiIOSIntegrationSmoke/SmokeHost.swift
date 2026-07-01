import Foundation
import Napaxi

public struct NapaxiIOSIntegrationSnapshot: Codable, Equatable, Sendable {
    public var filesDir: String
    public var platformContextJSON: String
    public var enabledCapabilities: [String]
    public var supportedCapabilities: [String]

    public init(
        filesDir: String,
        platformContextJSON: String,
        enabledCapabilities: [String],
        supportedCapabilities: [String]
    ) {
        self.filesDir = filesDir
        self.platformContextJSON = platformContextJSON
        self.enabledCapabilities = enabledCapabilities
        self.supportedCapabilities = supportedCapabilities
    }
}

public enum NapaxiIOSIntegrationSmoke {
    public static let filesDirName = "napaxi-ios-integration"

    public static func makeConfig(apiKey: String = "sk-integration-placeholder") -> NapaxiConfig {
        NapaxiConfig(
            provider: "openai",
            apiKey: apiKey,
            model: "gpt-4o-mini",
            systemPrompt: "You are running inside the Napaxi iOS integration smoke package.",
            maxToolIterations: 4
        )
    }

    public static func makeCapabilityProfile(rootfsAvailable: Bool = NapaxiIshSupport.isBundledRootfsAvailable) -> NapaxiCapabilityProfile {
        NapaxiCapabilityProfile(
            platform: "ios",
            supportedCapabilities: [
                "napaxi.tool.custom_host",
                "napaxi.platform_tool.*",
                "napaxi.tool.browser",
            ],
            disabledCapabilities: NapaxiIshSupport.disabledCapabilities(rootfsAvailable: rootfsAvailable)
        )
    }

    public static func makeCapabilitySelection() -> NapaxiCapabilitySelection {
        NapaxiCapabilitySelection(
            enabledCapabilities: [
                "napaxi.tool.custom_host",
                "napaxi.platform_tool.open_url",
            ]
        )
    }

    public static func makeFilesDir(baseDirectory: URL = FileManager.default.temporaryDirectory) -> String {
        baseDirectory.appendingPathComponent(filesDirName, isDirectory: true).path
    }

    public static func makePlatformContext(filesDir: String) throws -> NapaxiPlatformContext {
        try NapaxiPlatformContextResolver.resolve(
            filesDir: filesDir,
            platform: "ios",
            capabilityProfile: makeCapabilityProfile(),
            capabilitySelection: makeCapabilitySelection()
        )
    }

    public static func makeSnapshot(filesDir: String = makeFilesDir()) throws -> NapaxiIOSIntegrationSnapshot {
        let profile = makeCapabilityProfile()
        let selection = makeCapabilitySelection()
        let context = try NapaxiPlatformContextResolver.resolve(
            filesDir: filesDir,
            platform: "ios",
            capabilityProfile: profile,
            capabilitySelection: selection
        )
        return NapaxiIOSIntegrationSnapshot(
            filesDir: context.filesDir,
            platformContextJSON: context.platformContextJSON,
            enabledCapabilities: selection.enabledCapabilities,
            supportedCapabilities: profile.supportedCapabilities
        )
    }

    public static func createEngineForSmoke(
        filesDir: String = makeFilesDir(),
        toolExecutor: NapaxiToolExecutor = SmokeToolExecutor(),
        approvalHandler: NapaxiStructuredToolApprovalHandler = SmokeApprovalHandler(),
        platformToolExecutor: NapaxiPlatformToolExecutor = SmokePlatformToolExecutor()
    ) throws -> NapaxiEngine {
        try NapaxiEngine.create(
            config: makeConfig(),
            filesDir: filesDir,
            toolExecutor: toolExecutor,
            enablePlatformTools: true,
            capabilityProfile: makeCapabilityProfile(),
            capabilitySelection: makeCapabilitySelection(),
            platformToolExecutor: platformToolExecutor,
            structuredToolApprovalHandler: approvalHandler
        )
    }
}

public final class SmokeToolExecutor: NapaxiToolExecutor {
    public init() {}

    public func execute(toolName: String, paramsJSON: String, context: NapaxiJSONValue?) async -> Result<String, Error> {
        let payload: [String: NapaxiJSONValue] = [
            "tool": .string(toolName),
            "params_json": .string(paramsJSON),
            "ok": .bool(true),
        ]
        return .success((try? NapaxiRawJSON(.object(payload)).jsonString()) ?? #"{"ok":true}"#)
    }
}

public final class SmokeApprovalHandler: NapaxiStructuredToolApprovalHandler {
    public init() {}

    public func approve(_ request: NapaxiHostToolApprovalRequest) async -> NapaxiHostToolApprovalResponse {
        NapaxiHostToolApprovalResponse(
            approved: true,
            message: "Approved by iOS integration smoke host for \(request.toolName)"
        )
    }
}

public final class SmokePlatformToolExecutor: NapaxiPlatformToolExecutor {
    public init() {}

    public func executePlatformTool(name: String, params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        .object([
            "success": .bool(true),
            "tool": .string(name),
            "params": .object(params),
        ])
    }
}
