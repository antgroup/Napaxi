import XCTest
@testable import Napaxi

final class CapabilityTests: XCTestCase {
    func testCapabilityAPIAliasesMirrorFlutterFacadeNames() {
        let listDefinitions: (NapaxiCapabilityAPI) throws -> [NapaxiCapabilityDefinition] = { api in
            try api.listDefinitions()
        }
        let listStatuses: (NapaxiCapabilityAPI, NapaxiCapabilityProfile?, NapaxiCapabilitySelection?) throws -> [NapaxiCapabilityStatus] = { api, profile, selection in
            try api.listStatuses(profile: profile, selection: selection)
        }
        let listStatusesJSON: (NapaxiCapabilityAPI, NapaxiCapabilityProfile?, NapaxiCapabilitySelection?) throws -> NapaxiJSONValue = { api, profile, selection in
            try api.listStatusesJSON(profile: profile, selection: selection)
        }
        let listStatusesRawJSON: (NapaxiCapabilityAPI, String, String) throws -> NapaxiJSONValue = { api, profileJSON, selectionJSON in
            try api.listStatusesJSON(profileJSON: profileJSON, selectionJSON: selectionJSON)
        }
        let listScenarioPacks: (NapaxiCapabilityAPI) throws -> [NapaxiScenarioPack] = { api in
            try api.listScenarioPacks()
        }
        let listScenarioStatuses: (NapaxiCapabilityAPI, NapaxiCapabilityProfile?, NapaxiCapabilitySelection?) throws -> [NapaxiScenarioStatus] = { api, profile, selection in
            try api.listScenarioStatuses(profile: profile, selection: selection)
        }
        let resolveScenario: (NapaxiCapabilityAPI, String) throws -> NapaxiScenarioResolution? = { api, scenarioId in
            try api.resolveScenario(scenarioId)
        }
        let installScenarioPack: (NapaxiCapabilityAPI, NapaxiScenarioPack) throws -> NapaxiScenarioPackInstallResult? = { api, pack in
            try api.installScenarioPack(pack)
        }
        let removeScenarioPack: (NapaxiCapabilityAPI, String) throws -> NapaxiScenarioPackRemovalResult? = { api, scenarioId in
            try api.removeScenarioPack(scenarioId)
        }
        let providerCapabilityId: (NapaxiCapabilityAPI, String) throws -> String = { api, provider in
            try api.providerCapabilityId(provider)
        }
        let agentEngineCapabilityId: (NapaxiCapabilityAPI, String) throws -> String = { api, engineId in
            try api.agentEngineCapabilityId(engineId)
        }
        let toolCapabilityId: (NapaxiCapabilityAPI, String) throws -> String = { api, toolName in
            try api.toolCapabilityId(toolName)
        }

        XCTAssertNotNil(listDefinitions)
        XCTAssertNotNil(listStatuses)
        XCTAssertNotNil(listStatusesJSON)
        XCTAssertNotNil(listStatusesRawJSON)
        XCTAssertNotNil(listScenarioPacks)
        XCTAssertNotNil(listScenarioStatuses)
        XCTAssertNotNil(resolveScenario)
        XCTAssertNotNil(installScenarioPack)
        XCTAssertNotNil(removeScenarioPack)
        XCTAssertNotNil(providerCapabilityId)
        XCTAssertNotNil(agentEngineCapabilityId)
        XCTAssertNotNil(toolCapabilityId)
    }

    func testCapabilitySelectionPreservesFlutterConfigMap() throws {
        let selection = NapaxiCapabilitySelection(
            enabledCapabilities: ["napaxi.llm.openai"],
            disabledCapabilities: ["napaxi.tool.shell"],
            config: [
                "napaxi.llm.openai": .object([
                    "profile_id": .string("primary"),
                    "temperature": .number(0.2),
                ]),
            ]
        )

        let decoded = try XCTUnwrap(decodeObject(try selection.jsonString()))
        let config = try XCTUnwrap(decoded["config"] as? [String: Any])
        let openAIConfig = try XCTUnwrap(config["napaxi.llm.openai"] as? [String: Any])

        XCTAssertEqual(decoded["enabled_capabilities"] as? [String], ["napaxi.llm.openai"])
        XCTAssertEqual(decoded["disabled_capabilities"] as? [String], ["napaxi.tool.shell"])
        XCTAssertEqual(openAIConfig["profile_id"] as? String, "primary")
        XCTAssertEqual(openAIConfig["temperature"] as? Double, 0.2)
    }

