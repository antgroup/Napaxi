import XCTest
@testable import Napaxi

final class FileBridgeTests: XCTestCase {
    func testFileBridgePathConveniencesMirrorFlutterAPISurface() {
        let initFileBridge: (NapaxiFileBridge) throws -> Bool = { api in
            try api.initFileBridge()
        }
        let initFileBridgeScoped: (NapaxiFileBridge, String, String) throws -> Bool = { api, accountId, agentId in
            try api.initFileBridgeScoped(accountId: accountId, agentId: agentId)
        }
        let sandboxToReal: (NapaxiFileBridge, String) throws -> String? = { api, sandboxPath in
            try api.sandboxToReal(sandboxPath)
        }
        let sandboxToRealScoped: (NapaxiFileBridgeAPI, String, String, String) throws -> String? = { api, sandboxPath, accountId, agentId in
            try api.sandboxToRealScoped(sandboxPath, accountId: accountId, agentId: agentId)
        }
        let sandboxToRealJSON: (NapaxiFileBridge, String) throws -> NapaxiJSONValue = { api, sandboxPath in
            try api.sandboxToRealJSON(sandboxPath)
        }
        let realToSandbox: (NapaxiFileBridge, String) throws -> String? = { api, realPath in
            try api.realToSandbox(realPath)
        }
        let realToSandboxScoped: (NapaxiFileBridgeAPI, String, String, String) throws -> String? = { api, realPath, accountId, agentId in
            try api.realToSandboxScoped(realPath, accountId: accountId, agentId: agentId)
        }
        let realToSandboxJSON: (NapaxiFileBridge, String) throws -> NapaxiJSONValue = { api, realPath in
            try api.realToSandboxJSON(realPath)
        }
        let deleteSandboxFile: (NapaxiFileBridge, String) throws -> Bool = { api, sandboxPath in
            try api.deleteSandboxFile(sandboxPath)
        }
        let deleteSandboxFileScoped: (NapaxiFileBridge, String, String, String) throws -> Bool = { api, sandboxPath, accountId, agentId in
            try api.deleteSandboxFileScoped(sandboxPath, accountId: accountId, agentId: agentId)
        }
        let listWorkspaceFilesystem: (NapaxiFileBridge, String?, Bool) throws -> [WorkspaceFileInfo] = { api, subdir, recursive in
            try api.listWorkspaceFilesystem(subdir: subdir, recursive: recursive)
        }
        let listWorkspaceFilesystemScoped: (NapaxiFileBridge, String, String, String?, Bool) throws -> [WorkspaceFileInfo] = { api, accountId, agentId, subdir, recursive in
            try api.listWorkspaceFilesystemScoped(accountId: accountId, agentId: agentId, subdir: subdir, recursive: recursive)
        }
        let workspaceSize: (NapaxiFileBridge) throws -> Int = { api in
            try api.workspaceSize()
        }
        let workspaceSizeScoped: (NapaxiFileBridge, String, String) throws -> Int = { api, accountId, agentId in
            try api.workspaceSizeScoped(accountId: accountId, agentId: agentId)
        }
        let workspaceDirPath: (NapaxiFileBridgeAPI) throws -> String? = { api in
            try api.workspaceDirPath()
        }
        let workspaceDirPathScoped: (NapaxiFileBridgeAPI, String, String) throws -> String? = { api, accountId, agentId in
            try api.workspaceDirPath(accountId: accountId, agentId: agentId)
        }
        let rootfsDirPath: (NapaxiFileBridgeAPI) throws -> String? = { api in
            try api.rootfsDirPath()
        }
        let skillsDirPath: (NapaxiFileBridgeAPI) throws -> String? = { api in
            try api.skillsDirPath()
        }
        let saveGeneratedShape: (NapaxiFileBridge, String, Int, String) throws -> Bool = { api, threadId, userMsgIndex, attachmentsJson in
            try api.saveMessageAttachments(threadId: threadId, userMsgIndex: userMsgIndex, attachmentsJson: attachmentsJson)
        }
        let staticInit: (String, Int64?) throws -> Bool = { filesDir, handle in
            try NapaxiFileBridge.initFileBridge(filesDir: filesDir, handle: handle)
        }
        let requireInstance: () throws -> NapaxiFileBridge = {
            try NapaxiFileBridge.requireInstance()
        }
        let resolveFile: (NapaxiFileBridge, String) async throws -> URL? = { api, sandboxPath in
            try await api.resolveFile(sandboxPath)
        }

        _ = initFileBridge
        _ = initFileBridgeScoped
        _ = sandboxToReal
        _ = sandboxToRealScoped
        _ = sandboxToRealJSON
        _ = realToSandbox
        _ = realToSandboxScoped
        _ = realToSandboxJSON
        _ = deleteSandboxFile
        _ = deleteSandboxFileScoped
        _ = listWorkspaceFilesystem
        _ = listWorkspaceFilesystemScoped
        _ = workspaceSize
        _ = workspaceSizeScoped
        _ = workspaceDirPath
        _ = workspaceDirPathScoped
        _ = rootfsDirPath
        _ = skillsDirPath
        _ = saveGeneratedShape
        _ = staticInit
        _ = requireInstance
        _ = resolveFile
        XCTAssertTrue(true)
    }

