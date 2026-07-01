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
            let profile = Self.makeCapabilityProfile()
            let selection = Self.makeCapabilitySelection()
            let context = try NapaxiPlatformContextResolver.resolve(
                filesDir: filesDir,
                platform: "ios",
                capabilityProfile: profile,
                capabilitySelection: selection
            )
            let engine = try Self.makeEngineForSmoke(filesDir: filesDir)

            return [
                "Napaxi native iOS app smoke is ready.",
                "token=\(token)",
                "engineHandle=\(engine.handle)",
                "filesDir=\(context.filesDir)",
                "enabled=\(selection.enabledCapabilities.joined(separator: ","))",
                "rootfs=\(NapaxiIshSupport.isBundledRootfsAvailable)",
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
        return "manual"
    }

    static func makeFilesDir() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("napaxi-ios-app-integration", isDirectory: true)
            .path
    }

    static func makeCapabilityProfile() -> NapaxiCapabilityProfile {
        NapaxiCapabilityProfile(
            platform: "ios",
            supportedCapabilities: [
                "napaxi.tool.custom_host",
                "napaxi.platform_tool.*",
            ],
            disabledCapabilities: NapaxiIshSupport.disabledCapabilities()
        )
    }

    static func makeCapabilitySelection() -> NapaxiCapabilitySelection {
        NapaxiCapabilitySelection(
            enabledCapabilities: [
                "napaxi.tool.custom_host",
                "napaxi.platform_tool.open_url",
            ]
        )
    }

    static func makeEngineForSmoke(filesDir: String) throws -> NapaxiEngine {
        try NapaxiEngine.create(
            config: NapaxiConfig(
                provider: "openai",
                apiKey: "sk-integration-placeholder",
                model: "gpt-4o-mini",
                maxToolIterations: 4
            ),
            filesDir: filesDir,
            toolExecutor: AppToolExecutor(),
            enablePlatformTools: true,
            capabilityProfile: makeCapabilityProfile(),
            capabilitySelection: makeCapabilitySelection(),
            platformToolExecutor: AppPlatformToolExecutor(),
            structuredToolApprovalHandler: AppApprovalHandler()
        )
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
