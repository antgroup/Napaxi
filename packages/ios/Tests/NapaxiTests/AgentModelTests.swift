import XCTest
@testable import Napaxi

final class AgentModelTests: XCTestCase {
    func testDefaultAgentDeleteMirrorsFlutterGuard() throws {
        let api = NapaxiAgentAPI(rawAPI: NapaxiRawAPI(handle: 0))

        XCTAssertFalse(try api.delete(NapaxiEngine.defaultAgentId))
        XCTAssertEqual(try api.deleteJSON(NapaxiEngine.defaultAgentId), .bool(false))
    }

    func testAgentConfigOverloadsMirrorFlutterAPISurface() {
        let getOrCreate: (NapaxiAgentAPI, String, NapaxiConfig?) throws -> NapaxiAgentHandle = { api, agentId, config in
            try api.getOrCreate(agentId, config: config)
        }
        let getOrCreateJSON: (NapaxiAgentAPI, String, String?) throws -> NapaxiJSONValue = { api, agentId, configJSON in
            try api.getOrCreateJSON(agentId, configJSON: configJSON)
        }
        let createFromDefinition: (NapaxiAgentAPI, String, NapaxiConfig?) throws -> Bool = { api, definitionId, config in
            try api.createFromDefinition(definitionId, config: config)
        }
        let createFromDefinitionJSON: (NapaxiAgentAPI, String, String?) throws -> NapaxiJSONValue = { api, definitionId, configJSON in
            try api.createFromDefinitionJSON(definitionId, configJSON: configJSON)
        }

        XCTAssertNotNil(getOrCreate)
        XCTAssertNotNil(getOrCreateJSON)
        XCTAssertNotNil(createFromDefinition)
        XCTAssertNotNil(createFromDefinitionJSON)
    }

    func testAgentFacadeSendMirrorsFlutterAPISurface() {
        let send: (NapaxiAgentAPI, NapaxiAgentHandle, NapaxiSessionKey, String, NapaxiConfig?, Int) throws -> [NapaxiChatEvent] = { api, agent, sessionKey, message, config, maxIterations in
            try api.send(agent, sessionKey, message, config: config, maxIterations: maxIterations)
        }

        XCTAssertNotNil(send)
    }

    func testAgentEngineHelpersMirrorFlutterAPISurface() {
        let getOrCreate: (NapaxiEngine, String, NapaxiConfig?) throws -> NapaxiAgentHandle = { engine, agentId, config in
            try engine.getOrCreateAgent(agentId, config: config)
        }
        let listAgents: (NapaxiEngine) throws -> [String] = { engine in
            try engine.listAgents()
        }
        let deleteAgent: (NapaxiEngine, String) throws -> Bool = { engine, agentId in
            try engine.deleteAgent(agentId)
        }
        let send: (NapaxiEngine, NapaxiAgentHandle, NapaxiSessionKey, String, NapaxiConfig?, Int) throws -> [NapaxiChatEvent] = { engine, agent, sessionKey, message, config, maxIterations in
            try engine.agentSend(agent, sessionKey, message, config: config, maxIterations: maxIterations)
        }
        let createDefinition: (NapaxiEngine, NapaxiAgentDefinition) throws -> NapaxiAgentDefinition = { engine, definition in
            try engine.createAgentDefinition(definition)
        }
        let listDefinitions: (NapaxiEngine) throws -> [NapaxiAgentDefinition] = { engine in
            try engine.listAgentDefinitions()
        }
        let getDefinition: (NapaxiEngine, String) throws -> NapaxiAgentDefinition? = { engine, definitionId in
            try engine.getAgentDefinition(definitionId)
        }
        let updateDefinition: (NapaxiEngine, NapaxiAgentDefinition) throws -> Bool = { engine, definition in
            try engine.updateAgentDefinition(definition)
        }
        let deleteDefinition: (NapaxiEngine, String) throws -> Bool = { engine, definitionId in
            try engine.deleteAgentDefinition(definitionId)
        }
        let importMarkdown: (NapaxiEngine, String) throws -> NapaxiAgentDefinition = { engine, content in
            try engine.importAgentMd(content)
        }
        let listAvailableTools: (NapaxiEngine) throws -> [NapaxiToolInfo] = { engine in
            try engine.listAvailableTools()
        }
        let createFromDefinition: (NapaxiEngine, String, NapaxiConfig?) throws -> Bool = { engine, definitionId, config in
            try engine.createAgentFromDefinition(definitionId, config: config)
        }

        XCTAssertNotNil(getOrCreate)
        XCTAssertNotNil(listAgents)
        XCTAssertNotNil(deleteAgent)
        XCTAssertNotNil(send)
        XCTAssertNotNil(createDefinition)
        XCTAssertNotNil(listDefinitions)
        XCTAssertNotNil(getDefinition)
        XCTAssertNotNil(updateDefinition)
        XCTAssertNotNil(deleteDefinition)
        XCTAssertNotNil(importMarkdown)
        XCTAssertNotNil(listAvailableTools)
        XCTAssertNotNil(createFromDefinition)
    }

