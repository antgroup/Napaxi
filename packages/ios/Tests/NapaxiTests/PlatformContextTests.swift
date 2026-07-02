import XCTest
@testable import Napaxi

final class PlatformContextTests: XCTestCase {
    func testMobileCapabilityContextMirrorsFlutterPathHelpers() throws {
        let context = NapaxiMobileCapabilityContext(
            filesDir: "/tmp/napaxi_data",
            workspaceFilesDir: "/tmp/workspace_data"
        )

        XCTAssertEqual(context.workspaceDir, "/tmp/workspace_data/linux-env/workspace")
        XCTAssertEqual(context.rootfsDir, "/tmp/napaxi_data/linux-env/rootfs")
        XCTAssertEqual(context.skillsDir, "/tmp/napaxi_data/prompt_skills")
        XCTAssertEqual(
            context.attachmentSandboxPath(category: "camera", filename: "photo.jpg"),
            "/workspace/attachments/camera/photo.jpg"
        )
        XCTAssertEqual(
            context.resolveSandboxOrLocalPath("/workspace/attachments/camera/photo.jpg"),
            "/tmp/workspace_data/linux-env/workspace/attachments/camera/photo.jpg"
        )
        XCTAssertEqual(
            context.resolveSandboxOrLocalPath("/skills/demo/SKILL.md"),
            "/tmp/napaxi_data/prompt_skills/demo/SKILL.md"
        )
        XCTAssertEqual(
            context.resolveSandboxOrLocalPath("/tmp/out.txt"),
            "/tmp/napaxi_data/linux-env/rootfs/tmp/out.txt"
        )
        XCTAssertEqual(context.resolveSandboxOrLocalPath("/local/out.txt"), "/local/out.txt")

        let result = try NapaxiRawJSON(jsonString: context.attachmentResultJson(
            sandboxPath: "/workspace/attachments/camera/photo.jpg",
            kind: "image",
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 42,
            extra: ["width": .number(100)]
        )).value
        let success = try NapaxiRawJSON(jsonString: context.successJson(["ok": .bool(true)])).value
        let error = try NapaxiRawJSON(jsonString: context.errorJson("failed", includeSuccess: true)).value

        XCTAssertEqual(result, .object([
            "sandbox_path": .string("/workspace/attachments/camera/photo.jpg"),
            "file_path": .string("/workspace/attachments/camera/photo.jpg"),
            "kind": .string("image"),
            "filename": .string("photo.jpg"),
            "mime_type": .string("image/jpeg"),
            "mimeType": .string("image/jpeg"),
            "size_bytes": .number(42),
            "sizeBytes": .number(42),
            "width": .number(100),
        ]))
        XCTAssertEqual(success, .object(["ok": .bool(true)]))
        XCTAssertEqual(error, .object([
            "error": .string("failed"),
            "success": .bool(false),
        ]))
    }

    func testPlatformToolHostAliasMirrorsFlutterName() {
        let context = CapabilityContext(filesDir: "/tmp/napaxi_data", workspaceFilesDir: "/tmp/workspace_data")
        let host = FlutterCapabilityHost(filesDir: "/tmp/napaxi_data")
        let mobileHost = FlutterMobileCapabilityHost(filesDir: "/tmp/napaxi_data")
        let executor: NapaxiPlatformToolExecutor = host

        XCTAssertNotNil(executor)
        XCTAssertEqual(context.workspaceDir, "/tmp/workspace_data/linux-env/workspace")
        XCTAssertEqual(host.filesDir, "/tmp/napaxi_data")
        XCTAssertNil(host.workspaceFilesDir)
        XCTAssertEqual(mobileHost.filesDir, "/tmp/napaxi_data")
        XCTAssertTrue(host.canHandle("open_url"))
        XCTAssertFalse(host.canHandle("browser_open"))
    }

    func testPlatformToolHostExecuteMirrorsFlutterJsonFacade() async throws {
        let host = FlutterCapabilityHost(filesDir: "/tmp/napaxi_data")

        let unknown = await host.execute("browser_open", "{}")
        let unavailable = await host.execute(
            "get_device_info",
            "{}",
            workspaceFilesDir: "/tmp/workspace_data"
        )

        XCTAssertEqual(host.filesDir, "/tmp/napaxi_data")
        XCTAssertEqual(try NapaxiRawJSON(jsonString: unknown).value, .object([
            "error": .string("Unknown platform tool: browser_open"),
        ]))
        guard case .object(let unavailableObject) = try NapaxiRawJSON(jsonString: unavailable).value else {
            return XCTFail("Expected unavailable platform tool JSON object")
        }
        XCTAssertEqual(unavailableObject["error"], .string("Platform tools are only available on iOS"))
    }

