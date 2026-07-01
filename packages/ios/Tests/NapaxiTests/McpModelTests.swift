import XCTest
@testable import Napaxi

final class McpModelTests: XCTestCase {
    func testMcpAPIAliasesMirrorFlutterAPISurface() {
        let addServer: (NapaxiMcpAPI, String, String) throws -> NapaxiMcpServerActionResult = { api, name, url in
            try api.addServer(name, url)
        }
        let addServerJSON: (NapaxiMcpAPI, String, String) throws -> NapaxiJSONValue = { api, name, url in
            try api.addServerJSON(name, url)
        }
        let removeServer: (NapaxiMcpAPI, String) throws -> Bool = { api, name in
            try api.removeServer(name)
        }
        let removeServerJSON: (NapaxiMcpAPI, String) throws -> NapaxiJSONValue = { api, name in
            try api.removeServerJSON(name)
        }
        let activate: (NapaxiMcpAPI, String) throws -> NapaxiMcpServerActionResult = { api, name in
            try api.activate(name)
        }
        let activateJSON: (NapaxiMcpAPI, String) throws -> NapaxiJSONValue = { api, name in
            try api.activateJSON(name)
        }
        let deactivate: (NapaxiMcpAPI, String) throws -> Bool = { api, name in
            try api.deactivate(name)
        }
        let deactivateJSON: (NapaxiMcpAPI, String) throws -> NapaxiJSONValue = { api, name in
            try api.deactivateJSON(name)
        }
        let startOAuth: (NapaxiMcpAPI, String, String, Bool?) throws -> NapaxiMcpOAuthStartResult = { api, name, redirectUri, usePkce in
            try api.startOAuth(name, redirectUri: redirectUri, usePkce: usePkce)
        }
        let startOAuthJSON: (NapaxiMcpAPI, String, String, String) throws -> NapaxiJSONValue = { api, name, redirectUri, oauthJSON in
            try api.startOAuthJSON(name, redirectUri: redirectUri, oauthJSON: oauthJSON)
        }
        let finishOAuth: (NapaxiMcpAPI, String, String, String) throws -> NapaxiMcpServerActionResult = { api, name, code, state in
            try api.finishOAuth(name, code: code, state: state)
        }
        let finishOAuthJSON: (NapaxiMcpAPI, String, String, String) throws -> NapaxiJSONValue = { api, name, code, state in
            try api.finishOAuthJSON(name, code: code, state: state)
        }
        let addServerOrError: (NapaxiMcpAPI, String, String) -> NapaxiMcpServerActionResult = { api, name, url in
            api.addServerOrError(name, url)
        }
        let removeServerOrFalse: (NapaxiMcpAPI, String) -> Bool = { api, name in
            api.removeServerOrFalse(name)
        }
        let listServersOrEmpty: (NapaxiMcpAPI) -> [NapaxiMcpServerInfo] = { api in
            api.listServersOrEmpty()
        }
        let activateOrError: (NapaxiMcpAPI, String) -> NapaxiMcpServerActionResult = { api, name in
            api.activateOrError(name)
        }
        let deactivateOrFalse: (NapaxiMcpAPI, String) -> Bool = { api, name in
            api.deactivateOrFalse(name)
        }
        let listToolsOrEmpty: (NapaxiMcpAPI, String) -> [NapaxiMcpToolInfo] = { api, serverName in
            api.listToolsOrEmpty(serverName: serverName)
        }
        let startOAuthOrError: (NapaxiMcpAPI, String, String, Bool?) -> NapaxiMcpOAuthStartResult = { api, name, redirectUri, usePkce in
            api.startOAuthOrError(name, redirectUri: redirectUri, usePkce: usePkce)
        }
        let finishOAuthOrError: (NapaxiMcpAPI, String, String, String) -> NapaxiMcpServerActionResult = { api, name, code, state in
            api.finishOAuthOrError(name, code: code, state: state)
        }

        XCTAssertNotNil(addServer)
        XCTAssertNotNil(addServerJSON)
        XCTAssertNotNil(removeServer)
        XCTAssertNotNil(removeServerJSON)
        XCTAssertNotNil(activate)
        XCTAssertNotNil(activateJSON)
        XCTAssertNotNil(deactivate)
        XCTAssertNotNil(deactivateJSON)
        XCTAssertNotNil(startOAuth)
        XCTAssertNotNil(startOAuthJSON)
        XCTAssertNotNil(finishOAuth)
        XCTAssertNotNil(finishOAuthJSON)
        XCTAssertNotNil(addServerOrError)
        XCTAssertNotNil(removeServerOrFalse)
        XCTAssertNotNil(listServersOrEmpty)
        XCTAssertNotNil(activateOrError)
        XCTAssertNotNil(deactivateOrFalse)
        XCTAssertNotNil(listToolsOrEmpty)
        XCTAssertNotNil(startOAuthOrError)
        XCTAssertNotNil(finishOAuthOrError)
    }