    func testAgentEngineRunEventModelsMirrorFlutterSurface() {
        let request = AgentEngineRunEventRequest(
            runId: "run-1",
            sessionKeyJson: #"{"thread_id":"t1"}"#,
            event: ["type": .string("completed"), "tool_call_count": .number(1)]
        )

        XCTAssertEqual(request.runId, "run-1")
        XCTAssertEqual(request.sessionKeyJson, #"{"thread_id":"t1"}"#)
        XCTAssertEqual(request.event["type"], .string("completed"))

        let result = AgentEngineRunEventResult.fromMap([
            "event": .object(["type": .string("run_completed"), "run_id": .string("run-1")]),
            "final_content": .string(""),
            "is_error": .bool(false),
            "completed": .bool(true),
        ])

        XCTAssertEqual(result.event["type"], .string("run_completed"))
        XCTAssertEqual(result.finalContent, "")
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.completed)
    }

    func testAgentHandleDecodesFlutterCompatibleFields() throws {
        let handle = try JSONDecoder().decode(
            NapaxiAgentHandle.self,
            from: Data(#"{"agent_id":"planner"}"#.utf8)
        )

        XCTAssertEqual(handle.agentId, "planner")
        XCTAssertEqual(NapaxiAgentHandle(agentId: "researcher").raw["agent_id"], .string("researcher"))
    }

    func testAgentGetOrCreateDecoderMirrorsFlutterErrorHandling() throws {
        let handle = try NapaxiAgentAPI.decodeAgentHandle(
            from: .object(["agent_id": .string("planner")])
        )
        XCTAssertEqual(handle.agentId, "planner")

        XCTAssertThrowsError(try NapaxiAgentAPI.decodeAgentHandle(
            from: .object(["error": .string("agent failed")])
        )) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("agent failed"))
        }