    func testUnsupportedPlatformToolsShortCircuitBeforeParsingLikeFlutter() async throws {
        let context = CapabilityContext(filesDir: "/tmp/napaxi_data", workspaceFilesDir: "/tmp/workspace_data")
        let host = FlutterCapabilityHost(filesDir: "/tmp/napaxi_data")

        let alarm = await AlarmTool.execute("not-json")
        let alarmViaHost = await host.execute("set_alarm", "not-json")
        let alarmViaExecutor = try await host.executePlatformTool(name: "set_alarm", params: [:])
        let install = await InstallAppTool.execute("not-json", context: context)
        let installViaHost = await host.execute("install_apk", "not-json")
        let installViaExecutor = try await host.executePlatformTool(name: "install_apk", params: [:])

        let expectedAlarm = NapaxiJSONValue.object([
            "error": .string("Setting alarms is not supported on iOS due to system restrictions."),
        ])
        let expectedInstall = NapaxiJSONValue.object([
            "success": .bool(false),
            "error": .string("install_apk is only supported on Android."),
        ])

        XCTAssertEqual(try NapaxiRawJSON(jsonString: alarm).value, expectedAlarm)
        XCTAssertEqual(try NapaxiRawJSON(jsonString: alarmViaHost).value, expectedAlarm)
        XCTAssertEqual(alarmViaExecutor, expectedAlarm)
        XCTAssertEqual(try NapaxiRawJSON(jsonString: install).value, expectedInstall)
        XCTAssertEqual(try NapaxiRawJSON(jsonString: installViaHost).value, expectedInstall)
        XCTAssertEqual(installViaExecutor, expectedInstall)
    }

