import XCTest
@testable import Napaxi

final class JSONValueTests: XCTestCase {
    func testJsonCodecHelpersMirrorFlutterApi() throws {
        let object = try decodeJsonObject(#"{"name":"napaxi","count":2}"#)
        XCTAssertEqual(object["name"], .string("napaxi"))
        XCTAssertEqual(object["count"], .number(2))

        let array = try decodeJsonArray(#"[{"id":"a"},7,{"id":"b"}]"#)
        XCTAssertEqual(array.count, 3)
        XCTAssertEqual(asJsonObject(array.first), ["id": .string("a")])
        XCTAssertNil(asJsonObject(.string("nope")))
        XCTAssertEqual(asJsonArray(.array([.string("x")])), [.string("x")])

        let ids = try decodeJsonObjectList(#"[{"id":"a"},7,{"id":"b"}]"#) { object in
            object["id"]?.stringValue ?? ""
        }
        XCTAssertEqual(ids, ["a", "b"])

        let tools = try NapaxiJSONValue.array([
            .object([
                "name": .string("open_url"),
                "description": .string("Open a URL"),
                "effect": .string("external"),
            ]),
            .number(7),
            .string("ignored"),
            .object(["name": .string("share")]),
        ]).decodedObjectList(of: NapaxiCustomToolDefinition.self)
        XCTAssertEqual(tools.map(\.name), ["open_url", "share"])
        XCTAssertEqual(tools.first?.effect, "external")
        XCTAssertEqual(tools.last?.description, "")
    }

    func testJsonCodecErrorsMirrorFlutterHelpers() throws {
        let decoded = try decodeJsonValue(#"{"error":{"message":"missing"}}"#)
        XCTAssertEqual(jsonErrorMessage(decoded), "{message: missing}")
        XCTAssertNoThrow(try throwIfJsonError(.object(["ok": .bool(true)])))
        XCTAssertThrowsError(try throwIfJsonError(decoded)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("{message: missing}"))
        }

        let listError = try decodeJsonValue(#"{"error":["denied",1,{"retry":false}]}"#)
        XCTAssertEqual(jsonErrorMessage(listError), "[denied, 1, {retry: false}]")

        XCTAssertThrowsError(try decodeJsonObject("[1,2]")) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected a JSON object"))
        }
        XCTAssertThrowsError(try decodeJsonArray(#"{"items":[]}"#)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected a JSON array"))
        }
        XCTAssertThrowsError(try decodeJsonObjectListFromValue(.object([:])) { $0 }) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected a JSON array"))
        }
        XCTAssertThrowsError(try NapaxiJSONValue.object([:]).decodedObjectList(of: NapaxiCustomToolDefinition.self)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected a JSON array"))
        }
    }
}
