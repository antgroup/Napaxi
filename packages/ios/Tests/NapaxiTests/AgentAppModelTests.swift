import XCTest
@testable import Napaxi

final class AgentAppModelTests: XCTestCase {
    func testSubmitResultAliasMirrorsFlutterAPISurface() {
        let submitResult: (NapaxiAgentAppAPI, NapaxiAgentAppActionResult) throws -> NapaxiAgentAppActionRecord = { api, result in
            try api.submitResult(result)
        }
        let submitResultJSON: (NapaxiAgentAppAPI, String) throws -> NapaxiJSONValue = { api, resultJSON in
            try api.submitResultJSON(resultJSON: resultJSON)
        }

        XCTAssertNotNil(submitResult)
        XCTAssertNotNil(submitResultJSON)
    }

    func testFlutterPositionalAgentAppFacadeAliasesCompile() {
        let getPackage: (NapaxiAgentAppAPI, String) throws -> NapaxiAgentAppPackage? = { api, agentId in
            try api.getPackage(agentId)
        }
        let getPackageJSON: (NapaxiAgentAppAPI, String) throws -> NapaxiJSONValue = { api, agentId in
            try api.getPackageJSON(agentId)
        }
        let deletePackage: (NapaxiAgentAppAPI, String) throws -> Bool = { api, agentId in
            try api.deletePackage(agentId)
        }
        let deletePackageJSON: (NapaxiAgentAppAPI, String) throws -> NapaxiJSONValue = { api, agentId in
            try api.deletePackageJSON(agentId)
        }
        let getProposal: (NapaxiAgentAppAPI, String) throws -> NapaxiAgentAppActionRecord? = { api, requestId in
            try api.getProposal(requestId)
        }
        let getProposalJSON: (NapaxiAgentAppAPI, String) throws -> NapaxiJSONValue = { api, requestId in
            try api.getProposalJSON(requestId)
        }

        XCTAssertNotNil(getPackage)
        XCTAssertNotNil(getPackageJSON)
        XCTAssertNotNil(deletePackage)
        XCTAssertNotNil(deletePackageJSON)
        XCTAssertNotNil(getProposal)
        XCTAssertNotNil(getProposalJSON)
    }