    func testFileBridgeStaticInstanceMirrorsFlutterLifecycleState() throws {
        NapaxiFileBridgeAPI.clearInstance()
        XCTAssertFalse(NapaxiFileBridgeAPI.isInitialized)
        XCTAssertNil(NapaxiFileBridgeAPI.instance)
        XCTAssertThrowsError(try NapaxiFileBridgeAPI.requireInstance()) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("NapaxiFileBridge is not initialized"))
        }

        NapaxiFileBridgeAPI.registerInitialized(filesDir: "/tmp/napaxi", handle: 42)
        defer { NapaxiFileBridgeAPI.clearInstance() }

        XCTAssertTrue(NapaxiFileBridge.isInitialized)
        let bridge: NapaxiFileBridge = try NapaxiFileBridge.requireInstance()
        XCTAssertEqual(bridge.filesDir, "/tmp/napaxi")
        XCTAssertEqual(bridge.rawAPI.handle, 42)

        NapaxiFileBridgeAPI.clearInstance(handle: 99)
        XCTAssertTrue(NapaxiFileBridgeAPI.isInitialized)
        NapaxiFileBridgeAPI.clearInstance(handle: 42)
        XCTAssertFalse(NapaxiFileBridgeAPI.isInitialized)
    }

    func testEngineFileBridgeInitializationIsBestEffortLikeFlutterCreate() {
        NapaxiFileBridgeAPI.clearInstance()
        defer { NapaxiFileBridgeAPI.clearInstance() }

        let falseResult = NapaxiEngine.initializeFileBridgeBestEffort(
            handle: 42,
            filesDir: "/tmp/napaxi"
        ) {
            false
        }
        XCTAssertFalse(falseResult)
        XCTAssertFalse(NapaxiFileBridgeAPI.isInitialized)

        let throwingResult = NapaxiEngine.initializeFileBridgeBestEffort(
            handle: 42,
            filesDir: "/tmp/napaxi"
        ) {
            throw NapaxiError.invalidState("file bridge unavailable")
        }
        XCTAssertFalse(throwingResult)
        XCTAssertFalse(NapaxiFileBridgeAPI.isInitialized)

        let trueResult = NapaxiEngine.initializeFileBridgeBestEffort(
            handle: 42,
            filesDir: "/tmp/napaxi"
        ) {
            true
        }
        XCTAssertTrue(trueResult)
        XCTAssertTrue(NapaxiFileBridgeAPI.isInitialized)
        XCTAssertEqual(NapaxiFileBridgeAPI.instance?.filesDir, "/tmp/napaxi")
    }

    func testResolvedFileMapHelpersMirrorFlutterModel() {
        let file = ResolvedFile.fromMap([
            "sandbox_path": .string("/workspace/out.png"),
            "real_path": .string("/tmp/out.png"),
            "filename": .string("out.png"),
            "mime_type": .string("image/png"),
            "is_image": .bool(true),
            "is_directory": .bool(false),
            "exists": .bool(true),
            "size_bytes": .number(123),
        ])

        XCTAssertEqual(file.sandboxPath, "/workspace/out.png")
        XCTAssertEqual(file.realPath, "/tmp/out.png")
        XCTAssertEqual(file.filename, "out.png")
        XCTAssertEqual(file.mimeType, "image/png")
        XCTAssertTrue(file.isImage)
        XCTAssertFalse(file.isDirectory)
        XCTAssertTrue(file.exists)
        XCTAssertEqual(file.sizeBytes, 123)
        XCTAssertEqual(file.toMap(), [
            "sandbox_path": .string("/workspace/out.png"),
            "real_path": .string("/tmp/out.png"),
            "filename": .string("out.png"),
            "mime_type": .string("image/png"),
            "is_image": .bool(true),
            "is_directory": .bool(false),
            "exists": .bool(true),
            "size_bytes": .number(123),
        ])
        XCTAssertEqual(NapaxiResolvedFile(raw: .object(file.toMap())), file)
    }

    func testWorkspaceFileInfoMapHelpersMirrorFlutterModel() {
        let file = WorkspaceFileInfo.fromMap([
            "name": .string("notes.txt"),
            "sandbox_path": .string("/workspace/notes.txt"),
            "real_path": .string("/tmp/notes.txt"),
            "mime_type": .string("text/plain"),
            "is_directory": .bool(false),
            "size_bytes": .number(42),
            "modified": .number(1_700_000_000_000),
        ])

        XCTAssertEqual(file.name, "notes.txt")
        XCTAssertEqual(file.sandboxPath, "/workspace/notes.txt")
        XCTAssertEqual(file.realPath, "/tmp/notes.txt")
        XCTAssertEqual(file.mimeType, "text/plain")
        XCTAssertFalse(file.isDirectory)
        XCTAssertEqual(file.sizeBytes, 42)
        XCTAssertEqual(file.modified.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(file.toMap(), [
            "name": .string("notes.txt"),
            "sandbox_path": .string("/workspace/notes.txt"),
            "real_path": .string("/tmp/notes.txt"),
            "mime_type": .string("text/plain"),
            "is_directory": .bool(false),
            "size_bytes": .number(42),
            "modified": .number(1_700_000_000_000),
        ])
        XCTAssertEqual(NapaxiWorkspaceFileInfo(raw: .object(file.toMap())), file)
    }

    func testFileBridgeCodableUsesFlutterWireShape() throws {
        let resolved = try JSONDecoder().decode(
            NapaxiResolvedFile.self,
            from: Data(#"{"sandbox_path":"/workspace/out.png","real_path":"/tmp/out.png","filename":"out.png","mime_type":"image/png","is_image":true,"is_directory":false,"exists":true,"size_bytes":123}"#.utf8)
        )
        let workspaceFile = try JSONDecoder().decode(
            NapaxiWorkspaceFileInfo.self,
            from: Data(#"{"name":"notes.txt","sandbox_path":"/workspace/notes.txt","real_path":"/tmp/notes.txt","mime_type":"text/plain","is_directory":false,"size_bytes":42,"modified":1700000000000}"#.utf8)
        )

        XCTAssertEqual(resolved.sandboxPath, "/workspace/out.png")
        XCTAssertEqual(resolved.mimeType, "image/png")
        XCTAssertEqual(workspaceFile.sandboxPath, "/workspace/notes.txt")
        XCTAssertEqual(workspaceFile.modified.timeIntervalSince1970, 1_700_000_000)

        let encodedResolved = try JSONDecoder().decode(
            NapaxiJSONValue.self,
            from: JSONEncoder().encode(resolved)
        )
        let encodedWorkspaceFile = try JSONDecoder().decode(
            NapaxiJSONValue.self,
            from: JSONEncoder().encode(workspaceFile)
        )

        XCTAssertEqual(encodedResolved.objectValue?["sandbox_path"], .string("/workspace/out.png"))
        XCTAssertNil(encodedResolved.objectValue?["sandboxPath"])
        XCTAssertEqual(encodedResolved.objectValue?["mime_type"], .string("image/png"))
        XCTAssertEqual(encodedWorkspaceFile.objectValue?["sandbox_path"], .string("/workspace/notes.txt"))
        XCTAssertNil(encodedWorkspaceFile.objectValue?["sandboxPath"])
        XCTAssertEqual(encodedWorkspaceFile.objectValue?["modified"], .number(1_700_000_000_000))
    }

    func testFileBridgeListDecodersMirrorFlutterJsonObjectList() throws {
        let resolved = try NapaxiFileBridgeAPI.decodeResolvedFiles(from: .array([
            .object([
                "sandbox_path": .string("/workspace/out.png"),
                "filename": .string("out.png"),
                "exists": .bool(true),
            ]),
            .number(7),
            .object([
                "sandbox_path": .string("/workspace/notes.txt"),
                "filename": .string("notes.txt"),
            ]),
        ]))

        XCTAssertEqual(resolved.map(\.sandboxPath), ["/workspace/out.png", "/workspace/notes.txt"])
        XCTAssertEqual(resolved.map(\.filename), ["out.png", "notes.txt"])

        let workspaceFiles = try NapaxiFileBridgeAPI.decodeWorkspaceFileInfos(from: .array([
            .object([
                "name": .string("notes.txt"),
                "sandbox_path": .string("/workspace/notes.txt"),
                "modified": .number(1_700_000_000_000),
            ]),
            .string("skip-me"),
        ]))

        XCTAssertEqual(workspaceFiles.map(\.name), ["notes.txt"])
        XCTAssertEqual(workspaceFiles.first?.modified.timeIntervalSince1970, 1_700_000_000)
    }

    func testFileBridgeListDecodersRejectNonArrayLikeFlutterJsonObjectList() {
        XCTAssertThrowsError(try NapaxiFileBridgeAPI.decodeResolvedFiles(from: .object(["error": .string("nope")]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected a JSON array"))
        }
        XCTAssertThrowsError(try NapaxiFileBridgeAPI.decodeWorkspaceFileInfos(from: .object(["error": .string("nope")]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected a JSON array"))
        }
    }

    func testScopedListInitializesBeforeListingLikeFlutter() throws {
        var calls: [String] = []

        let files = try NapaxiFileBridgeAPI.listFilesScopedAfterInit(
            initScoped: {
                calls.append("init_scoped")
            },
            listScopedJSON: {
                calls.append("list_workspace_filesystem_scoped")
                return .array([
                    .object([
                        "name": .string("notes.txt"),
                        "sandbox_path": .string("/workspace/notes.txt"),
                    ]),
                ])
            }
        )

        XCTAssertEqual(calls, ["init_scoped", "list_workspace_filesystem_scoped"])
        XCTAssertEqual(files.map(\.name), ["notes.txt"])
    }

    func testChatAttachmentEncodesFlutterCompatibleMetadata() throws {
        let attachments = [
            NapaxiChatAttachment(
                kind: "image",
                mimeType: "image/png",
                filename: "out.png",
                sandboxPath: "/workspace/out.png"
            ),
            NapaxiChatAttachment(
                kind: "document",
                mimeType: "text/plain",
                filename: "notes.txt",
                localPath: "/tmp/notes.txt"
            ),
        ]

        let raw = try NapaxiRawJSON(jsonString: NapaxiChatAttachment.jsonString(for: attachments)).value

        XCTAssertEqual(raw, .array([
            .object([
                "kind": .string("image"),
                "mime_type": .string("image/png"),
                "filename": .string("out.png"),
                "sandbox_path": .string("/workspace/out.png"),
            ]),
            .object([
                "kind": .string("document"),
                "mime_type": .string("text/plain"),
                "filename": .string("notes.txt"),
                "path": .string("/tmp/notes.txt"),
            ]),
        ]))
    }

    func testFileBridgeThreadAttachmentMapDecodesCoreShape() throws {
        let raw: NapaxiJSONValue = .object([
            "0": .array([
                .object([
                    "kind": .string("image"),
                    "mime_type": .string("image/jpeg"),
                    "sandbox_path": .string("/workspace/photo.jpg"),
                ]),
            ]),
            "2": .array([
                .object([
                    "kind": .string("document"),
                    "mime_type": .string("text/plain"),
                    "path": .string("/tmp/notes.txt"),
                ]),
            ]),
            "not-an-index": .array([]),
        ])

        let decoded = try NapaxiFileBridgeAPI.threadAttachments(from: raw)

        XCTAssertEqual(decoded[0]?.first?.sandboxPath, "/workspace/photo.jpg")
        XCTAssertEqual(decoded[2]?.first?.localPath, "/tmp/notes.txt")
        XCTAssertNil(decoded[-1])
        XCTAssertEqual(decoded.keys.sorted(), [0, 2])
    }

    func testSaveMessageAttachmentsReturnsTrueForEmptyListLikeFlutter() throws {
        let api = NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: 0))

        XCTAssertTrue(try api.saveMessageAttachments(
            threadId: "thread-a",
            userMessageIndex: 0,
            attachments: []
        ))
    }

    func testOpenLocalFileIsExplicitlyUnsupportedOnIOS() async {
        let result = await NapaxiFileBridgeAPI.openLocalFile("/tmp/out.png", mimeType: "image/png")

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Opening local files is only implemented on Android.")
        XCTAssertNil(result.code)
        XCTAssertEqual(result.jsonValue(), .object([
            "success": .bool(false),
            "error": .string("Opening local files is only implemented on Android."),
        ]))
    }
}