    func testCapabilityMapHelpersMirrorFlutterToJson() throws {
        let profile = NapaxiCapabilityProfile(
            platform: "ios",
            supportedCapabilities: ["napaxi.platform_tool.*"],
            disabledCapabilities: ["napaxi.tool.shell"]
        )
        let selection = NapaxiCapabilitySelection(
            enabledCapabilities: ["napaxi.tool.browser"],
            disabledCapabilities: ["napaxi.tool.shell"],
            config: ["napaxi.tool.browser": .object(["mode": .string("webkit")])]
        )
        let definition = NapaxiCapabilityDefinition.fromJson([
            "id": .string("napaxi.tool.browser"),
            "kind": .string("tool"),
            "version": .string("1"),
            "platforms": .array([.string("ios"), .number(2.5), .object(["mode": .string("host")])]),
            "config_schema": .object(["type": .string("object")]),
            "risk": .string("medium"),
            "requirements": .array([.string("host_ui"), .bool(true)]),
            "default_enabled": .bool(false),
            "activation": .string("host"),
        ])
        let status = NapaxiCapabilityStatus.fromJson([
            "definition": .object(definition.toJson()),
            "registered": .bool(true),
            "available": .bool(true),
            "enabled": .bool(false),
            "unavailable_reason": .string("disabled"),
        ])

        let profileJSON = try XCTUnwrap(decodeObject(try profile.toJsonString()))
        let selectionJSON = try XCTUnwrap(decodeObject(try selection.toJsonString()))
        let statusJSON = status.toJson()

        XCTAssertEqual(profile.toJson()["platform"], .string("ios"))
        XCTAssertEqual(profileJSON["supported_capabilities"] as? [String], ["napaxi.platform_tool.*"])
        XCTAssertEqual(selectionJSON["enabled_capabilities"] as? [String], ["napaxi.tool.browser"])
        XCTAssertEqual(definition.platforms, ["ios", "2.5", "{mode: host}"])
        XCTAssertEqual(definition.requirements, ["host_ui", "true"])
        XCTAssertEqual(definition.toJson()["config_schema"], .object(["type": .string("object")]))
        XCTAssertEqual(status.definition.id, "napaxi.tool.browser")
        XCTAssertEqual(statusJSON["unavailable_reason"], .string("disabled"))
        XCTAssertTrue(status.registered)
        XCTAssertTrue(status.available)
        XCTAssertFalse(status.enabled)
    }

