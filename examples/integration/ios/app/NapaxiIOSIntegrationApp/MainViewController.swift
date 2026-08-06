import Napaxi
import UIKit

final class MainViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Napaxi iOS Integration"
        view.backgroundColor = .systemBackground

        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        let summary = buildSmokeSummary()
        statusLabel.text = summary
        Self.writeSmokeReport(summary)
    }

    private func buildSmokeSummary() -> String {
        do {
            let token = Self.smokeToken()
            let filesDir = Self.makeFilesDir()
            let rootfsRegistered = NapaxiIosQemuSandboxSupport.registerBundledRootfsArchive()
            let qemuReady = NapaxiIosQemuSandboxSupport.isReady(filesDir: filesDir)
            let profile = Self.makeCapabilityProfile(qemuReady: qemuReady)
            let selection = Self.makeCapabilitySelection(qemuReady: qemuReady)
            let context = try NapaxiPlatformContextResolver.resolve(
                filesDir: filesDir,
                platform: "ios",
                capabilityProfile: profile,
                capabilitySelection: selection
            )
            let engine = try Self.makeEngineForSmoke(filesDir: filesDir, qemuReady: qemuReady)
            let shellSmoke = qemuReady ? try Self.runQemuShellSmoke(engine: engine) : "skipped: qemuReady=false"

            return [
                "Napaxi native iOS app smoke is ready.",
                "token=\(token)",
                "engineHandle=\(engine.handle)",
                "filesDir=\(context.filesDir)",
                "enabled=\(selection.enabledCapabilities.joined(separator: ","))",
                "rootfs=\(NapaxiIosQemuSandboxSupport.isBundledRootfsAvailable)",
                "rootfsRegistered=\(rootfsRegistered)",
                "qemuRuntime=\(NapaxiIosQemuSandboxSupport.isRuntimeLinked)",
                "qemuReady=\(qemuReady)",
                "qemuShell=\(shellSmoke)",
            ].joined(separator: "\n")
        } catch {
            return "Napaxi native iOS app smoke failed: \(error)"
        }
    }

    static func smokeToken() -> String {
        let arguments = ProcessInfo.processInfo.arguments
        if let tokenFlagIndex = arguments.firstIndex(of: "--napaxi-smoke-token") {
            let tokenIndex = arguments.index(after: tokenFlagIndex)
            if arguments.indices.contains(tokenIndex) {
                return arguments[tokenIndex]
            }
        }

        if let environmentToken = ProcessInfo.processInfo.environment["NAPAXI_SMOKE_TOKEN"],
           !environmentToken.isEmpty {
            return environmentToken
        }

        return "manual"
    }

    static func makeFilesDir() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("napaxi-ios-app-integration", isDirectory: true)
            .path
    }

    static func makeCapabilityProfile(qemuReady: Bool = NapaxiIosQemuSandboxSupport.isBundledSandboxAvailable) -> NapaxiCapabilityProfile {
        NapaxiCapabilityProfile(
            platform: "ios",
            supportedCapabilities: [
                "napaxi.tool.custom_host",
                "napaxi.agent_engine.codex",
                NapaxiIosQemuSandboxSupport.sandboxCapabilityId,
                "napaxi.platform_tool.*",
            ],
            disabledCapabilities: qemuReady ? [] : [
                NapaxiIosQemuSandboxSupport.shellCapabilityId,
                NapaxiIosQemuSandboxSupport.codexCapabilityId,
                NapaxiIosQemuSandboxSupport.sandboxCapabilityId,
            ]
        )
    }

    static func makeCapabilitySelection(qemuReady: Bool = NapaxiIosQemuSandboxSupport.isBundledSandboxAvailable) -> NapaxiCapabilitySelection {
        NapaxiCapabilitySelection(
            enabledCapabilities: [
                "napaxi.tool.custom_host",
                qemuReady ? NapaxiIosQemuSandboxSupport.shellCapabilityId : nil,
                qemuReady ? NapaxiIosQemuSandboxSupport.codexCapabilityId : nil,
                qemuReady ? NapaxiIosQemuSandboxSupport.sandboxCapabilityId : nil,
                "napaxi.platform_tool.open_url",
            ].compactMap { $0 },
            disabledCapabilities: qemuReady ? [] : [
                NapaxiIosQemuSandboxSupport.shellCapabilityId,
                NapaxiIosQemuSandboxSupport.codexCapabilityId,
                NapaxiIosQemuSandboxSupport.sandboxCapabilityId,
            ]
        )
    }

    static func makeEngineForSmoke(filesDir: String, qemuReady: Bool = NapaxiIosQemuSandboxSupport.isBundledSandboxAvailable) throws -> NapaxiEngine {
        try NapaxiEngine.create(
            config: NapaxiConfig(
                provider: "openai",
                apiKey: "sk-integration-placeholder",
                model: "gpt-4o-mini",
                maxToolIterations: 4,
                shellSecurity: NapaxiShellSecurityConfig(approvalMode: .trustedAllow)
            ),
            filesDir: filesDir,
            toolExecutor: AppToolExecutor(),
            enablePlatformTools: true,
            capabilityProfile: makeCapabilityProfile(qemuReady: qemuReady),
            capabilitySelection: makeCapabilitySelection(qemuReady: qemuReady),
            platformToolExecutor: AppPlatformToolExecutor(),
            structuredToolApprovalHandler: AppApprovalHandler()
        )
    }


    static func runQemuShellSmoke(engine: NapaxiEngine) throws -> String {
        let arguments: [String: NapaxiJSONValue] = [
            "command": .string("echo napaxi-ios-qemu-smoke && pwd && uname -m"),
            "timeout": .number(20),
        ]
        let request = try NapaxiRawJSON(.object([
            "call_id": .string("ios-qemu-smoke-shell"),
            "name": .string("shell"),
            "arguments": .object(arguments),
        ])).jsonString()
        let result = try engine.api.call(
            namespace: "tools",
            method: "tool_broker_call_tool",
            payload: ["request_json": .string(request)]
        )
        let object = result.objectValue ?? [:]
        let output = object["output"]?.stringValue ?? ""
        let isError = object["is_error"]?.boolValue ?? true
        return "isError=\(isError); output=\(output.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private static func writeSmokeReport(_ summary: String) {
        do {
            let documentsDir = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let reportURL = documentsDir.appendingPathComponent("napaxi-ios-app-smoke.txt")
            try summary.write(to: reportURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Napaxi iOS app smoke report write failed: \(error)")
        }
    }
}

final class AppToolExecutor: NapaxiToolExecutor {
    func execute(toolName: String, paramsJSON: String, context: NapaxiJSONValue?) async -> Result<String, Error> {
        let payload: [String: NapaxiJSONValue] = [
            "tool": .string(toolName),
            "params_json": .string(paramsJSON),
            "ok": .bool(true),
        ]
        return .success((try? NapaxiRawJSON(.object(payload)).jsonString()) ?? #"{"ok":true}"#)
    }
}

final class AppApprovalHandler: NapaxiStructuredToolApprovalHandler {
    func approve(_ request: NapaxiHostToolApprovalRequest) async -> NapaxiHostToolApprovalResponse {
        NapaxiHostToolApprovalResponse(approved: true, message: "Approved by iOS app smoke")
    }
}

final class AppPlatformToolExecutor: NapaxiPlatformToolExecutor {
    func executePlatformTool(name: String, params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        .object([
            "success": .bool(true),
            "tool": .string(name),
            "params": .object(params),
        ])
    }
}