    func testMcpServerInfoDecodesFlutterCompatibleFieldsAndState() throws {
        let connected = try JSONDecoder().decode(
            NapaxiMcpServerInfo.self,
            from: Data(#"{"name":"github","url":"https://mcp.example","connected":true,"tools":["github.search"],"authRequired":true,"oauthConnected":true,"oauthPending":false,"transport":"streamable_http"}"#.utf8)
        )
        let pending = try JSONDecoder().decode(
            NapaxiMcpServerInfo.self,
            from: Data(#"{"name":"notion","url":"https://mcp.example","connected":false,"oauth_pending":true}"#.utf8)
        )
        let failed = try JSONDecoder().decode(
            NapaxiMcpServerInfo.self,
            from: Data(#"{"name":"bad","url":"https://mcp.example","connected":false,"error":"timeout"}"#.utf8)
        )

        XCTAssertEqual(connected.name, "github")
        XCTAssertEqual(connected.tools, ["github.search"])
        XCTAssertTrue(connected.authRequired)
        XCTAssertTrue(connected.oauthConnected)
        XCTAssertEqual(connected.transport, "streamable_http")
        XCTAssertEqual(connected.connectionState, .connected)
        XCTAssertEqual(pending.connectionState, .connecting)
        XCTAssertEqual(failed.error, "timeout")
        XCTAssertEqual(failed.connectionState, .error)
    }

    func testMcpMapHelpersMirrorFlutterFromMapFactories() throws {
        let server = McpServerInfo.fromMap([
            "name": .string("github"),
            "url": .string("https://mcp.example"),
            "connected": .bool(true),
            "tools": .array([.string("github.search")]),
            "authRequired": .bool(true),
            "oauthConnected": .bool(true),
            "oauthPending": .bool(false),
        ])
        let tool = McpToolInfo.fromMap([
            "name": .string("github.search"),
            "server_name": .string("github"),
        ])
        let action = McpServerActionResult.fromJson([
            "name": .string("github"),
            "tools_loaded": .array([.string("github.search")]),
            "message": .string("ok"),
        ])
        let oauth = McpOAuthStartResult.fromJson([
            "name": .string("github"),
            "authorization_url": .string("https://auth.example"),
            "state": .string("s1"),
            "redirect_uri": .string("napaxi://oauth/mcp"),
        ])
        let oauthFromString = try McpOAuthStartResult.fromJsonString(
            #"{"name":"github","authorization_url":"https://auth.example","state":"s1","redirect_uri":"napaxi://oauth/mcp"}"#
        )

        XCTAssertEqual(server.name, "github")
        XCTAssertEqual(server.tools, ["github.search"])
        XCTAssertTrue(server.authRequired)
        XCTAssertTrue(server.oauthConnected)
        XCTAssertEqual(server.connectionState, .connected)
        XCTAssertEqual(server.toMap()["name"], .string("github"))
        XCTAssertEqual(tool.serverName, "github")
        XCTAssertEqual(tool.toMap()["server_name"], .string("github"))
        XCTAssertEqual(action.toolsLoaded, ["github.search"])
        XCTAssertEqual(action.message, "ok")
        XCTAssertTrue(action.isSuccess)
        XCTAssertEqual(oauth.authorizationUrl, "https://auth.example")
        XCTAssertEqual(oauth.redirectUri, "napaxi://oauth/mcp")
        XCTAssertTrue(oauth.isSuccess)
        XCTAssertEqual(oauthFromString.authorizationUrl, oauth.authorizationUrl)
    }

    func testMcpToolAndActionResultDecodeFlutterCompatibleFields() throws {
        let tool = try JSONDecoder().decode(
            NapaxiMcpToolInfo.self,
            from: Data(#"{"name":"github.search","server_name":"github"}"#.utf8)
        )
        let result = try JSONDecoder().decode(
            NapaxiMcpServerActionResult.self,
            from: Data(#"{"name":"github","tools_loaded":["github.search"],"message":"ok","error":""}"#.utf8)
        )

        XCTAssertEqual(tool.name, "github.search")
        XCTAssertEqual(tool.serverName, "github")
        XCTAssertEqual(result.name, "github")
        XCTAssertEqual(result.toolsLoaded, ["github.search"])
        XCTAssertEqual(result.message, "ok")
        XCTAssertNil(result.error)
        XCTAssertTrue(result.isSuccess)
    }

    func testMcpOAuthResultDecodesFlutterCompatibleFields() throws {
        let result = try JSONDecoder().decode(
            NapaxiMcpOAuthStartResult.self,
            from: Data(#"{"name":"github","authorization_url":"https://auth.example","state":"s1","redirect_uri":"napaxi://oauth/mcp","error":""}"#.utf8)
        )

        XCTAssertEqual(result.name, "github")
        XCTAssertEqual(result.authorizationUrl, "https://auth.example")
        XCTAssertEqual(result.state, "s1")
        XCTAssertEqual(result.redirectUri, "napaxi://oauth/mcp")
        XCTAssertNil(result.error)
        XCTAssertTrue(result.isSuccess)
    }

    func testMcpTypedDecodersSurfaceFlutterFactoryErrors() throws {
        let validServer: [String: NapaxiJSONValue] = [
            "name": .string("github"),
            "url": .string("https://mcp.example"),
            "connected": .bool(true),
            "tools": .array([.string("github.search")]),
        ]
        let servers = try NapaxiMcpAPI.decodeMcpServerInfos(from: .array([
            .number(7),
            .object(validServer),
        ]))
        XCTAssertEqual(servers.map(\.name), ["github"])

        var malformedServerTools = validServer
        malformedServerTools["tools"] = .array([.string("github.search"), .number(7)])
        XCTAssertThrowsError(try NapaxiMcpAPI.decodeMcpServerInfos(from: .array([.object(malformedServerTools)])))
        XCTAssertThrowsError(try NapaxiMcpServerInfo.fromJsonString(#"{"name":"github","connected":"true"}"#))

        let validTool: [String: NapaxiJSONValue] = [
            "name": .string("github.search"),
            "serverName": .string("github"),
        ]
        let tools = try NapaxiMcpAPI.decodeMcpToolInfos(from: .array([
            .string("ignored"),
            .object(validTool),
        ]))
        XCTAssertEqual(tools.map(\.name), ["github.search"])

        var malformedTool = validTool
        malformedTool["name"] = .bool(true)
        XCTAssertThrowsError(try NapaxiMcpAPI.decodeMcpToolInfos(from: .array([.object(malformedTool)])))

        XCTAssertThrowsError(try NapaxiMcpAPI.decodeMcpServerActionResult(from: .object([
            "name": .string("github"),
            "tools_loaded": .array([.string("github.search"), .bool(true)]),
        ])))
        XCTAssertThrowsError(try NapaxiMcpAPI.decodeMcpOAuthStartResult(from: .object([
            "name": .string("github"),
            "authorization_url": .number(7),
        ])))
    }

    func testMcpAPINormalizesDefaultUserId() {
        let api = NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: 0), defaultUserId: "  ")

        XCTAssertEqual(api.defaultUserId, NapaxiEngine.defaultAccountId)
    }

    func testMcpSafeFacadeMirrorsFlutterFailureFallbacks() {
        let api = NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: 0))

        let add = api.addServerOrError("github", "https://mcp.example")
        let activate = api.activateOrError("github")
        let oauth = api.startOAuthOrError("github", redirectUri: "napaxi://oauth/mcp")
        let finish = api.finishOAuthOrError("github", code: "code", state: "state")

        XCTAssertEqual(add.name, "github")
        XCTAssertEqual(add.error?.hasPrefix("addServer failed:"), true)
        XCTAssertFalse(add.isSuccess)
        XCTAssertFalse(api.removeServerOrFalse("github"))
        XCTAssertEqual(api.listServersOrEmpty(), [])
        XCTAssertEqual(activate.error?.hasPrefix("activate failed:"), true)
        XCTAssertFalse(activate.isSuccess)
        XCTAssertEqual(oauth.name, "github")
        XCTAssertEqual(oauth.authorizationUrl, "")
        XCTAssertEqual(oauth.state, "")
        XCTAssertEqual(oauth.redirectUri, "napaxi://oauth/mcp")
        XCTAssertEqual(oauth.error?.hasPrefix("startOAuth failed:"), true)
        XCTAssertFalse(oauth.isSuccess)
        XCTAssertEqual(finish.error?.hasPrefix("finishOAuth failed:"), true)
        XCTAssertFalse(finish.isSuccess)
        XCTAssertFalse(api.deactivateOrFalse("github"))
        XCTAssertEqual(api.listToolsOrEmpty(serverName: "github"), [])
    }

    func testMcpPrimaryFacadeMirrorsFlutterFailureFallbacks() throws {
        let api = NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: 0))

        let add = try api.addServer("github", "https://mcp.example")
        let activate = try api.activate("github")
        let oauth = try api.startOAuth("github", redirectUri: "napaxi://oauth/mcp")
        let finish = try api.finishOAuth("github", code: "code", state: "state")

        XCTAssertEqual(add.name, "github")
        XCTAssertEqual(add.error?.hasPrefix("addServer failed:"), true)
        XCTAssertFalse(add.isSuccess)
        XCTAssertFalse(try api.removeServer("github"))
        XCTAssertEqual(try api.listServers(), [])
        XCTAssertEqual(activate.error?.hasPrefix("activate failed:"), true)
        XCTAssertFalse(activate.isSuccess)
        XCTAssertEqual(oauth.name, "github")
        XCTAssertEqual(oauth.authorizationUrl, "")
        XCTAssertEqual(oauth.state, "")
        XCTAssertEqual(oauth.redirectUri, "napaxi://oauth/mcp")
        XCTAssertEqual(oauth.error?.hasPrefix("startOAuth failed:"), true)
        XCTAssertFalse(oauth.isSuccess)
        XCTAssertEqual(finish.error?.hasPrefix("finishOAuth failed:"), true)
        XCTAssertFalse(finish.isSuccess)
        XCTAssertFalse(try api.deactivate("github"))
        XCTAssertEqual(try api.listTools(serverName: "github"), [])
    }
}