    func testScenarioMapHelpersMirrorFlutterToJson() throws {
        let pack = NapaxiScenarioPack(
            id: "napaxi.scenario.mobile_development",
            version: "1",
            label: "Mobile Development",
            description: "Mobile development scene",
            risk: "high",
            activation: "host_policy",
            executionPlanes: ["core", "host_bridge"],
            requiredCapabilities: ["napaxi.service.scenario_registry"],
            recommendedCapabilities: ["napaxi.tool.web_fetch"],
            optionalCapabilities: ["napaxi.service.automation"],
            uiSurfaces: ["chat", "ticket_panel"],
            settingsContributions: [
                NapaxiScenarioSettingsContribution(
                    id: "settings.git",
                    capabilityId: "napaxi.tool.git",
                    placement: "scenario_settings",
                    title: "Git",
                    schema: [
                        "type": .string("object"),
                        "properties": .object([
                            "token": .object(["type": .string("secret")])
                        ]),
                    ],
                    actions: ["save", "clear_credentials"]
                )
            ],
            uiContributions: [
                NapaxiScenarioUiContribution(
                    id: "ui.repo_workbench",
                    capabilityId: "napaxi.tool.git",
                    placement: "left_menu",
                    title: "Repositories",
                    icon: "folder_git",
                    renderer: "repo_workbench",
                    dataSources: ["repositories": .string("git.repositories")],
                    actions: ["open_repository", "search_files"]
                )
            ],
            memoryScopes: ["workspace", "ticket"],
            tags: ["developer", "mobile"]
        )
        let status = NapaxiScenarioStatus(
            definition: pack,
            registered: true,
            available: false,
            enabled: false,
            missingRequiredCapabilities: ["napaxi.tool.git"],
            disabledRequiredCapabilities: ["napaxi.policy.approval"],
            unavailableReasons: ["requires host support"]
        )
        let plan = NapaxiScenarioActivationPlan(
            enabledCapabilities: ["napaxi.tool.shell_remote"],
            hostRequiredCapabilities: ["napaxi.policy.approval"],
            remoteRequiredCapabilities: ["napaxi.tool.shell_remote"],
            policyRequiredCapabilities: ["napaxi.policy.approval"],
            warnings: ["critical risk"]
        )
        let resolution = NapaxiScenarioResolution(status: status, activationPlan: plan)
        let install = NapaxiScenarioPackInstallResult(
            definition: pack,
            installed: true,
            replaced: false,
            warnings: ["core execution plane was added"]
        )
        let removal = NapaxiScenarioPackRemovalResult(
            scenarioId: "napaxi.scenario.mobile_development",
            removed: true
        )

        XCTAssertEqual(NapaxiScenarioPack.fromJson(pack.toJson()).id, "napaxi.scenario.mobile_development")
        XCTAssertEqual(NapaxiScenarioPack.fromJson(pack.toJson()).settingsContributions.first?.id, "settings.git")
        XCTAssertEqual(NapaxiScenarioPack.fromJson(pack.toJson()).settingsContributions.first?.actions.last, "clear_credentials")
        XCTAssertEqual(NapaxiScenarioPack.fromJson(pack.toJson()).uiContributions.first?.id, "ui.repo_workbench")
        XCTAssertEqual(NapaxiScenarioPack.fromJson(pack.toJson()).uiContributions.first?.renderer, "repo_workbench")
        XCTAssertEqual(NapaxiScenarioPack.fromJson(pack.toJson()).uiContributions.first?.dataSources["repositories"], .string("git.repositories"))
        XCTAssertEqual(NapaxiScenarioPack.fromJson(pack.toJson()).uiContributions.first?.actions.last, "search_files")
        XCTAssertEqual(status.missingRequiredCapabilities, ["napaxi.tool.git"])
        XCTAssertEqual(resolution.activationPlan.remoteRequiredCapabilities, ["napaxi.tool.shell_remote"])
        XCTAssertEqual(install.definition.id, "napaxi.scenario.mobile_development")
        XCTAssertTrue(install.installed)
        XCTAssertFalse(install.replaced)
        XCTAssertEqual(removal.scenarioId, "napaxi.scenario.mobile_development")
        XCTAssertTrue(removal.removed)
        XCTAssertEqual(try decodeScenarioPacks("[\(try pack.jsonString())]").first?.id, "napaxi.scenario.mobile_development")
        XCTAssertEqual(try decodeScenarioStatuses("[\(try status.jsonString())]").first?.missingRequiredCapabilities, ["napaxi.tool.git"])
        XCTAssertEqual(try decodeScenarioResolution(try resolution.jsonString())?.activationPlan.remoteRequiredCapabilities, ["napaxi.tool.shell_remote"])
        XCTAssertEqual(try decodeScenarioPackInstallResult(try install.jsonString())?.definition.id, "napaxi.scenario.mobile_development")
        XCTAssertEqual(try decodeScenarioPackRemovalResult(try removal.jsonString())?.scenarioId, "napaxi.scenario.mobile_development")
        XCTAssertNil(try decodeScenarioResolution(#"{"error":{"code":"unknown_scenario"}}"#))
        XCTAssertNil(try decodeScenarioPackInstallResult(#"{"error":{"code":"invalid"}}"#))
        XCTAssertNil(try decodeScenarioPackRemovalResult(#"{"error":{"code":"invalid"}}"#))
    }

    func testCapabilityDefinitionDecodesFlutterCompatibleKeys() throws {
        let json = """
        {
          "id": "napaxi.tool.shell",
          "kind": "tool",
          "version": "1",
          "platforms": ["ios", "android", 2.5, {"mode": "host"}],
          "config_schema": {"type": "object"},
          "risk": "high",
          "requirements": ["host_policy", true],
          "default_enabled": false,
          "activation": "host"
        }
        """

        let definition = try JSONDecoder().decode(NapaxiCapabilityDefinition.self, from: Data(json.utf8))

        XCTAssertEqual(definition.id, "napaxi.tool.shell")
        XCTAssertEqual(definition.kind, "tool")
        XCTAssertEqual(definition.platforms, ["ios", "android", "2.5", "{mode: host}"])
        XCTAssertEqual(definition.configSchema["type"], .string("object"))
        XCTAssertEqual(definition.risk, "high")
        XCTAssertEqual(definition.requirements, ["host_policy", "true"])
        XCTAssertFalse(definition.defaultEnabled)
        XCTAssertEqual(definition.activation, "host")
    }

    func testCapabilityStatusDecodesMissingFieldsWithFlutterDefaults() throws {
        let json = """
        {
          "definition": {"id": "napaxi.platform_tool.open_url"},
          "registered": true
        }
        """

        let status = try JSONDecoder().decode(NapaxiCapabilityStatus.self, from: Data(json.utf8))

        XCTAssertEqual(status.definition.id, "napaxi.platform_tool.open_url")
        XCTAssertEqual(status.definition.kind, "")
        XCTAssertTrue(status.registered)
        XCTAssertFalse(status.available)
        XCTAssertFalse(status.enabled)
        XCTAssertNil(status.unavailableReason)
    }

    func testCapabilityArrayDecodingFromRawJSONValue() throws {
        let raw = NapaxiJSONValue.array([
            .object([
                "id": .string("napaxi.tool.custom_host"),
                "kind": .string("tool"),
                "version": .string("1"),
                "platforms": .array([.string("ios")]),
                "risk": .string("medium"),
                "default_enabled": .bool(false),
                "activation": .string("host"),
            ]),
        ])

        let decoded = try raw.decodedArray(of: NapaxiCapabilityDefinition.self)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, "napaxi.tool.custom_host")
        XCTAssertEqual(decoded[0].platforms, ["ios"])
    }

    func testCapabilityDecodeHelpersMirrorFlutterHelpers() throws {
        let definitions = try decodeCapabilityDefinitions("""
        [
          {
            "id": "napaxi.tool.browser",
            "kind": "tool",
            "version": "1",
            "platforms": ["ios"],
            "risk": "medium",
            "default_enabled": false,
            "activation": "host"
          },
          "ignored"
        ]
        """)
        let statuses = try decodeCapabilityStatuses("""
        [
          {
            "definition": {"id": "napaxi.platform_tool.open_url"},
            "registered": true,
            "available": true,
            "enabled": true
          },
          42
        ]
        """)

        XCTAssertEqual(definitions.map(\.id), ["napaxi.tool.browser"])
        XCTAssertEqual(statuses.map(\.definition.id), ["napaxi.platform_tool.open_url"])
        XCTAssertTrue(statuses[0].enabled)
        XCTAssertEqual(try NapaxiCapabilityAPI.decodeDefinitions(from: .object(["error": .string("ignored")])).count, 0)
        XCTAssertEqual(try NapaxiCapabilityAPI.decodeStatuses(from: .string("ignored")).count, 0)
        XCTAssertEqual(try decodeCapabilityDefinitions(#"{"id":"not-array"}"#), [])
        XCTAssertThrowsError(try decodeCapabilityStatuses("not json"))
    }

    func testCapabilityTypedDecodersSurfaceFlutterFactoryErrors() throws {
        let definitions = try NapaxiCapabilityAPI.decodeDefinitions(from: .array([
            .number(42),
            .object([
                "id": .string("napaxi.tool.browser"),
                "kind": .string("tool"),
                "version": .string("1"),
                "platforms": .array([.string("ios"), .number(2), .bool(true)]),
                "config_schema": .string("ignored like Flutter"),
                "risk": .string("medium"),
                "requirements": .array([.string("host_ui"), .bool(true)]),
                "default_enabled": .bool(false),
                "activation": .string("host"),
            ]),
        ]))
        let statuses = try NapaxiCapabilityAPI.decodeStatuses(from: .array([
            .string("ignored"),
            .object([
                "definition": .object([
                    "id": .string("napaxi.platform_tool.open_url"),
                    "platforms": .array([.string("ios")]),
                ]),
                "registered": .bool(true),
                "available": .bool(true),
                "enabled": .bool(false),
                "unavailable_reason": .string("disabled"),
            ]),
        ]))

        XCTAssertEqual(definitions.map(\.id), ["napaxi.tool.browser"])
        XCTAssertEqual(definitions[0].platforms, ["ios", "2", "true"])
        XCTAssertEqual(definitions[0].requirements, ["host_ui", "true"])
        XCTAssertEqual(definitions[0].configSchema, [:])
        XCTAssertEqual(statuses.map(\.definition.id), ["napaxi.platform_tool.open_url"])
        XCTAssertTrue(statuses[0].registered)
        XCTAssertTrue(statuses[0].available)
        XCTAssertFalse(statuses[0].enabled)
        XCTAssertEqual(statuses[0].unavailableReason, "disabled")

        XCTAssertEqual(try NapaxiCapabilityAPI.decodeDefinitions(from: .string("not-array")), [])
        XCTAssertEqual(try NapaxiCapabilityAPI.decodeStatuses(from: .object(["ignored": .bool(true)])), [])
        XCTAssertThrowsError(try NapaxiCapabilityAPI.decodeDefinitions(from: .array([
            .object(["id": .number(1)]),
        ])))
        XCTAssertThrowsError(try NapaxiCapabilityAPI.decodeDefinitions(from: .array([
            .object(["platforms": .string("ios")]),
        ])))
        XCTAssertThrowsError(try NapaxiCapabilityAPI.decodeDefinitions(from: .array([
            .object(["default_enabled": .string("true")]),
        ])))
        XCTAssertThrowsError(try NapaxiCapabilityAPI.decodeStatuses(from: .array([
            .object(["definition": .string("bad")]),
        ])))
        XCTAssertThrowsError(try NapaxiCapabilityAPI.decodeStatuses(from: .array([
            .object(["registered": .string("true")]),
        ])))
        XCTAssertThrowsError(try NapaxiCapabilityAPI.decodeStatuses(from: .array([
            .object(["unavailable_reason": .number(1)]),
        ])))
    }

    func testCapabilityAPIUsesDefaultProfileWhenStatusProfileIsOmitted() throws {
        let defaultProfile = NapaxiCapabilityProfile(
            platform: "ios",
            supportedCapabilities: ["napaxi.platform_tool.*"],
            disabledCapabilities: ["napaxi.tool.shell"]
        )
        let overrideProfile = NapaxiCapabilityProfile(
            platform: "ios",
            supportedCapabilities: ["napaxi.tool.browser"]
        )
        let api = NapaxiCapabilityAPI(
            rawAPI: NapaxiRawAPI(handle: 0),
            defaultProfile: defaultProfile
        )

        let defaultJSON = try XCTUnwrap(decodeObject(try api.statusProfileJSON(nil)))
        let overrideJSON = try XCTUnwrap(decodeObject(try api.statusProfileJSON(overrideProfile)))

        XCTAssertEqual(defaultJSON["supported_capabilities"] as? [String], ["napaxi.platform_tool.*"])
        XCTAssertEqual(defaultJSON["disabled_capabilities"] as? [String], ["napaxi.tool.shell"])
        XCTAssertEqual(overrideJSON["supported_capabilities"] as? [String], ["napaxi.tool.browser"])
    }
}

private func decodeObject(_ value: String) throws -> [String: Any]? {
    let decoded = try JSONSerialization.jsonObject(with: Data(value.utf8))
    return decoded as? [String: Any]
}