    func testPlatformToolParameterParsingMirrorsFlutterPerToolBehavior() throws {
        let setClipboard = try NapaxiDefaultPlatformToolExecutor.params(
            from: #"{"text":"hello"}"#,
            forTool: "set_clipboard"
        )
        let getClipboard = try NapaxiDefaultPlatformToolExecutor.params(
            from: "not-json",
            forTool: "get_clipboard"
        )
        let deviceInfo = try NapaxiDefaultPlatformToolExecutor.params(
            from: "[]",
            forTool: "get_device_info"
        )
        let alarm = try NapaxiDefaultPlatformToolExecutor.params(
            from: "not-json",
            forTool: "set_alarm"
        )
        let installApk = try NapaxiDefaultPlatformToolExecutor.params(
            from: "[]",
            forTool: "install_apk"
        )

        XCTAssertEqual(setClipboard["text"], .string("hello"))
        XCTAssertEqual(getClipboard, [:])
        XCTAssertEqual(deviceInfo, [:])
        XCTAssertEqual(alarm, [:])
        XCTAssertEqual(installApk, [:])
        XCTAssertEqual(
            try NapaxiDefaultPlatformToolExecutor.flutterStringParameter(["title": .string("Hi")], "title", default: "Notification"),
            "Hi"
        )
        XCTAssertEqual(
            try NapaxiDefaultPlatformToolExecutor.flutterStringParameter(["title": .null], "title", default: "Notification"),
            "Notification"
        )
        XCTAssertNil(try NapaxiDefaultPlatformToolExecutor.flutterStringParameter([:], "body"))
        XCTAssertEqual(
            try NapaxiDefaultPlatformToolExecutor.flutterIntParameter(["limit": .number(3)], "limit", default: 20),
            3
        )
        XCTAssertEqual(
            try NapaxiDefaultPlatformToolExecutor.flutterIntParameter(["limit": .null], "limit", default: 20),
            20
        )
        XCTAssertThrowsError(try NapaxiDefaultPlatformToolExecutor.params(
            from: "[]",
            forTool: "set_clipboard"
        )) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Platform tool parameters must be a JSON object"))
        }
        XCTAssertThrowsError(try NapaxiDefaultPlatformToolExecutor.params(
            from: "",
            forTool: "send_notification"
        ))
        XCTAssertThrowsError(try NapaxiDefaultPlatformToolExecutor.flutterStringParameter(["title": .number(1)], "title"))
        XCTAssertThrowsError(try NapaxiDefaultPlatformToolExecutor.flutterIntParameter(["limit": .string("3")], "limit"))
        XCTAssertThrowsError(try NapaxiDefaultPlatformToolExecutor.flutterIntParameter(["limit": .number(3.5)], "limit"))
    }

    func testPlatformToolResultShapesMirrorFlutterHelpers() {
        let clipboardRead = NapaxiDefaultPlatformToolExecutor.clipboardReadResult("hello")
        let emptyClipboardRead = NapaxiDefaultPlatformToolExecutor.clipboardReadResult(nil)
        let clipboardWrite = NapaxiDefaultPlatformToolExecutor.clipboardWriteResult("a😀")
        let deviceInfo = NapaxiDefaultPlatformToolExecutor.deviceInfoResult(
            name: "iPhone",
            model: "iPhone",
            systemName: "iOS",
            systemVersion: "18.0",
            isPhysicalDevice: false
        )
        let url = NapaxiDefaultPlatformToolExecutor.urlResult(url: "https://example.com", success: true)
        let invalidURL = NapaxiDefaultPlatformToolExecutor.invalidURLResult("")
        let missingPhone = NapaxiDefaultPlatformToolExecutor.phoneNumberRequiredResult()
        let sms = NapaxiDefaultPlatformToolExecutor.schemeResult(
            valueKey: "phone_number",
            value: "+15551234567",
            success: false
        )

        XCTAssertEqual(clipboardRead, .object([
            "text": .string("hello"),
            "has_content": .bool(true),
        ]))
        XCTAssertEqual(emptyClipboardRead, .object([
            "text": .string(""),
            "has_content": .bool(false),
        ]))
        XCTAssertEqual(clipboardWrite, .object([
            "success": .bool(true),
            "copied_length": .number(3),
        ]))
        XCTAssertEqual(deviceInfo, .object([
            "platform": .string("ios"),
            "name": .string("iPhone"),
            "model": .string("iPhone"),
            "system_name": .string("iOS"),
            "system_version": .string("18.0"),
            "is_physical_device": .bool(false),
        ]))
        XCTAssertEqual(url, .object([
            "success": .bool(true),
            "url": .string("https://example.com"),
        ]))
        XCTAssertEqual(invalidURL, .object([
            "success": .bool(false),
            "error": .string("Invalid URL: "),
        ]))
        XCTAssertEqual(missingPhone, .object([
            "success": .bool(false),
            "error": .string("phone_number is required"),
        ]))
        XCTAssertEqual(sms, .object([
            "success": .bool(false),
            "phone_number": .string("+15551234567"),
        ]))
        XCTAssertEqual(NapaxiDefaultPlatformToolExecutor.notificationPermissionDeniedResult, .object([
            "error": .string("Notification permission denied on iOS."),
        ]))
    }

    func testStandalonePlatformToolHelpersMirrorFlutterNames() async throws {
        let context = MobileCapabilityContext(filesDir: "/tmp/napaxi_data", workspaceFilesDir: "/tmp/workspace_data")
        let notificationsInitialized = await NotificationTool.ensureInit()

        let results = await [
            UrlTool.execute(#"{"url":"https://example.com"}"#),
            PhoneTool.makeCall(#"{"phone_number":"+15551234567"}"#),
            PhoneTool.sendSms(#"{"phone_number":"+15551234567","body":"hi"}"#),
            ClipboardTool.getClipboard("{}"),
            ClipboardTool.setClipboard(#"{"text":"hello"}"#),
            DeviceInfoTool.execute("{}"),
            LocationTool.execute("{}"),
            NotificationTool.execute(#"{"title":"Hi","body":"There"}"#),
            ContactsTool.execute("{}"),
            CalendarTool.createEvent(#"{"title":"Standup","start":"2026-01-01T10:00:00Z","end":"2026-01-01T10:30:00Z"}"#),
            CalendarTool.listEvents(#"{"start":"2026-01-01T00:00:00Z","end":"2026-01-02T00:00:00Z"}"#),
            CameraTool.execute("{}", context: context),
            AudioTool.execute("{}", context: context),
            AlarmTool.execute(#"{"time":"07:30"}"#),
            InstallAppTool.execute(#"{"apk_path":"/workspace/app.apk"}"#, context: context),
        ]

        XCTAssertTrue(notificationsInitialized)
        XCTAssertEqual(results.count, 15)
        for result in results {
            guard case .object(let object) = try NapaxiRawJSON(jsonString: result).value else {
                return XCTFail("Expected platform tool helper to return a JSON object")
            }
            XCTAssertNotNil(object["error"])
        }
    }

    func testPlatformToolProviderMirrorsFlutterStandaloneHelper() {
        XCTAssertEqual(PlatformToolProvider.isSupported, false)
        XCTAssertTrue(PlatformToolProvider.isPlatformTool("open_url"))
        XCTAssertTrue(PlatformToolProvider.isMobilePlatformTool("open_url"))
        XCTAssertTrue(PlatformToolProvider.isMobilePlatformTool("install_apk"))
        XCTAssertFalse(PlatformToolProvider.isPlatformTool("browser_open"))
        XCTAssertFalse(PlatformToolProvider.isMobilePlatformTool("browser_open"))

        let definitions = PlatformToolProvider.getToolDefinitions()
        XCTAssertEqual(Set(definitions.map(\.name)), PlatformToolProvider.platformToolNames)
        XCTAssertEqual(definitions.first(where: { $0.name == "get_clipboard" })?.effect, "read")
        XCTAssertEqual(definitions.first(where: { $0.name == "open_url" })?.parameters["required"], .array([.string("url")]))
    }

    func testPlatformToolDefinitionsMirrorCoreDescriptorSchemas() {
        let definitions = Dictionary(uniqueKeysWithValues: PlatformToolProvider.getToolDefinitions().map { ($0.name, $0) })

        let openURLProperties = definitions["open_url"]?.parameters["properties"]?.objectValue
        let notificationParameters = definitions["send_notification"]?.parameters
        let contactProperties = definitions["get_contacts"]?.parameters["properties"]?.objectValue
        let createCalendarParameters = definitions["create_calendar_event"]?.parameters
        let listCalendarParameters = definitions["list_calendar_events"]?.parameters
        let mediaLibraryProperties = definitions["media_library"]?.parameters["properties"]?.objectValue
        let audioProperties = definitions["record_audio"]?.parameters["properties"]?.objectValue
        let alarmParameters = definitions["set_alarm"]?.parameters
        let alarmProperties = alarmParameters?["properties"]?.objectValue
        let repeatDays = alarmProperties?["repeat_days"]?.objectValue
        let repeatItems = repeatDays?["items"]?.objectValue
        let installParameters = definitions["install_apk"]?.parameters
        let installProperties = installParameters?["properties"]?.objectValue

        XCTAssertEqual(openURLProperties?["url"]?.objectValue?["description"], .string("The URL to open"))
        XCTAssertEqual(notificationParameters?["required"], .array([.string("title"), .string("body")]))
        XCTAssertEqual(notificationParameters?["properties"]?.objectValue?["body"]?.objectValue?["description"], .string("Notification body text"))
        XCTAssertNil(notificationParameters?["properties"]?.objectValue?["message"])
        XCTAssertEqual(contactProperties?["limit"]?.objectValue?["type"], .string("integer"))
        XCTAssertEqual(createCalendarParameters?["required"], .array([.string("title"), .string("start"), .string("end")]))
        XCTAssertEqual(listCalendarParameters?["required"], .array([.string("start"), .string("end")]))
        XCTAssertEqual(mediaLibraryProperties?["action"]?.objectValue?["enum"], .array([.string("status"), .string("search"), .string("import"), .string("pick")]))
        XCTAssertEqual(mediaLibraryProperties?["limit"]?.objectValue?["type"], .string("integer"))
        XCTAssertEqual(mediaLibraryProperties?["media_types"]?.objectValue?["items"]?.objectValue?["enum"], .array([.string("image"), .string("video")]))
        XCTAssertEqual(audioProperties?["duration_seconds"]?.objectValue?["type"], .string("integer"))
        XCTAssertEqual(alarmParameters?["required"], .array([.string("time"), .string("message")]))
        XCTAssertEqual(repeatDays?["type"], .string("array"))
        XCTAssertEqual(repeatItems?["enum"], .array([
            .string("sunday"),
            .string("monday"),
            .string("tuesday"),
            .string("wednesday"),
            .string("thursday"),
            .string("friday"),
            .string("saturday"),
        ]))
        XCTAssertEqual(installParameters?["required"], .array([.string("apk_path")]))
        XCTAssertEqual(installProperties?["apk_path"]?.objectValue?["type"], .string("string"))
    }

    func testAlarmToolBuildIntentArgumentsMirrorsFlutterHelper() throws {
        let arguments = try AlarmTool.buildIntentArguments(#"{"time":"07:30","message":"Wake","repeatDays":["mon","周末","mon"]}"#)

        XCTAssertEqual(arguments["android.intent.extra.alarm.HOUR"], .number(7))
        XCTAssertEqual(arguments["android.intent.extra.alarm.MINUTES"], .number(30))
        XCTAssertEqual(arguments["android.intent.extra.alarm.MESSAGE"], .string("Wake"))
        XCTAssertEqual(arguments["android.intent.extra.alarm.SKIP_UI"], .bool(true))
        XCTAssertEqual(arguments["android.intent.extra.alarm.DAYS"], .array([.number(2), .number(1), .number(7)]))

        XCTAssertThrowsError(try AlarmTool.buildIntentArguments("[]")) { error in
            XCTAssertTrue(String(describing: error).contains("Alarm parameters must be a JSON object"))
        }
        XCTAssertThrowsError(try AlarmTool.buildIntentArguments(#"{"time":"25:00"}"#)) { error in
            XCTAssertTrue(String(describing: error).contains("Hour must be 0-23"))
        }
        XCTAssertThrowsError(try AlarmTool.buildIntentArguments(#"{"time":"07:30","repeat_days":[1.5]}"#)) { error in
            XCTAssertTrue(String(describing: error).contains("Invalid repeat day"))
        }
    }

    func testPlatformContextResolverMirrorsFlutterShape() throws {
        let profile = NapaxiCapabilityProfile(
            platform: "ios",
            supportedCapabilities: ["napaxi.tool.custom_host", "napaxi.service.automation"],
            disabledCapabilities: ["napaxi.tool.shell"]
        )
        let selection = NapaxiCapabilitySelection(
            enabledCapabilities: ["napaxi.tool.custom_host"],
            config: ["provider": .string("local")]
        )

        let context = try NapaxiPlatformContextResolver.resolve(
            filesDir: "/tmp/napaxi_data",
            platform: "ios",
            nativeLibraryDir: "/tmp/native",
            capabilityProfile: profile,
            capabilitySelection: selection
        )
        let raw = try NapaxiRawJSON(jsonString: context.platformContextJSON).value
        XCTAssertEqual(context.platformContextJson, context.platformContextJSON)
        guard case .object(let object) = raw,
              case .object(let readiness)? = object["skill_readiness"],
              case .array(let capabilities)? = readiness["capabilities"],
              case .object(let selectionObject)? = object["capability_selection"] else {
            return XCTFail("Expected platform context object")
        }

        XCTAssertEqual(context.filesDir, "/tmp/napaxi_data")
        XCTAssertEqual(object["platform"], .string("ios"))
        XCTAssertEqual(object["files_dir"], .string("/tmp/napaxi_data"))
        XCTAssertEqual(object["native_library_dir"], .string("/tmp/native"))
        XCTAssertEqual(readiness["platform"], .string("ios"))
        XCTAssertEqual(readiness["use_process_fallback"], .bool(false))
        XCTAssertEqual(capabilities, [.string("napaxi.tool.custom_host"), .string("napaxi.service.automation")])
        XCTAssertEqual(selectionObject["config"], .object(["provider": .string("local")]))
    }

    func testPlatformContextCodableUsesFlutterPropertyNames() throws {
        let context = try JSONDecoder().decode(
            NapaxiPlatformContext.self,
            from: Data(#"{"filesDir":"/tmp/napaxi_data","platformContextJson":"{\"platform\":\"ios\"}"}"#.utf8)
        )

        XCTAssertEqual(context.filesDir, "/tmp/napaxi_data")
        XCTAssertEqual(context.platformContextJSON, #"{"platform":"ios"}"#)
        XCTAssertEqual(context.platformContextJson, #"{"platform":"ios"}"#)

        let encoded = try JSONDecoder().decode(
            NapaxiJSONValue.self,
            from: JSONEncoder().encode(context)
        )
        XCTAssertEqual(encoded.objectValue?["filesDir"], .string("/tmp/napaxi_data"))
        XCTAssertEqual(encoded.objectValue?["platformContextJson"], .string(#"{"platform":"ios"}"#))
        XCTAssertNil(encoded.objectValue?["platformContextJSON"])
    }
}
