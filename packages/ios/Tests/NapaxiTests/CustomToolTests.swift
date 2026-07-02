import XCTest
@testable import Napaxi

final class CustomToolTests: XCTestCase {
    func testCustomToolDefinitionEncodesFlutterCompatibleKeys() throws {
        let tool = NapaxiCustomToolDefinition(
            name: "lookup_order",
            description: "Look up an order by id",
            parameters: [
                "type": .string("object"),
                "required": .array([.string("order_id")]),
                "properties": .object([
                    "order_id": .object([
                        "type": .string("string"),
                    ]),
                ]),
            ],
            effect: "read"
        )

        let json = try tool.jsonString()
        let decoded = try XCTUnwrap(decodeObject(json))
        let parameters = try XCTUnwrap(decoded["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])

        XCTAssertEqual(decoded["name"] as? String, "lookup_order")
        XCTAssertEqual(decoded["description"] as? String, "Look up an order by id")
        XCTAssertEqual(decoded["effect"] as? String, "read")
        XCTAssertNotNil(properties["order_id"])
    }

    func testCustomToolMapHelpersMirrorFlutterToJsonFromJson() throws {
        let tool = NapaxiCustomToolDefinition.fromJson([
            "name": .string("lookup_order"),
            "description": .string("Look up an order by id"),
            "parameters": .object([
                "type": .string("object"),
                "properties": .object([
                    "order_id": .object(["type": .string("string")]),
                ]),
            ]),
            "effect": .string("read"),
        ])
        let defaulted = CustomToolDef.fromJson([
            "name": .string("noop"),
            "description": .string("No op"),
            "parameters": .string("bad"),
        ])

        let json = tool.toJson()
        let jsonString = try tool.toJsonString()
        let decoded = try XCTUnwrap(decodeObject(jsonString))
        let parameters = try XCTUnwrap(json["parameters"])

        XCTAssertEqual(json["name"], .string("lookup_order"))
        XCTAssertEqual(json["description"], .string("Look up an order by id"))
        XCTAssertEqual(json["effect"], .string("read"))
        XCTAssertEqual(decoded["name"] as? String, "lookup_order")
        XCTAssertEqual(parameters, .object([
            "type": .string("object"),
            "properties": .object([
                "order_id": .object(["type": .string("string")]),
            ]),
        ]))
        XCTAssertEqual(defaulted.name, "noop")
        XCTAssertEqual(defaulted.parameters, NapaxiCustomToolDefinition.defaultParameters)
        XCTAssertEqual(defaulted.effect, "unknown")
    }

    func testCustomToolDefinitionDecodesWithFlutterDefaults() throws {
        let raw = #"{"name":"noop","description":"No op","parameters":"bad"}"#

        let tool = try JSONDecoder().decode(NapaxiCustomToolDefinition.self, from: Data(raw.utf8))

        XCTAssertEqual(tool.name, "noop")
        XCTAssertEqual(tool.description, "No op")
        XCTAssertEqual(tool.effect, "unknown")
        XCTAssertEqual(tool.parameters, NapaxiCustomToolDefinition.defaultParameters)
    }

    func testCustomToolArrayJSONMatchesBridgePayloadShape() throws {
        let json = try NapaxiCustomToolDefinition.jsonString(for: [
            NapaxiCustomToolDefinition(name: "a", description: "A"),
            NapaxiCustomToolDefinition(name: "b", description: "B", effect: "write"),
        ])
        let decoded = try XCTUnwrap(decodeArray(json))

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.first?["name"] as? String, "a")
        XCTAssertEqual(decoded.first?["effect"] as? String, "unknown")
        XCTAssertEqual(decoded.last?["name"] as? String, "b")
        XCTAssertEqual(decoded.last?["effect"] as? String, "write")
    }

    func testToolAPIDecodesDescriptorArraysLikeFlutterProvider() throws {
        let descriptors = NapaxiJSONValue.array([
            .object([
                "name": .string("open_url"),
                "description": .string("Open a URL"),
                "parameters": .object(["type": .string("object")]),
                "effect": .string("external"),
            ]),
            .object([
                "description": .string("Ignored because Flutter providers drop empty tool names"),
            ]),
            .string("ignored"),
            .object([
                "name": .string("browser_snapshot"),
                "description": .string("Snapshot browser"),
            ]),
        ])

        let tools = try NapaxiToolAPI.toolDefinitions(from: descriptors)

        XCTAssertEqual(tools.map(\.name), ["open_url", "browser_snapshot"])
        XCTAssertEqual(tools.first?.parameters["type"], .string("object"))
        XCTAssertEqual(tools.first?.effect, "external")
        XCTAssertEqual(tools.last?.effect, "unknown")
    }

    func testToolAPITypedDecoderSurfacesFlutterFactoryErrors() throws {
        let descriptors = NapaxiJSONValue.array([
            .number(1),
            .object([
                "name": .string("open_url"),
                "description": .string("Open a URL"),
                "parameters": .string("ignored like Flutter"),
                "effect": .string("external"),
            ]),
        ])

        let tools = try NapaxiToolAPI.toolDefinitions(from: descriptors)

        XCTAssertEqual(tools.map(\.name), ["open_url"])
        XCTAssertEqual(tools[0].parameters, NapaxiCustomToolDefinition.defaultParameters)
        XCTAssertEqual(tools[0].effect, "external")
        XCTAssertThrowsError(try NapaxiToolAPI.toolDefinitions(from: .object(["ignored": .bool(true)])))
        XCTAssertThrowsError(try NapaxiToolAPI.toolDefinitions(from: .array([
            .object(["name": .number(1)]),
        ])))
        XCTAssertThrowsError(try NapaxiToolAPI.toolDefinitions(from: .array([
            .object(["description": .bool(true)]),
        ])))
        XCTAssertThrowsError(try NapaxiToolAPI.toolDefinitions(from: .array([
            .object(["effect": .bool(true)]),
        ])))
    }

    func testFlutterApprovalAliasesUseStructuredHostTypes() throws {
        let request = McToolApprovalRequest(
            requestId: 42,
            toolName: "open_url",
            description: "Open URL",
            parametersJson: #"{"url":"https://example.com"}"#,
            allowAlways: true
        )
        let response = McToolApprovalResponse(
            approved: true,
            always: true,
            message: "Allowed"
        )
        let handler: McToolApprovalHandler = { request in
            McToolApprovalResponse(
                approved: request.toolName == "open_url",
                always: true,
                message: "Allowed"
            )
        }
        let adapter = NapaxiToolApprovalHandlerAdapter(handler: handler)

        XCTAssertEqual(request.requestId, 42)
        XCTAssertEqual(request.toolName, "open_url")
        XCTAssertEqual(request.parametersJson, #"{"url":"https://example.com"}"#)
        XCTAssertEqual(request.parameters["url"], .string("https://example.com"))
        XCTAssertTrue(request.allowAlways)
        XCTAssertNotNil(adapter)

        let decodedResponse = try XCTUnwrap(decodeObject(response.jsonString()))
        XCTAssertEqual(decodedResponse["approved"] as? Bool, true)
        XCTAssertEqual(decodedResponse["always"] as? Bool, true)
        XCTAssertEqual(decodedResponse["message"] as? String, "Allowed")
    }

    func testApprovalRequestCodableAcceptsCoreWireAndEmitsFlutterFacadeKeys() throws {
        let coreWireJSON = """
        {
          "request_id": 42,
          "tool_name": "open_url",
          "description": "Open URL",
          "parameters": "{\\"url\\":\\"https://example.com\\"}",
          "allow_always": true
        }
        """

        let request = try JSONDecoder().decode(McToolApprovalRequest.self, from: Data(coreWireJSON.utf8))
        XCTAssertEqual(request.requestId, 42)
        XCTAssertEqual(request.toolName, "open_url")
        XCTAssertEqual(request.description, "Open URL")
        XCTAssertEqual(request.parametersJson, #"{"url":"https://example.com"}"#)
        XCTAssertEqual(request.parameters["url"], .string("https://example.com"))
        XCTAssertTrue(request.allowAlways)

        let encoded = try JSONEncoder().encode(request)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(decoded["requestId"] as? Int, 42)
        XCTAssertEqual(decoded["toolName"] as? String, "open_url")
        XCTAssertEqual(decoded["description"] as? String, "Open URL")
        XCTAssertEqual(decoded["parametersJson"] as? String, #"{"url":"https://example.com"}"#)
        XCTAssertEqual(decoded["allowAlways"] as? Bool, true)
        XCTAssertNil(decoded["parametersJSON"])
        XCTAssertNil(decoded["request_id"])
        XCTAssertNil(decoded["tool_name"])
    }
}

private func decodeObject(_ value: String) throws -> [String: Any]? {
    let decoded = try JSONSerialization.jsonObject(with: Data(value.utf8))
    return decoded as? [String: Any]
}

private func decodeArray(_ value: String) throws -> [[String: Any]]? {
    let decoded = try JSONSerialization.jsonObject(with: Data(value.utf8))
    return decoded as? [[String: Any]]
}
