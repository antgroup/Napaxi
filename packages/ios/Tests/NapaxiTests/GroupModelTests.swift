import XCTest
@testable import Napaxi

final class GroupModelTests: XCTestCase {
    func testGroupFacadePositionalOverloadsMirrorFlutterAPISurface() {
        let create: (NapaxiGroupAPI, String, [String]) throws -> String = { api, name, members in
            try api.create(name, members)
        }
        let rename: (NapaxiGroupAPI, String, String) throws -> Bool = { api, groupId, newName in
            try api.rename(groupId, newName)
        }
        let updateMembers: (NapaxiGroupAPI, String, [String]) throws -> Bool = { api, groupId, members in
            try api.updateMembers(groupId, members)
        }
        let send: (NapaxiGroupAPI, String, String, Int) throws -> [NapaxiChatEvent] = { api, groupId, message, maxIterations in
            try api.send(groupId, message, maxIterations: maxIterations)
        }
        let sendToAgent: (NapaxiGroupAPI, String, String, NapaxiSessionKey, String, Int) throws -> [NapaxiChatEvent] = { api, groupId, agentId, sessionKey, message, maxIterations in
            try api.sendToAgent(groupId, agentId, sessionKey, message, maxIterations: maxIterations)
        }
        let importState: (NapaxiGroupAPI, String) throws -> Bool = { api, stateJSON in
            try api.importState(stateJSON)
        }

        XCTAssertNotNil(create)
        XCTAssertNotNil(rename)
        XCTAssertNotNil(updateMembers)
        XCTAssertNotNil(send)
        XCTAssertNotNil(sendToAgent)
        XCTAssertNotNil(importState)
    }

    func testGroupEngineHelpersMirrorFlutterAPISurface() {
        let createGroup: (NapaxiEngine, String, [String]) throws -> String = { engine, name, members in
            try engine.createGroup(name, memberAgentIds: members)
        }
        let deleteGroup: (NapaxiEngine, String) throws -> Bool = { engine, groupId in
            try engine.deleteGroup(groupId)
        }
        let listGroups: (NapaxiEngine) throws -> [NapaxiGroupInfo] = { engine in
            try engine.listGroups()
        }
        let getGroup: (NapaxiEngine, String) throws -> NapaxiGroupInfo? = { engine, groupId in
            try engine.getGroup(groupId)
        }
        let renameGroup: (NapaxiEngine, String, String) throws -> Bool = { engine, groupId, newName in
            try engine.renameGroup(groupId, newName: newName)
        }
        let updateMembers: (NapaxiEngine, String, [String]) throws -> Bool = { engine, groupId, members in
            try engine.updateGroupMembers(groupId, memberAgentIds: members)
        }
        let setPrompt: (NapaxiEngine, String, String?) throws -> Bool = { engine, groupId, prompt in
            try engine.setGroupCustomPrompt(groupId, prompt: prompt)
        }
        let messages: (NapaxiEngine, String) throws -> [NapaxiGroupMessage] = { engine, groupId in
            try engine.getGroupMessages(groupId)
        }
        let clearHistory: (NapaxiEngine, String) throws -> Bool = { engine, groupId in
            try engine.clearGroupHistory(groupId)
        }
        let sendToGroup: (NapaxiEngine, String, String, Int) throws -> [NapaxiChatEvent] = { engine, groupId, message, maxIterations in
            try engine.sendToGroup(groupId, message, maxIterations: maxIterations)
        }
        let sendToGroupAgent: (NapaxiEngine, String, String, NapaxiSessionKey, String, Int) throws -> [NapaxiChatEvent] = { engine, groupId, agentId, sessionKey, message, maxIterations in
            try engine.sendToGroupAgent(groupId, agentId: agentId, sessionKey: sessionKey, message: message, maxIterations: maxIterations)
        }
        let exportState: (NapaxiEngine) throws -> String = { engine in
            try engine.exportGroupState()
        }
        let importState: (NapaxiEngine, String) throws -> Bool = { engine, stateJSON in
            try engine.importGroupState(stateJSON)
        }

        XCTAssertNotNil(createGroup)
        XCTAssertNotNil(deleteGroup)
        XCTAssertNotNil(listGroups)
        XCTAssertNotNil(getGroup)
        XCTAssertNotNil(renameGroup)
        XCTAssertNotNil(updateMembers)
        XCTAssertNotNil(setPrompt)
        XCTAssertNotNil(messages)
        XCTAssertNotNil(clearHistory)
        XCTAssertNotNil(sendToGroup)
        XCTAssertNotNil(sendToGroupAgent)
        XCTAssertNotNil(exportState)
        XCTAssertNotNil(importState)
    }