        XCTAssertThrowsError(try NapaxiAgentAPI.decodeAgentHandle(
            from: .object(["agentId": .string("planner")])
        )) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected agent_id string"))
        }
    }

    func testAgentDefinitionDecodesToolFilterAndOptionalFields() throws {
        let definition = try JSONDecoder().decode(
            NapaxiAgentDefinition.self,
            from: Data(#"{"id":"planner","name":"Planner","description":"plans","system_prompt":"Plan carefully","provider":"openai","model":"gpt-5","model_profile_id":"fast","engine_id":"external_host","engine_profile_id":"dev-loop","engine_config":{"binary":"custom-agent"},"tool_filter":{"type":"Allowlist","tools":["calendar.create"]},"icon":"calendar"}"#.utf8)
        )

        XCTAssertEqual(definition.id, "planner")
        XCTAssertEqual(definition.name, "Planner")
        XCTAssertEqual(definition.description, "plans")
        XCTAssertEqual(definition.systemPrompt, "Plan carefully")
        XCTAssertEqual(definition.provider, "openai")
        XCTAssertEqual(definition.model, "gpt-5")
        XCTAssertEqual(definition.modelProfileId, "fast")
        XCTAssertEqual(definition.engineId, "external_host")
        XCTAssertEqual(definition.engineProfileId, "dev-loop")
        XCTAssertEqual(definition.engineConfig["binary"], .string("custom-agent"))
        XCTAssertEqual(definition.toolFilter, .allowlist)
        XCTAssertEqual(definition.toolList, ["calendar.create"])
        XCTAssertEqual(definition.icon, "calendar")
    }

    func testAgentDefinitionMapHelpersMirrorFlutterFactories() throws {
        let definition = try AgentDefinition.fromJson("""
        {
          "id": "planner",
          "name": "Planner",
          "description": "plans",
          "system_prompt": "Plan carefully",
          "provider": "openai",
          "model": "gpt-5",
          "model_profile_id": "fast",
          "engine_id": "external_host",
          "engine_profile_id": "dev-loop",
          "engine_config": {"binary": "custom-agent"},
          "tool_filter": {"type": "Allowlist", "tools": ["calendar.create"]},
          "icon": "calendar"
        }
        """)

        XCTAssertEqual(definition.id, "planner")
        XCTAssertEqual(definition.name, "Planner")
        XCTAssertEqual(definition.description, "plans")
        XCTAssertEqual(definition.systemPrompt, "Plan carefully")
        XCTAssertEqual(definition.provider, "openai")
        XCTAssertEqual(definition.model, "gpt-5")
        XCTAssertEqual(definition.modelProfileId, "fast")
        XCTAssertEqual(definition.engineId, "external_host")
        XCTAssertEqual(definition.engineProfileId, "dev-loop")
        XCTAssertEqual(definition.engineConfig["binary"], .string("custom-agent"))
        XCTAssertEqual(definition.toolFilter, .allowlist)
        XCTAssertEqual(definition.toolList, ["calendar.create"])
        XCTAssertEqual(definition.icon, "calendar")

        XCTAssertEqual(definition.toMap()["id"], .string("planner"))
        XCTAssertEqual(definition.toMap()["system_prompt"], .string("Plan carefully"))
        XCTAssertEqual(definition.toMap()["engine_id"], .string("external_host"))
        guard case .object(let engineConfig)? = definition.toMap()["engine_config"] else {
            return XCTFail("Expected engine_config object")
        }
        XCTAssertEqual(engineConfig["binary"], .string("custom-agent"))
        guard case .object(let filter)? = definition.toMap()["tool_filter"] else {
            return XCTFail("Expected tool_filter object")
        }
        XCTAssertEqual(filter["type"], .string("Allowlist"))
        XCTAssertEqual(filter["tools"], .array([.string("calendar.create")]))
        XCTAssertEqual(try NapaxiRawJSON(jsonString: definition.toJson()).value, .object(definition.toMap()))

        let defaulted = AgentDefinition.fromMap([
            "id": .string("empty"),
            "name": .string("Empty"),
            "provider": .string("  "),
            "model": .string(""),
            "model_profile_id": .string("  "),
            "icon": .string(""),
        ])

        XCTAssertEqual(defaulted.description, "")
        XCTAssertEqual(defaulted.systemPrompt, "")
        XCTAssertEqual(defaulted.provider, "  ")
        XCTAssertEqual(defaulted.model, "")
        XCTAssertEqual(defaulted.modelProfileId, "  ")
        XCTAssertEqual(defaulted.engineId, "napaxi_core")
        XCTAssertEqual(defaulted.engineProfileId, "")
        XCTAssertEqual(defaulted.engineConfig, [:])
        XCTAssertEqual(defaulted.toolFilter, .all)
        XCTAssertNil(defaulted.toolList)
        XCTAssertEqual(defaulted.icon, "")
        XCTAssertNil(defaulted.toMap()["provider"])
        XCTAssertNil(defaulted.toMap()["model"])
        XCTAssertNil(defaulted.toMap()["model_profile_id"])
        XCTAssertEqual(defaulted.toMap()["engine_id"], .string("napaxi_core"))
        XCTAssertNil(defaulted.toMap()["engine_profile_id"])
        XCTAssertNil(defaulted.toMap()["engine_config"])
        XCTAssertNil(defaulted.toMap()["icon"])
        guard case .object(let defaultFilter)? = defaulted.toMap()["tool_filter"] else {
            return XCTFail("Expected default tool_filter object")
        }
        XCTAssertEqual(defaultFilter["type"], .string("AllTools"))
        XCTAssertNil(defaultFilter["tools"])

        let camelCase = AgentDefinition.fromMap([
            "id": .string("reviewer"),
            "name": .string("Reviewer"),
            "systemPrompt": .string("Review carefully"),
            "modelProfileId": .string("balanced"),
            "toolFilter": .object([
                "type": .string("denylist"),
                "tools": .array([.string("shell.run")]),
            ]),
        ])

        XCTAssertEqual(camelCase.systemPrompt, "Review carefully")
        XCTAssertEqual(camelCase.modelProfileId, "balanced")
        XCTAssertEqual(camelCase.toolFilter, .denylist)
        XCTAssertEqual(camelCase.toolList, ["shell.run"])
    }

    func testAgentDefinitionTypedDecodersSurfaceFlutterErrors() throws {
        let valid: [String: NapaxiJSONValue] = [
            "id": .string("planner"),
            "name": .string("Planner"),
            "description": .string("plans"),
            "system_prompt": .string("Plan carefully"),
            "tool_filter": .object([
                "type": .string("Allowlist"),
                "tools": .array([.string("calendar.create")]),
            ]),
        ]

        let definition = try NapaxiAgentDefinitionAPI.decodeAgentDefinition(from: .object(valid))
        XCTAssertEqual(definition.id, "planner")
        XCTAssertEqual(definition.toolFilter, .allowlist)
        XCTAssertEqual(definition.toolList, ["calendar.create"])

        let definitions = try NapaxiAgentDefinitionAPI.decodeAgentDefinitions(from: .array([
            .number(7),
            .object(valid),
        ]))
        XCTAssertEqual(definitions.map(\.id), ["planner"])

        XCTAssertThrowsError(try AgentDefinition.fromJson(#"{"id":7}"#))
        XCTAssertThrowsError(try AgentDefinition.fromJson(#"{"tool_filter":[]}"#))
        XCTAssertThrowsError(try AgentDefinition.fromJson(#"{"tool_filter":{"type":7}}"#))
        XCTAssertThrowsError(try AgentDefinition.fromJson(#"{"tool_filter":{"tools":"shell.run"}}"#))
        XCTAssertThrowsError(try AgentDefinition.fromJson(#"{"tool_filter":{"tools":["shell.run",7]}}"#))

        var malformedId = valid
        malformedId["id"] = .number(7)
        XCTAssertThrowsError(try NapaxiAgentDefinitionAPI.decodeAgentDefinition(from: .object(malformedId)))

        var malformedFilter = valid
        malformedFilter["tool_filter"] = .array([])
        XCTAssertThrowsError(try NapaxiAgentDefinitionAPI.decodeAgentDefinitions(from: .array([.object(malformedFilter)])))

        var malformedTools = valid
        malformedTools["tool_filter"] = .object([
            "type": .string("Allowlist"),
            "tools": .array([.string("shell.run"), .number(7)]),
        ])
        XCTAssertThrowsError(try NapaxiAgentDefinitionAPI.decodeAgentDefinitions(from: .array([.object(malformedTools)])))
    }

    func testAgentDefinitionConstructorEmitsCoreShape() {
        let definition = NapaxiAgentDefinition(
            id: "planner",
            name: "Planner",
            provider: " openai ",
            model: "gpt-5",
            toolFilter: .denylist,
            toolList: ["shell.run"],
            icon: "calendar"
        )

        XCTAssertEqual(definition.raw["provider"], .string(" openai "))
        XCTAssertEqual(definition.toMap()["provider"], .string(" openai "))
        XCTAssertEqual(definition.raw["model"], .string("gpt-5"))
        XCTAssertEqual(definition.raw["icon"], .string("calendar"))
        guard case .object(let filter)? = definition.raw["tool_filter"] else {
            return XCTFail("Expected tool_filter object")
        }
        XCTAssertEqual(filter["type"], .string("Denylist"))
        XCTAssertEqual(filter["tools"], .array([.string("shell.run")]))
    }

    func testToolInfoDecodesFlutterCompatibleFields() throws {
        let tool = try JSONDecoder().decode(
            NapaxiToolInfo.self,
            from: Data(#"{"name":"calendar.create","description":"Create calendar events","future":true}"#.utf8)
        )

        XCTAssertEqual(tool.name, "calendar.create")
        XCTAssertEqual(tool.description, "Create calendar events")
        XCTAssertEqual(tool.raw["future"], .bool(true))
    }

    func testToolInfoFromMapMirrorsFlutterFactory() {
        let tool = ToolInfo.fromMap([
            "name": .string("calendar.create"),
            "description": .string("Create calendar events"),
            "future": .bool(true),
        ])

        XCTAssertEqual(tool.name, "calendar.create")
        XCTAssertEqual(tool.description, "Create calendar events")
        XCTAssertNil(tool.raw["future"])

        let defaulted = ToolInfo.fromMap([:])
        XCTAssertEqual(defaulted.name, "")
        XCTAssertEqual(defaulted.description, "")
    }

    func testToolInfoTypedListDecoderSurfacesFlutterFactoryErrors() throws {
        let valid: [String: NapaxiJSONValue] = [
            "name": .string("calendar.create"),
            "description": .string("Create calendar events"),
        ]
        let tools = try NapaxiAgentDefinitionAPI.decodeToolInfos(from: .array([
            .number(7),
            .object(valid),
        ]))
        XCTAssertEqual(tools.map(\.name), ["calendar.create"])

        var malformedName = valid
        malformedName["name"] = .number(7)
        XCTAssertThrowsError(try NapaxiAgentDefinitionAPI.decodeToolInfos(from: .array([.object(malformedName)])))

        var malformedDescription = valid
        malformedDescription["description"] = .bool(true)
        XCTAssertThrowsError(try NapaxiAgentDefinitionAPI.decodeToolInfos(from: .array([.object(malformedDescription)])))
    }
}