    func testAgentAppTypedDecodersSurfaceFlutterErrors() throws {
        let package = try NapaxiAgentAppAPI.decodePackage(from: .object([
            "provider_id": .string("provider"),
            "agent_id": .string("agent"),
            "display_name": .string("Agent"),
        ]))
        let record = try NapaxiAgentAppAPI.decodeActionRecord(from: .object([
            "proposal": .object([
                "request_id": .string("r1"),
                "provider_id": .string("provider"),
            ]),
            "status": .string("completed"),
        ]))

        XCTAssertEqual(package.agentId, "agent")
        XCTAssertEqual(record.proposal.requestId, "r1")
        XCTAssertThrowsError(try NapaxiAgentAppAPI.decodePackage(from: .object([
            "error": .string("register failed"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("register failed"))
        }
        XCTAssertThrowsError(try NapaxiAgentAppAPI.decodeActionRecord(from: .object([
            "error": .string("submit failed"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("submit failed"))
        }
        let nullProposalRecord = try NapaxiAgentAppAPI.decodeActionRecord(from: .object([
            "proposal": .null,
            "status": .string("pending"),
        ]))
        XCTAssertEqual(nullProposalRecord.proposal.requestId, "")
        XCTAssertThrowsError(try NapaxiAgentAppAPI.decodeActionRecord(from: .object([
            "proposal": .string("bad"),
            "status": .string("pending"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected agent app action record proposal object"))
        }
    }

    func testAgentAppTypedActionExecutorRejectsMalformedRequestLikeFlutter() async throws {
        let executor = RecordingAgentAppActionExecutor()
        let adapter = NapaxiAgentAppActionExecutorAdapter(executor: executor)

        let resultJSON = await adapter.executeAgentAppAction(requestJSON: """
        {
          "proposal": {"request_id": "r1"},
          "action": "bad",
          "package": {"agent_id": "agent"}
        }
        """)
        let raw = try NapaxiRawJSON(jsonString: resultJSON).value

        XCTAssertNil(executor.lastRequest)
        guard case .object(let object) = raw else {
            return XCTFail("Expected failed action result object")
        }
        XCTAssertEqual(object["request_id"], .string("r1"))
        XCTAssertEqual(object["status"], .string("failed"))
        XCTAssertTrue(object["error"]?.stringValue?.contains("Expected agent app action request action object") ?? false)
    }

    func testAgentAppPackageTypedAccessorsPreserveRawFields() throws {
        let json = """
        {
          "provider_id": "provider",
          "agent_id": "agent",
          "display_name": "Agent",
          "system_prompt": "Help",
          "actions": [
            {
              "action_id": "book",
              "tool_name": "provider.book",
              "description": "Book",
              "parameters": {"type": "object"},
              "execution_modes": ["handoff"],
              "timeout_seconds": 30
            }
          ],
          "install_binding": {
            "platform": "ios",
            "install_request_id": "req",
            "protocol_version": 2,
            "ios_bundle_id": "com.example.provider",
            "host_callback_scheme": "napaxi"
          },
          "unknown_future_field": {"nested": true}
        }
        """

        let package = try JSONDecoder().decode(NapaxiAgentAppPackage.self, from: Data(json.utf8))

        XCTAssertEqual(package.providerId, "provider")
        XCTAssertEqual(package.agentId, "agent")
        XCTAssertEqual(package.displayName, "Agent")
        XCTAssertEqual(package.systemPrompt, "Help")
        XCTAssertEqual(package.actions.first?.actionId, "book")
        XCTAssertEqual(package.actions.first?.toolName, "provider.book")
        XCTAssertEqual(package.actions.first?.executionModes, ["handoff"])
        XCTAssertEqual(package.actions.first?.timeoutSeconds, 30)
        XCTAssertEqual(package.installBinding?.platform, "ios")
        XCTAssertEqual(package.installBinding?.protocolVersion, 2)
        XCTAssertEqual(package.installBinding?.iosBundleId, "com.example.provider")
        XCTAssertEqual(package.installBinding?.hostCallbackScheme, "napaxi")
        XCTAssertEqual(package.raw["unknown_future_field"], .object(["nested": .bool(true)]))
    }

    func testAgentAppConstructorsEncodeFlutterCompatibleShape() throws {
        let action = NapaxiAgentAppActionManifest(
            actionId: "lookup",
            toolName: "provider.lookup",
            description: "Lookup",
            parameters: ["type": .string("object")]
        )
        let binding = NapaxiAgentAppInstallBinding(
            platform: "ios",
            appPackageName: "",
            activityName: "",
            signingCertSha256: "",
            installedAt: "now",
            installRequestId: "req",
            protocolVersion: 2,
            iosBundleId: "com.example.provider",
            hostBundleId: "com.example.host"
        )
        let package = NapaxiAgentAppPackage(
            providerId: "provider",
            agentId: "agent",
            displayName: "Agent",
            actions: [action],
            installBinding: binding
        )

        let value = try NapaxiRawJSON(jsonString: package.jsonString()).value
        guard case .object(let object) = value else {
            return XCTFail("package should encode as object")
        }

        XCTAssertEqual(object["provider_id"], .string("provider"))
        XCTAssertEqual(object["agent_id"], .string("agent"))
        if case .array(let actions)? = object["actions"],
           case .object(let first)? = actions.first {
            XCTAssertEqual(first["action_id"], .string("lookup"))
            XCTAssertEqual(first["tool_name"], .string("provider.lookup"))
        } else {
            XCTFail("actions should encode as object array")
        }
        if case .object(let encodedBinding)? = object["install_binding"] {
            XCTAssertEqual(encodedBinding["protocol_version"], .number(2))
            XCTAssertEqual(encodedBinding["ios_bundle_id"], .string("com.example.provider"))
            XCTAssertEqual(encodedBinding["host_bundle_id"], .string("com.example.host"))
        } else {
            XCTFail("install binding should encode as object")
        }
    }

    func testAgentAppMapHelpersMirrorFlutterModels() throws {
        let action = NapaxiAgentAppActionManifest.fromMap([
            "action_id": .string("lookup"),
            "tool_name": .string("provider.lookup"),
            "description": .string("Lookup"),
            "parameters": .object(["type": .string("object")]),
            "execution_modes": .array([
                .string("handoff"),
                .number(1),
                .bool(true),
                .object(["mode": .string("url")]),
            ]),
            "timeout_seconds": .number(45),
        ])

        XCTAssertEqual(action.toJson()["action_id"], .string("lookup"))
        XCTAssertEqual(action.toJson()["result_schema"], .object(["type": .string("object")]))
        XCTAssertEqual(action.toJson()["risk"], .string("high"))
        XCTAssertEqual(action.executionModes, ["handoff", "1", "true", "{mode: url}"])
        XCTAssertEqual(action.timeoutSeconds, 45)

        let defaultedAction = NapaxiAgentAppActionManifest.fromMap([
            "timeout_seconds": .string("45"),
        ])
        XCTAssertEqual(defaultedAction.timeoutSeconds, 600)

        let binding = NapaxiAgentAppInstallBinding.fromMap([
            "platform": .string("ios"),
            "app_package_name": .string(""),
            "activity_name": .string(""),
            "signing_cert_sha256": .string(""),
            "installed_at": .string("now"),
            "install_request_id": .string("req"),
            "protocol_version": .number(2),
            "ios_bundle_id": .string("com.example.provider"),
            "host_callback_scheme": .string("napaxi"),
            "background_trigger_supported": .bool(true),
        ])

        XCTAssertEqual(binding.toJson()["ios_bundle_id"], .string("com.example.provider"))
        XCTAssertEqual(binding.toJson()["host_callback_scheme"], .string("napaxi"))
        XCTAssertEqual(binding.toJson()["action_url"], nil)
        XCTAssertEqual(binding.toJson()["background_trigger_supported"], .bool(true))

        let defaultedBinding = NapaxiAgentAppInstallBinding.fromMap([
            "protocol_version": .string("2"),
        ])
        XCTAssertEqual(defaultedBinding.protocolVersion, 1)

        let package = NapaxiAgentAppPackage.fromMap([
            "provider_id": .string("provider"),
            "agent_id": .string("agent"),
            "display_name": .string("Agent"),
            "actions": .array([.object(action.toJson())]),
            "handoff": .object(["mode": .string("url")]),
            "install_binding": .object(binding.toJson()),
        ])

        XCTAssertEqual(package.actions.first?.toolName, "provider.lookup")
        XCTAssertEqual(package.toJson()["created_at"], nil)
        XCTAssertEqual(try NapaxiRawJSON(jsonString: package.toJsonString()).value.objectValue?["provider_id"], .string("provider"))
        if case .object(let encodedBinding)? = package.toJson()["install_binding"] {
            XCTAssertEqual(encodedBinding["platform"], .string("ios"))
        } else {
            XCTFail("package should encode install binding")
        }

        let proposal = NapaxiAgentAppActionProposal.fromMap([
            "request_id": .string("r1"),
            "provider_id": .string("provider"),
            "agent_id": .string("agent"),
            "action_id": .string("lookup"),
            "tool_name": .string("provider.lookup"),
            "arguments": .object(["q": .string("hello")]),
            "created_at": .string("start"),
            "expires_at": .string("end"),
            "nonce": .string("nonce"),
            "idempotency_key": .string("idem"),
            "signature": .string(""),
        ])

        XCTAssertEqual(proposal.toJson()["arguments"], .object(["q": .string("hello")]))
        XCTAssertEqual(proposal.toJson()["host_instance_id"], nil)
        XCTAssertEqual(proposal.toJson()["signature"], .string(""))

        let result = NapaxiAgentAppActionResult.fromMap([
            "request_id": .string("r1"),
            "status": .string("success"),
            "result": .object(["ok": .bool(true)]),
            "completed_at": .string("done"),
            "provider_trace_id": .string("trace"),
        ])
        let failedResult = NapaxiAgentAppActionResult.fromMap([
            "request_id": .string("r2"),
            "status": .string("failed"),
            "error": .object([
                "message": .string("denied"),
                "retry": .bool(false),
            ]),
            "completed_at": .string("done"),
        ])

        XCTAssertEqual(result.toJson()["provider_trace_id"], .string("trace"))
        XCTAssertEqual(try NapaxiRawJSON(jsonString: result.toJsonString()).value.objectValue?["status"], .string("success"))
        XCTAssertEqual(failedResult.error, "{message: denied, retry: false}")
        XCTAssertEqual(failedResult.toJson()["error"], .string("{message: denied, retry: false}"))
        XCTAssertNil(NapaxiAgentAppActionResult.fromMap([
            "request_id": .string("r3"),
            "status": .string("failed"),
            "error": .null,
            "completed_at": .string("done"),
        ]).error)

        let record = NapaxiAgentAppActionRecord.fromMap([
            "proposal": .object(proposal.toJson()),
            "status": .string("completed"),
            "result": .object(result.toJson()),
            "created_at": .string("start"),
            "updated_at": .string("done"),
        ])
        let request = NapaxiAgentAppActionRequest.fromMap([
            "proposal": .object(proposal.toJson()),
            "action": .object(action.toJson()),
            "package": .object(package.toJson()),
        ])

        XCTAssertEqual(record.proposal.requestId, "r1")
        XCTAssertEqual(record.result?.result["ok"], .bool(true))
        XCTAssertEqual(request.action.actionId, "lookup")
        XCTAssertEqual(request.package["agent_id"], .string("agent"))
    }

    func testAgentAppProposalResultAndRecordTypedAccessors() throws {
        let json = """
        {
          "proposal": {
            "request_id": "r1",
            "provider_id": "provider",
            "agent_id": "agent",
            "action_id": "lookup",
            "tool_name": "provider.lookup",
            "arguments": {"q": "hi"},
            "created_at": "start",
            "expires_at": "end",
            "nonce": "n",
            "idempotency_key": "idem"
          },
          "status": "completed",
          "result": {
            "request_id": "r1",
            "status": "success",
            "result": {"ok": true},
            "completed_at": "done"
          },
          "created_at": "start",
          "updated_at": "done"
        }
        """

        let record = try JSONDecoder().decode(NapaxiAgentAppActionRecord.self, from: Data(json.utf8))
        let structuredErrorResult = try JSONDecoder().decode(
            NapaxiAgentAppActionResult.self,
            from: Data(#"{"request_id":"r2","status":"failed","error":{"message":"denied","retry":false},"completed_at":"done"}"#.utf8)
        )

        XCTAssertEqual(record.proposal.requestId, "r1")
        XCTAssertEqual(record.proposal.arguments["q"], .string("hi"))
        XCTAssertEqual(record.status, "completed")
        XCTAssertEqual(record.result?.status, "success")
        XCTAssertEqual(record.result?.result["ok"], .bool(true))
        XCTAssertEqual(record.updatedAt, "done")
        XCTAssertEqual(structuredErrorResult.error, "{message: denied, retry: false}")
    }

    func testAgentAppDecodeHelpersMirrorFlutterHelpers() throws {
        let packages = try decodeAgentAppPackages("""
        [
          {
            "provider_id": "provider",
            "agent_id": "agent",
            "display_name": "Agent",
            "actions": [{"action_id": "lookup", "tool_name": "provider.lookup"}]
          },
          "ignored"
        ]
        """)
        let records = try decodeAgentAppActionRecords("""
        [
          {
            "proposal": {
              "request_id": "r1",
              "provider_id": "provider",
              "agent_id": "agent",
              "action_id": "lookup",
              "tool_name": "provider.lookup",
              "created_at": "start",
              "expires_at": "end",
              "nonce": "n",
              "idempotency_key": "idem"
            },
            "status": "pending",
            "created_at": "start",
            "updated_at": "start"
          },
          7
        ]
        """)

        XCTAssertEqual(packages.map(\.agentId), ["agent"])
        XCTAssertEqual(packages.first?.actions.first?.toolName, "provider.lookup")
        XCTAssertEqual(records.map(\.proposal.requestId), ["r1"])
        XCTAssertEqual(records.first?.status, "pending")
        XCTAssertEqual(try NapaxiAgentAppAPI.decodePackages(from: .object(["error": .string("ignored")])).count, 0)
        XCTAssertEqual(try NapaxiAgentAppAPI.decodeActionRecords(from: .string("ignored")).count, 0)
        XCTAssertEqual(try decodeAgentAppPackages(#"{"agent_id":"not-array"}"#), [])
        XCTAssertThrowsError(try decodeAgentAppActionRecords("""
        [
          {
            "proposal": "bad",
            "status": "pending"
          }
        ]
        """)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected agent app action record proposal object"))
        }
        XCTAssertThrowsError(try decodeAgentAppActionRecords("not json"))
    }
}

private final class RecordingAgentAppActionExecutor: AgentAppActionExecutor {
    private(set) var lastRequest: NapaxiAgentAppActionRequest?

    func execute(_ request: NapaxiAgentAppActionRequest) async throws -> NapaxiAgentAppActionResult {
        lastRequest = request
        return NapaxiAgentAppActionResult(
            requestId: request.proposal.requestId,
            status: "succeeded",
            completedAt: "1970-01-01T00:00:00Z"
        )
    }
}