    func testGroupInfoDecodesFlutterCompatibleFields() throws {
        let group = try JSONDecoder().decode(
            NapaxiGroupInfo.self,
            from: Data(#"{"id":"g1","name":"Planning","members":["napaxi","planner"],"coordinator":"napaxi","createdAt":"2026-01-01T00:00:00Z","messageCount":7,"last_message_preview":"ship it","lastMessageTime":"2026-01-01T01:00:00Z","custom_prompt":"Be concise","future":true}"#.utf8)
        )
        let stringCountGroup = try JSONDecoder().decode(
            NapaxiGroupInfo.self,
            from: Data(#"{"id":"g2","name":"Planning","messageCount":"7"}"#.utf8)
        )
        let fractionalCountGroup = try JSONDecoder().decode(
            NapaxiGroupInfo.self,
            from: Data(#"{"id":"g3","name":"Planning","messageCount":7.5}"#.utf8)
        )

        XCTAssertEqual(group.id, "g1")
        XCTAssertEqual(group.name, "Planning")
        XCTAssertEqual(group.members, ["napaxi", "planner"])
        XCTAssertEqual(group.coordinator, "napaxi")
        XCTAssertEqual(group.createdAt, "2026-01-01T00:00:00Z")
        XCTAssertEqual(group.messageCount, 7)
        XCTAssertEqual(group.lastMessagePreview, "ship it")
        XCTAssertEqual(group.lastMessageTime, "2026-01-01T01:00:00Z")
        XCTAssertEqual(group.customPrompt, "Be concise")
        XCTAssertEqual(group.raw["future"], .bool(true))
        XCTAssertEqual(stringCountGroup.messageCount, 0)
        XCTAssertEqual(fractionalCountGroup.messageCount, 0)
    }

    func testGroupMapHelpersMirrorFlutterFactories() throws {
        let group = GroupInfo.fromMap([
            "id": .string("g1"),
            "name": .string("Planning"),
            "members": .array([.string("napaxi"), .string("planner")]),
            "coordinator": .string("napaxi"),
            "created_at": .string("2026-01-01T00:00:00Z"),
            "message_count": .number(7),
            "last_message_preview": .string("ship it"),
            "custom_prompt": .string("Be concise"),
            "future": .bool(true),
        ])
        let fromJSON = try GroupInfo.fromJson(
            #"{"id":"g2","name":"Research","members":["napaxi"],"message_count":3}"#
        )
        let message = GroupMessage.fromMap([
            "id": .string("m1"),
            "group_id": .string("g1"),
            "sender": .string("planner"),
            "content": .string("delegate"),
            "type": .string("tool_call"),
            "target_agent": .string("researcher"),
        ])

        XCTAssertEqual(group.id, "g1")
        XCTAssertEqual(group.members, ["napaxi", "planner"])
        XCTAssertEqual(group.messageCount, 7)
        XCTAssertEqual(group.lastMessagePreview, "ship it")
        XCTAssertEqual(group.customPrompt, "Be concise")
        XCTAssertEqual(group.toMap()["future"], .bool(true))
        XCTAssertEqual(fromJSON.id, "g2")
        XCTAssertEqual(fromJSON.messageCount, 3)
        XCTAssertThrowsError(try GroupInfo.fromJson(#"{"id":"g3","name":"Research","message_count":"3"}"#))
        XCTAssertThrowsError(try GroupInfo.fromJson(#"{"id":"g4","name":"Research","message_count":3.5}"#))
        XCTAssertEqual(message.groupId, "g1")
        XCTAssertEqual(message.messageType, .toolCall)
        XCTAssertTrue(message.isDelegation)
        XCTAssertEqual(message.toMap()["target_agent"], .string("researcher"))
    }

    func testGroupTypedDecodersSurfaceFlutterModelErrors() throws {
        func expectThrows(
            _ expression: @autoclosure () throws -> Any,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            do {
                _ = try expression()
                XCTFail("Expected expression to throw", file: file, line: line)
            } catch {
                // Expected.
            }
        }

        let validInfo: [String: NapaxiJSONValue] = [
            "id": .string("g1"),
            "name": .string("Planning"),
            "members": .array([.string("napaxi"), .string("planner")]),
            "coordinator": .string("napaxi"),
            "created_at": .string("2026-01-01T00:00:00Z"),
            "message_count": .number(2),
        ]
        let info = try NapaxiGroupAPI.decodeGroupInfo(from: .object(validInfo))
        XCTAssertEqual(info.id, "g1")
        XCTAssertEqual(info.members, ["napaxi", "planner"])
        XCTAssertEqual(info.messageCount, 2)

        let infos = try NapaxiGroupAPI.decodeGroupInfos(from: .array([
            .number(7),
            .object(validInfo),
        ]))
        XCTAssertEqual(infos.map(\.id), ["g1"])

        expectThrows(try GroupInfo.fromJson(#"{"members":["napaxi",7]}"#))
        expectThrows(try GroupInfo.fromJson(#"{"members":"napaxi"}"#))
        expectThrows(try GroupInfo.fromJson(#"{"message_count":"2"}"#))

        var malformedMembers = validInfo
        malformedMembers["members"] = .array([.string("napaxi"), .number(7)])
        expectThrows(try NapaxiGroupAPI.decodeGroupInfos(from: .array([.object(malformedMembers)])))

        var malformedCount = validInfo
        malformedCount["message_count"] = .number(2.5)
        expectThrows(try NapaxiGroupAPI.decodeGroupInfo(from: .object(malformedCount)))

        let validMessage: [String: NapaxiJSONValue] = [
            "id": .string("m1"),
            "group_id": .string("g1"),
            "sender": .string("planner"),
            "content": .string("delegate"),
            "type": .string("tool_call"),
            "timestamp": .string("2026-01-01T00:00:00Z"),
        ]
        let messages = try NapaxiGroupAPI.decodeGroupMessages(from: .array([
            .number(7),
            .object(validMessage),
        ]))
        XCTAssertEqual(messages.map(\.id), ["m1"])

        expectThrows(try GroupMessage.fromJsonString(#"{"content":7}"#))

        var malformedMessage = validMessage
        malformedMessage["content"] = .number(7)
        expectThrows(try NapaxiGroupAPI.decodeGroupMessages(from: .array([.object(malformedMessage)])))
    }

    func testGroupMessageDecodesTypeAndDelegationFields() throws {
        let message = try JSONDecoder().decode(
            NapaxiGroupMessage.self,
            from: Data(#"{"id":"m1","groupId":"g1","sender":"planner","content":"delegate","type":"tool_call","timestamp":"2026-01-01T00:00:00Z","toolCallId":"tc1","tool_name":"assign","target_agent":"researcher"}"#.utf8)
        )

        XCTAssertEqual(message.id, "m1")
        XCTAssertEqual(message.groupId, "g1")
        XCTAssertEqual(message.sender, "planner")
        XCTAssertEqual(message.content, "delegate")
        XCTAssertEqual(message.messageType, .toolCall)
        XCTAssertEqual(message.timestamp, "2026-01-01T00:00:00Z")
        XCTAssertEqual(message.toolCallId, "tc1")
        XCTAssertEqual(message.toolName, "assign")
        XCTAssertEqual(message.targetAgent, "researcher")
        XCTAssertFalse(message.isUser)
        XCTAssertFalse(message.isSystem)
        XCTAssertTrue(message.isDelegation)
    }

    func testGroupMessageTypePreservesUnknownValues() {
        let messageType = NapaxiGroupMessageType(rawValue: "handoff")
        let message = GroupMessage.fromMap([
            "id": .string("m1"),
            "group_id": .string("g1"),
            "sender": .string("agent"),
            "content": .string("future"),
            "type": .string("handoff"),
        ])
        let typedSystemMessage = GroupMessage.fromMap([
            "id": .string("m2"),
            "group_id": .string("g1"),
            "sender": .string("agent"),
            "content": .string("typed system"),
            "type": .string("system"),
        ])

        XCTAssertEqual(messageType.rawValue, "handoff")
        XCTAssertEqual(GroupMessageType.fromString("tool_call"), .toolCall)
        XCTAssertEqual(GroupMessageType.fromString("tool_result"), .toolResult)
        XCTAssertEqual(GroupMessageType.fromString("system"), .system)
        XCTAssertEqual(GroupMessageType.fromString("handoff"), .text)
        XCTAssertEqual(message.messageType, .text)
        XCTAssertEqual(message.raw["type"], .string("handoff"))
        XCTAssertEqual(NapaxiGroupMessageType.text.rawValue, "text")
        XCTAssertEqual(NapaxiGroupMessageType.toolResult.rawValue, "tool_result")
        XCTAssertEqual(NapaxiGroupMessageType.system.rawValue, "system")
        XCTAssertEqual(typedSystemMessage.messageType, .system)
        XCTAssertFalse(typedSystemMessage.isSystem)
    }

    func testGroupConstructorsEmitCoreSnakeCaseJSON() throws {
        let group = NapaxiGroupInfo(
            id: "g1",
            name: "Team",
            members: ["napaxi"],
            messageCount: 2,
            lastMessagePreview: "hello"
        )
        let message = NapaxiGroupMessage(
            id: "m1",
            groupId: "g1",
            sender: "system",
            content: "ready",
            messageType: .system,
            targetAgent: "napaxi"
        )

        XCTAssertEqual(group.raw["message_count"], .number(2))
        XCTAssertEqual(group.raw["last_message_preview"], .string("hello"))
        XCTAssertEqual(message.raw["group_id"], .string("g1"))
        XCTAssertEqual(message.raw["type"], .string("system"))
        XCTAssertTrue(message.isSystem)
        XCTAssertTrue(message.isDelegation)
    }

    func testGroupSendToAgentDecoderSurfacesNativeErrorLikeFlutter() throws {
        XCTAssertThrowsError(try NapaxiGroupAPI.decodeChatEvents(
            from: .object(["error": .string("agent unavailable")])
        )) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected group send to return a JSON array"))
        }

        XCTAssertThrowsError(try NapaxiGroupAPI.decodeChatEvents(
            from: .object(["error": .string("agent unavailable")]),
            propagatingJSONError: true
        )) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("agent unavailable"))
        }
    }

    func testGroupChatEventDecoderSurfacesFlutterEventParseErrors() throws {
        let events = try NapaxiGroupAPI.decodeChatEvents(from: .array([
            .number(7),
            .object([
                "type": .string("response"),
                "content": .string("hello"),
            ]),
            .object([
                "type": .string("unknown_future_event"),
            ]),
        ]))
        XCTAssertEqual(events.map(\.type), ["response", "unknown_future_event"])
        XCTAssertEqual(events.first?.content, "hello")

        XCTAssertThrowsError(try NapaxiGroupAPI.decodeChatEvents(from: .array([
            .object(["type": .string("response")]),
        ])))

        XCTAssertThrowsError(try NapaxiGroupAPI.decodeChatEvents(from: .array([
            .object([
                "type": .string("run_completed"),
                "run_id": .string("run-1"),
                "status": .string("completed"),
                "evidence_kind": .string("strong"),
                "verification": .string("verified"),
                "tool_call_count": .string("2"),
            ]),
        ])))

        XCTAssertThrowsError(try NapaxiGroupAPI.decodeChatEvents(from: .array([
            .object([
                "type": .string("asking_human"),
                "question": .string("Pick one"),
                "request_id": .string("req-1"),
                "options": .array([.string("A"), .number(1)]),
            ]),
        ])))

        XCTAssertThrowsError(try NapaxiGroupAPI.decodeChatEvents(from: .array([
            .object([
                "type": .string("evolution_queued"),
                "runs": .array([.object(["id": .string("run-1")])]),
            ]),
        ])))
    }
}
