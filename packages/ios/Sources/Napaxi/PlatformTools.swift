import Foundation

#if os(iOS)
import AVFoundation
import Contacts
import CoreLocation
import EventKit
import UIKit
import UserNotifications
#endif

public struct NapaxiMobileCapabilityContext: Equatable, Sendable {
    public var filesDir: String?
    public var workspaceFilesDir: String?

    public init(filesDir: String?, workspaceFilesDir: String?) {
        self.filesDir = filesDir
        self.workspaceFilesDir = workspaceFilesDir
    }

    public var workspaceDir: String? {
        let base = workspaceFilesDir?.isEmpty == false ? workspaceFilesDir : filesDir
        guard let base, !base.isEmpty else { return nil }
        return "\(base)/linux-env/workspace"
    }

    public var rootfsDir: String? {
        guard let filesDir, !filesDir.isEmpty else { return nil }
        return "\(filesDir)/linux-env/rootfs"
    }

    public var skillsDir: String? {
        guard let filesDir, !filesDir.isEmpty else { return nil }
        return "\(filesDir)/prompt_skills"
    }

    public func ensureAttachmentDir(_ category: String) throws -> URL? {
        guard let workspaceDir else { return nil }
        let url = URL(fileURLWithPath: workspaceDir)
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(category, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func attachmentSandboxPath(category: String, filename: String) -> String {
        "/workspace/attachments/\(category)/\(filename)"
    }

    public func attachmentResultJSON(
        sandboxPath: String,
        kind: String,
        filename: String,
        mimeType: String,
        sizeBytes: Int,
        extra: [String: NapaxiJSONValue] = [:]
    ) throws -> String {
        var object: [String: NapaxiJSONValue] = [
            "sandbox_path": .string(sandboxPath),
            "file_path": .string(sandboxPath),
            "kind": .string(kind),
            "filename": .string(filename),
            "mime_type": .string(mimeType),
            "mimeType": .string(mimeType),
            "size_bytes": .number(Double(sizeBytes)),
            "sizeBytes": .number(Double(sizeBytes)),
        ]
        for (key, value) in extra {
            object[key] = value
        }
        return try successJSON(object)
    }

    public func attachmentResultJson(
        sandboxPath: String,
        kind: String,
        filename: String,
        mimeType: String,
        sizeBytes: Int,
        extra: [String: NapaxiJSONValue] = [:]
    ) throws -> String {
        try attachmentResultJSON(
            sandboxPath: sandboxPath,
            kind: kind,
            filename: filename,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            extra: extra
        )
    }

    public func successJSON(_ value: [String: NapaxiJSONValue]) throws -> String {
        try value.jsonString()
    }

    public func successJson(_ value: [String: NapaxiJSONValue]) throws -> String {
        try successJSON(value)
    }

    public func errorJSON(_ message: String, includeSuccess: Bool = false) throws -> String {
        var object: [String: NapaxiJSONValue] = ["error": .string(message)]
        if includeSuccess {
            object["success"] = .bool(false)
        }
        return try object.jsonString()
    }

    public func errorJson(_ message: String, includeSuccess: Bool = false) throws -> String {
        try errorJSON(message, includeSuccess: includeSuccess)
    }

    public func resolveSandboxOrLocalPath(_ path: String) -> String {
        if path == "/workspace", let workspaceDir {
            return workspaceDir
        }
        if path.hasPrefix("/workspace/"), let workspaceDir {
            return "\(workspaceDir)/\(String(path.dropFirst("/workspace/".count)))"
        }
        if path == "/skills", let skillsDir {
            return skillsDir
        }
        if path.hasPrefix("/skills/"), let skillsDir {
            return "\(skillsDir)/\(String(path.dropFirst("/skills/".count)))"
        }
        if let rootfsDir,
           Self.rootfsPrefixes.contains(where: { path == $0 || path.hasPrefix("\($0)/") }) {
            return "\(rootfsDir)/\(String(path.dropFirst()))"
        }
        return path
    }

    private static let rootfsPrefixes = [
        "/tmp",
        "/root",
        "/home",
        "/var",
        "/usr",
        "/opt",
        "/etc",
        "/srv",
        "/run",
    ]
}

public typealias MobileCapabilityContext = NapaxiMobileCapabilityContext
public typealias CapabilityContext = NapaxiMobileCapabilityContext

public enum NapaxiPlatformToolProvider {
    public static var isSupported: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    public static let platformToolNames: Set<String> = [
        "open_url",
        "make_call",
        "send_sms",
        "get_clipboard",
        "set_clipboard",
        "get_device_info",
        "get_location",
        "send_notification",
        "get_contacts",
        "create_calendar_event",
        "list_calendar_events",
        "take_photo",
        "media_library",
        "record_audio",
        "set_alarm",
        "install_apk",
    ]

    public static func isMobilePlatformTool(_ name: String) -> Bool {
        platformToolNames.contains(name)
    }

    public static func isPlatformTool(_ name: String) -> Bool {
        isMobilePlatformTool(name)
    }

    public static func getToolDefinitions() -> [NapaxiCustomToolDefinition] {
        toolDefinitions
    }

    private static let emptyParameters: [String: NapaxiJSONValue] = [
        "type": .string("object"),
        "properties": .object([:]),
    ]

    private static func stringParameter(_ description: String) -> NapaxiJSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func integerParameter(_ description: String) -> NapaxiJSONValue {
        .object(["type": .string("integer"), "description": .string(description)])
    }

    private static let toolDefinitions: [NapaxiCustomToolDefinition] = [
        NapaxiCustomToolDefinition(
            name: "open_url",
            description: "Open a URL in the device's default browser or app.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "url": stringParameter("The URL to open"),
                ]),
                "required": .array([.string("url")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(
            name: "make_call",
            description: "Open the phone dialer with a pre-filled number. The user must confirm to dial.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "phone_number": stringParameter("Phone number to call"),
                ]),
                "required": .array([.string("phone_number")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(
            name: "send_sms",
            description: "Open the SMS app with a pre-filled recipient and optional message body.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "phone_number": stringParameter("Phone number to send SMS to"),
                    "body": stringParameter("Pre-filled message body (optional)"),
                ]),
                "required": .array([.string("phone_number")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(name: "get_clipboard", description: "Read the current text content from the device clipboard.", parameters: emptyParameters, effect: "read"),
        NapaxiCustomToolDefinition(
            name: "set_clipboard",
            description: "Copy text to the device clipboard.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "text": stringParameter("Text to copy to clipboard"),
                ]),
                "required": .array([.string("text")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(name: "get_device_info", description: "Get device hardware and OS information (brand, model, OS version, etc.).", parameters: emptyParameters, effect: "read"),
        NapaxiCustomToolDefinition(name: "get_location", description: "Get the device's current GPS location (latitude, longitude, altitude, accuracy). Requests location permission if not yet granted.", parameters: emptyParameters, effect: "read"),
        NapaxiCustomToolDefinition(
            name: "send_notification",
            description: "Send a local notification to the device. Requests notification permission if not yet granted.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "title": stringParameter("Notification title"),
                    "body": stringParameter("Notification body text"),
                ]),
                "required": .array([.string("title"), .string("body")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(
            name: "get_contacts",
            description: "Search or list contacts from the device address book. Requests contacts permission if not yet granted.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "query": stringParameter("Search keyword to filter contacts by name (optional)"),
                    "limit": integerParameter("Maximum number of contacts to return (default 20)"),
                ]),
            ],
            effect: "read"
        ),
        NapaxiCustomToolDefinition(
            name: "create_calendar_event",
            description: "Create a new event in the device calendar. Requests calendar permission if not yet granted.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "title": stringParameter("Event title"),
                    "start": stringParameter("Start time in ISO 8601 format (e.g. 2026-04-28T10:00:00)"),
                    "end": stringParameter("End time in ISO 8601 format (e.g. 2026-04-28T11:00:00)"),
                    "description": stringParameter("Event description (optional)"),
                ]),
                "required": .array([.string("title"), .string("start"), .string("end")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(
            name: "list_calendar_events",
            description: "List events from the device calendar within a date range. Requests calendar permission if not yet granted.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "start": stringParameter("Start date in ISO 8601 format (e.g. 2026-04-28)"),
                    "end": stringParameter("End date in ISO 8601 format (e.g. 2026-04-29)"),
                ]),
                "required": .array([.string("start"), .string("end")]),
            ],
            effect: "read"
        ),
        NapaxiCustomToolDefinition(name: "take_photo", description: "Open the device camera to take a photo. Returns the saved photo path in the sandbox.", parameters: emptyParameters, effect: "external"),
        NapaxiCustomToolDefinition(
            name: "media_library",
            description: "Access the device media library with explicit user or host authorization. Use status to inspect permission, search to list authorized media metadata, import to copy selected assets into sandbox artifacts, or pick as a manual picker fallback.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("Media library operation to perform."),
                        "enum": .array([.string("status"), .string("search"), .string("import"), .string("pick")]),
                    ]),
                    "media_types": .object([
                        "type": .string("array"),
                        "description": .string("Optional media types to include. Defaults to images."),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array([.string("image"), .string("video")]),
                        ]),
                    ]),
                    "start_ms": integerParameter("Optional inclusive creation timestamp lower bound in Unix milliseconds."),
                    "end_ms": integerParameter("Optional exclusive creation timestamp upper bound in Unix milliseconds."),
                    "limit": integerParameter("Maximum number of media items. Default 20 for search/import and 9 for pick. Max 50."),
                    "asset_ids": .object([
                        "type": .string("array"),
                        "description": .string("Asset identifiers returned by search to import."),
                        "items": .object(["type": .string("string")]),
                    ]),
                    "request_permission": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the host may show a system permission prompt if needed. Default true for search/import."),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(
            name: "record_audio",
            description: "Record audio from the device microphone for a specified duration. Requests microphone permission if not yet granted.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "duration_seconds": integerParameter("Recording duration in seconds (default 10, max 60)"),
                ]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(
            name: "set_alarm",
            description: "Schedule an alarm notification at a specified time. Uses the device notification system.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "time": stringParameter(#"Alarm time in HH:mm format (e.g. "07:30") or ISO 8601"#),
                    "message": stringParameter("Alarm message"),
                    "repeat_days": .object([
                        "type": .string("array"),
                        "description": .string("Optional weekdays for a repeating alarm. Omit for a one-time alarm. Use lowercase weekday names such as monday, tuesday, or all seven days for daily."),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("sunday"),
                                .string("monday"),
                                .string("tuesday"),
                                .string("wednesday"),
                                .string("thursday"),
                                .string("friday"),
                                .string("saturday"),
                            ]),
                        ]),
                    ]),
                ]),
                "required": .array([.string("time"), .string("message")]),
            ],
            effect: "external"
        ),
        NapaxiCustomToolDefinition(
            name: "install_apk",
            description: "Install an Android APK from a sandbox or local file path. If installing unknown apps is not allowed yet, opens the Android permission screen first. The user must confirm the installation in the system package installer.",
            parameters: [
                "type": .string("object"),
                "properties": .object([
                    "apk_path": stringParameter("APK file path. Prefer sandbox paths such as /workspace/app.apk; absolute local paths are also accepted."),
                ]),
                "required": .array([.string("apk_path")]),
            ],
            effect: "external"
        ),
    ]
}

public typealias PlatformToolProvider = NapaxiPlatformToolProvider

public protocol NapaxiPlatformToolExecutor: AnyObject {
    func executePlatformTool(name: String, params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue
}

public final class NapaxiDefaultPlatformToolExecutor: NapaxiPlatformToolExecutor {
    public let filesDir: String?
    public let workspaceFilesDir: String?

    #if os(iOS)
    private let locationProvider = NapaxiLocationProvider()
    private let contactStore = CNContactStore()
    private let eventStore = EKEventStore()
    #endif

    public init(filesDir: String? = nil, workspaceFilesDir: String? = nil) {
        self.filesDir = filesDir
        self.workspaceFilesDir = workspaceFilesDir
    }

    public func canHandle(_ toolName: String) -> Bool {
        NapaxiPlatformToolProvider.isMobilePlatformTool(toolName)
    }

    public func execute(
        _ toolName: String,
        _ paramsJSON: String,
        workspaceFilesDir: String? = nil
    ) async -> String {
        guard canHandle(toolName) else {
            return (try? ["error": NapaxiJSONValue.string("Unknown platform tool: \(toolName)")].jsonString())
                ?? #"{"error":"Unknown platform tool"}"#
        }
        if let unsupported = Self.unsupportedPlatformResult(for: toolName) {
            return (try? unsupported.napaxiJSONString())
                ?? #"{"error":"Platform tool is not supported"}"#
        }
        do {
            let executor = workspaceFilesDir == nil
                ? self
                : NapaxiDefaultPlatformToolExecutor(filesDir: filesDir, workspaceFilesDir: workspaceFilesDir)
            return try await executor.executePlatformTool(
                name: toolName,
                params: Self.params(from: paramsJSON, forTool: toolName)
            ).napaxiJSONString()
        } catch {
            return (try? ["error": NapaxiJSONValue.string(error.localizedDescription)].jsonString())
                ?? #"{"error":"Platform tool failed"}"#
        }
    }

    public func executePlatformTool(name: String, params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        if let unsupported = Self.unsupportedPlatformResult(for: name) {
            return unsupported
        }
        #if os(iOS)
        switch name {
        case "open_url":
            return try await openURL(params)
        case "make_call":
            return try await openScheme(prefix: "tel", valueKey: "phone_number", params: params)
        case "send_sms":
            return try await openScheme(
                prefix: "sms",
                valueKey: "phone_number",
                body: Self.flutterStringParameter(params, "body"),
                params: params
            )
        case "get_clipboard":
            return Self.clipboardReadResult(UIPasteboard.general.string)
        case "set_clipboard":
            let text = try Self.flutterStringParameter(params, "text", default: "") ?? ""
            UIPasteboard.general.string = text
            return Self.clipboardWriteResult(text)
        case "get_device_info":
            return await deviceInfo()
        case "get_location":
            return try await getLocation()
        case "send_notification":
            return try await sendNotification(params)
        case "get_contacts":
            return try await getContacts(params)
        case "create_calendar_event":
            return try await createCalendarEvent(params)
        case "list_calendar_events":
            return try await listCalendarEvents(params)
        case "take_photo":
            return try await takePhoto()
        case "media_library":
            return Self.unsupportedMediaLibraryResult
        case "record_audio":
            return try await recordAudio(params)
        case "set_alarm":
            return Self.unsupportedAlarmResult
        case "install_apk":
            return Self.unsupportedInstallApkResult
        default:
            throw NapaxiError.unavailable("Platform tool \(name) needs host implementation on iOS")
        }
        #else
        throw NapaxiError.unavailable("Platform tools are only available on iOS")
        #endif
    }

    private static func unsupportedPlatformResult(for toolName: String) -> NapaxiJSONValue? {
        switch toolName {
        case "set_alarm":
            return unsupportedAlarmResult
        case "media_library":
            return unsupportedMediaLibraryResult
        case "install_apk":
            return unsupportedInstallApkResult
        default:
            return nil
        }
    }

    private static var unsupportedAlarmResult: NapaxiJSONValue {
        .object(["error": .string("Setting alarms is not supported on iOS due to system restrictions.")])
    }

    private static var unsupportedInstallApkResult: NapaxiJSONValue {
        .object([
            "success": .bool(false),
            "error": .string("install_apk is only supported on Android."),
        ])
    }

    private static var unsupportedMediaLibraryResult: NapaxiJSONValue {
        .object([
            "success": .bool(false),
            "error": .string("media_library requires a host media library implementation on iOS."),
        ])
    }

    static func clipboardReadResult(_ text: String?) -> NapaxiJSONValue {
        let value = text ?? ""
        return .object([
            "text": .string(value),
            "has_content": .bool(!value.isEmpty),
        ])
    }

    static func clipboardWriteResult(_ text: String) -> NapaxiJSONValue {
        .object([
            "success": .bool(true),
            "copied_length": .number(Double(text.utf16.count)),
        ])
    }

    static func deviceInfoResult(
        name: String,
        model: String,
        systemName: String,
        systemVersion: String,
        isPhysicalDevice: Bool
    ) -> NapaxiJSONValue {
        .object([
            "platform": .string("ios"),
            "name": .string(name),
            "model": .string(model),
            "system_name": .string(systemName),
            "system_version": .string(systemVersion),
            "is_physical_device": .bool(isPhysicalDevice),
        ])
    }

    static func urlResult(url: String, success: Bool) -> NapaxiJSONValue {
        .object([
            "success": .bool(success),
            "url": .string(url),
        ])
    }

    static func invalidURLResult(_ value: String) -> NapaxiJSONValue {
        .object([
            "success": .bool(false),
            "error": .string("Invalid URL: \(value)"),
        ])
    }

    static func phoneNumberRequiredResult() -> NapaxiJSONValue {
        .object([
            "success": .bool(false),
            "error": .string("phone_number is required"),
        ])
    }

    static func schemeResult(valueKey: String, value: String, success: Bool) -> NapaxiJSONValue {
        .object([
            "success": .bool(success),
            valueKey: .string(value),
        ])
    }

    static var notificationPermissionDeniedResult: NapaxiJSONValue {
        .object(["error": .string("Notification permission denied on iOS.")])
    }

    static func flutterStringParameter(
        _ params: [String: NapaxiJSONValue],
        _ key: String,
        default defaultValue: String? = nil
    ) throws -> String? {
        guard let value = params[key], value != .null else {
            return defaultValue
        }
        guard case .string(let string) = value else {
            throw NapaxiError.invalidJSON("Platform tool parameter '\(key)' must be a string")
        }
        return string
    }

    static func flutterIntParameter(
        _ params: [String: NapaxiJSONValue],
        _ key: String,
        default defaultValue: Int? = nil
    ) throws -> Int? {
        guard let value = params[key], value != .null else {
            return defaultValue
        }
        guard case .number(let number) = value, number.isFinite else {
            throw NapaxiError.invalidJSON("Platform tool parameter '\(key)' must be an integer")
        }
        let integer = number.rounded(.towardZero)
        guard integer == number, let intValue = Int(exactly: integer) else {
            throw NapaxiError.invalidJSON("Platform tool parameter '\(key)' must be an integer")
        }
        return intValue
    }

    #if os(iOS)
    @MainActor
    private func openURL(_ params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        let raw = try Self.flutterStringParameter(params, "url", default: "") ?? ""
        guard let url = URL(string: raw) else {
            return Self.invalidURLResult(raw)
        }
        let success = await UIApplication.shared.open(url)
        return Self.urlResult(url: raw, success: success)
    }

    @MainActor
    private func openScheme(prefix: String, valueKey: String, params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        let value = try Self.flutterStringParameter(params, valueKey, default: "") ?? ""
        guard !value.isEmpty else {
            return Self.phoneNumberRequiredResult()
        }
        guard let url = URL(string: "\(prefix):\(value)") else {
            return Self.phoneNumberRequiredResult()
        }
        let success = await UIApplication.shared.open(url)
        return Self.schemeResult(valueKey: valueKey, value: value, success: success)
    }

    @MainActor
    private func openScheme(prefix: String, valueKey: String, body: String?, params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        let value = try Self.flutterStringParameter(params, valueKey, default: "") ?? ""
        guard !value.isEmpty else {
            return Self.phoneNumberRequiredResult()
        }
        var components = URLComponents()
        components.scheme = prefix
        components.path = value
        if let body, !body.isEmpty {
            components.queryItems = [URLQueryItem(name: "body", value: body)]
        }
        guard let url = components.url else {
            throw NapaxiError.invalidState("Invalid \(prefix) handoff URL")
        }
        let success = await UIApplication.shared.open(url)
        return Self.schemeResult(valueKey: valueKey, value: value, success: success)
    }

    private func sendNotification(_ params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        let title = try Self.flutterStringParameter(params, "title", default: "Notification") ?? "Notification"
        let body = try Self.flutterStringParameter(params, "body", default: "") ?? ""
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else {
            return Self.notificationPermissionDeniedResult
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let id = String(Int(Date().timeIntervalSince1970 * 1000) % 100000)
        let request = UNNotificationRequest(
            identifier: "napaxi.platform.notification.\(id)",
            content: content,
            trigger: nil
        )
        try await center.add(request)
        return .object(["success": .bool(true), "notification_id": .number(Double(id) ?? 0)])
    }

    @MainActor
    private func deviceInfo() -> NapaxiJSONValue {
        let device = UIDevice.current
        return Self.deviceInfoResult(
            name: device.name,
            model: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            isPhysicalDevice: Self.isPhysicalDevice
        )
    }

    private static var isPhysicalDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    private func getLocation() async throws -> NapaxiJSONValue {
        let location = try await locationProvider.currentLocation()
        let timestamp = ISO8601DateFormatter().string(from: location.timestamp)
        return .object([
            "latitude": .number(location.coordinate.latitude),
            "longitude": .number(location.coordinate.longitude),
            "altitude": .number(location.altitude),
            "accuracy": .number(location.horizontalAccuracy),
            "speed": .number(location.speed),
            "timestamp": .string(timestamp),
        ])
    }

    private func getContacts(_ params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        let query = try Self.flutterStringParameter(params, "query")
        let limit = max(1, try Self.flutterIntParameter(params, "limit", default: 20) ?? 20)
        let granted = try await requestContactsAccess()
        guard granted else {
            return .object(["error": .string("Contacts permission denied by user.")])
        }

        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var contacts: [NapaxiJSONValue] = []
        try contactStore.enumerateContacts(with: request) { contact, stop in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            if let query, !query.isEmpty && !name.localizedCaseInsensitiveContains(query) {
                return
            }
            let phones = contact.phoneNumbers.map { NapaxiJSONValue.string($0.value.stringValue) }
            let emails = contact.emailAddresses.map { NapaxiJSONValue.string(String($0.value)) }
            contacts.append(.object([
                "name": .string(name),
                "phones": .array(phones),
                "emails": .array(emails),
            ]))
            if contacts.count >= limit {
                stop.pointee = true
            }
        }
        return .object(["contacts": .array(contacts), "total": .number(Double(contacts.count))])
    }

    private func createCalendarEvent(_ params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        guard try await requestCalendarAccess() else {
            return .object(["error": .string("Calendar permission denied by user.")])
        }
        let title = try Self.flutterStringParameter(params, "title", default: "") ?? ""
        let startString = try Self.flutterStringParameter(params, "start", default: "") ?? ""
        let endString = try Self.flutterStringParameter(params, "end", default: "") ?? ""
        guard let start = parseDate(startString),
              let end = parseDate(endString) else {
            return .object(["error": .string("Invalid date format. Use ISO 8601.")])
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents
            ?? eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications })
        else {
            return .object(["error": .string("No calendar found on device.")])
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = try Self.flutterStringParameter(params, "description")
        try eventStore.save(event, span: .thisEvent, commit: true)
        return .object([
            "success": .bool(true),
            "event_id": .string(event.eventIdentifier ?? ""),
            "title": .string(title),
            "start": .string(isoString(start)),
            "end": .string(isoString(end)),
        ])
    }

    private func listCalendarEvents(_ params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        guard try await requestCalendarAccess() else {
            return .object(["error": .string("Calendar permission denied by user.")])
        }
        let startString = try Self.flutterStringParameter(params, "start", default: "") ?? ""
        let endString = try Self.flutterStringParameter(params, "end", default: "") ?? ""
        guard let start = parseDate(startString),
              let end = parseDate(endString) else {
            return .object(["error": .string("Invalid date format. Use ISO 8601.")])
        }
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event -> NapaxiJSONValue in
                .object([
                    "title": .string(event.title ?? ""),
                    "start": .string(isoString(event.startDate)),
                    "end": .string(isoString(event.endDate)),
                    "description": .string(event.notes ?? ""),
                    "calendar": .string(event.calendar?.title ?? ""),
                    "all_day": .bool(event.isAllDay),
                ])
            }
        return .object(["events": .array(events), "count": .number(Double(events.count))])
    }

    @MainActor
    private func takePhoto() async throws -> NapaxiJSONValue {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .object(["error": .string("Camera is not available on this device.")])
        }
        guard let presenter = UIApplication.shared.napaxiTopViewController() else {
            return .object(["error": .string("No presenting view controller available for camera.")])
        }
        let image = try await NapaxiImageCaptureController.capturePhoto(from: presenter)
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            return .object(["error": .string("Failed to encode photo.")])
        }
        let filename = "photo_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        return try writeAttachment(data: data, category: "camera", filename: filename, kind: "image", mimeType: "image/jpeg")
    }

    private func recordAudio(_ params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        let duration = min(60, max(1, try Self.flutterIntParameter(params, "duration_seconds", default: 10) ?? 10))
        guard try await requestMicrophoneAccess() else {
            return .object(["error": .string("Microphone permission denied by user.")])
        }
        let filename = "rec_\(Int(Date().timeIntervalSince1970 * 1000)).wav"
        let url = try attachmentURL(category: "audio", filename: filename)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)
        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
        ])
        guard recorder.record() else {
            return .object(["error": .string("Recording failed.")])
        }
        try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)
        recorder.stop()
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let sandboxPath = "/workspace/attachments/audio/\(filename)"
        return .object([
            "sandbox_path": .string(sandboxPath),
            "file_path": .string(sandboxPath),
            "kind": .string("audio"),
            "filename": .string(filename),
            "mime_type": .string("audio/wav"),
            "mimeType": .string("audio/wav"),
            "size_bytes": .number(Double(size)),
            "sizeBytes": .number(Double(size)),
            "duration_seconds": .number(Double(duration)),
            "duration_secs": .number(Double(duration)),
        ])
    }

    private func requestContactsAccess() async throws -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return true }
        if #available(iOS 18.0, *), status == .limited { return true }
        if status == .denied || status == .restricted { return false }
        return try await withCheckedThrowingContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestCalendarAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            if status == .fullAccess || status == .writeOnly { return true }
            if status == .denied || status == .restricted { return false }
            return try await eventStore.requestFullAccessToEvents()
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestMicrophoneAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: value) { return date }
        let dateOnly = DateFormatter()
        dateOnly.calendar = Calendar(identifier: .gregorian)
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: value)
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func writeAttachment(data: Data, category: String, filename: String, kind: String, mimeType: String) throws -> NapaxiJSONValue {
        let url = try attachmentURL(category: category, filename: filename)
        try data.write(to: url, options: .atomic)
        let sandboxPath = "/workspace/attachments/\(category)/\(filename)"
        return .object([
            "sandbox_path": .string(sandboxPath),
            "file_path": .string(sandboxPath),
            "kind": .string(kind),
            "filename": .string(filename),
            "mime_type": .string(mimeType),
            "mimeType": .string(mimeType),
            "size_bytes": .number(Double(data.count)),
            "sizeBytes": .number(Double(data.count)),
        ])
    }

    private func attachmentURL(category: String, filename: String) throws -> URL {
        let base = (workspaceFilesDir ?? filesDir).flatMap(URL.init(fileURLWithPath:))
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("napaxi_data", isDirectory: true)
        let dir = base
            .appendingPathComponent("linux-env", isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(category, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }
    #endif

    static func params(from paramsJSON: String, forTool toolName: String) throws -> [String: NapaxiJSONValue] {
        do {
            let value = try NapaxiRawJSON(jsonString: paramsJSON).value
            guard case .object(let object) = value else {
                if requiresParameterObject(toolName) {
                    throw NapaxiError.invalidJSON("Platform tool parameters must be a JSON object")
                }
                return [:]
            }
            return object
        } catch {
            if requiresParameterObject(toolName) {
                throw error
            }
            return [:]
        }
    }

    private static func requiresParameterObject(_ toolName: String) -> Bool {
        switch toolName {
        case "open_url",
             "make_call",
             "send_sms",
             "set_clipboard",
             "send_notification",
             "get_contacts",
             "create_calendar_event",
             "list_calendar_events",
             "media_library",
             "record_audio":
            return true
        default:
            return false
        }
    }
}

private extension NapaxiJSONValue {
    func napaxiJSONString() throws -> String {
        try NapaxiRawJSON(self).jsonString()
    }
}

public typealias FlutterMobileCapabilityHost = NapaxiDefaultPlatformToolExecutor
public typealias FlutterCapabilityHost = NapaxiDefaultPlatformToolExecutor

@available(*, deprecated, message: "Use FlutterCapabilityHost instead.")
public typealias PlatformToolExecutor = FlutterCapabilityHost

public enum UrlTool {
    public static func execute(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("open_url", paramsJSON)
    }
}

public enum PhoneTool {
    public static func makeCall(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("make_call", paramsJSON)
    }

    public static func sendSms(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("send_sms", paramsJSON)
    }
}

public enum ClipboardTool {
    public static func getClipboard(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("get_clipboard", paramsJSON)
    }

    public static func setClipboard(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("set_clipboard", paramsJSON)
    }
}

public enum DeviceInfoTool {
    public static func execute(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("get_device_info", paramsJSON)
    }
}

public enum LocationTool {
    public static func execute(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("get_location", paramsJSON)
    }
}

public enum NotificationTool {
    public static func ensureInit() async -> Bool {
        true
    }

    public static func execute(_ paramsJSON: String) async -> String {
        _ = await ensureInit()
        return await NapaxiPlatformToolFacade.execute("send_notification", paramsJSON)
    }
}

public enum ContactsTool {
    public static func execute(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("get_contacts", paramsJSON)
    }
}

public enum CalendarTool {
    public static func createEvent(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("create_calendar_event", paramsJSON)
    }

    public static func listEvents(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("list_calendar_events", paramsJSON)
    }
}

public enum CameraTool {
    public static func execute(_ paramsJSON: String, _ context: NapaxiMobileCapabilityContext) async -> String {
        await NapaxiPlatformToolFacade.execute("take_photo", paramsJSON, context: context)
    }

    public static func execute(_ paramsJSON: String, context: NapaxiMobileCapabilityContext) async -> String {
        await execute(paramsJSON, context)
    }
}

public enum AudioTool {
    public static func execute(_ paramsJSON: String, _ context: NapaxiMobileCapabilityContext) async -> String {
        await NapaxiPlatformToolFacade.execute("record_audio", paramsJSON, context: context)
    }

    public static func execute(_ paramsJSON: String, context: NapaxiMobileCapabilityContext) async -> String {
        await execute(paramsJSON, context)
    }
}

public enum AlarmTool {
    public static func execute(_ paramsJSON: String) async -> String {
        await NapaxiPlatformToolFacade.execute("set_alarm", paramsJSON)
    }

    public static func buildIntentArguments(_ paramsJSON: String) throws -> [String: NapaxiJSONValue] {
        let decoded = try NapaxiRawJSON(jsonString: paramsJSON).value
        guard case .object(let object) = decoded else {
            throw NapaxiError.invalidJSON("Alarm parameters must be a JSON object.")
        }

        let time = try parseAlarmTime(object["time"]?.stringValue ?? "")
        let message = object["message"]?.stringValue ?? "Alarm"
        let repeatDays = try parseRepeatDays(
            object["repeat_days"] ?? object["repeatDays"] ?? object["days"]
        )

        var arguments: [String: NapaxiJSONValue] = [
            "android.intent.extra.alarm.HOUR": .number(Double(time.hour)),
            "android.intent.extra.alarm.MINUTES": .number(Double(time.minute)),
            "android.intent.extra.alarm.MESSAGE": .string(message),
            "android.intent.extra.alarm.SKIP_UI": .bool(true),
        ]
        if let repeatDays {
            arguments["android.intent.extra.alarm.DAYS"] = .array(repeatDays.map { .number(Double($0)) })
        }
        return arguments
    }

    private static func parseAlarmTime(_ timeString: String) throws -> (hour: Int, minute: Int) {
        let hhmmPattern = #"^(\d{1,2}):(\d{2})$"#
        if let regex = try? NSRegularExpression(pattern: hhmmPattern),
           let match = regex.firstMatch(in: timeString, range: NSRange(timeString.startIndex..., in: timeString)),
           let hourRange = Range(match.range(at: 1), in: timeString),
           let minuteRange = Range(match.range(at: 2), in: timeString),
           let hour = Int(timeString[hourRange]),
           let minute = Int(timeString[minuteRange]) {
            return try validateAlarmTime(hour: hour, minute: minute)
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        if let date = fractional.date(from: timeString) ?? standard.date(from: timeString) {
            let components = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
            if let hour = components.hour, let minute = components.minute {
                return try validateAlarmTime(hour: hour, minute: minute)
            }
        }

        throw NapaxiError.invalidJSON(#"Invalid time format. Use HH:mm (e.g. "07:30") or ISO 8601."#)
    }

    private static func validateAlarmTime(hour: Int, minute: Int) throws -> (hour: Int, minute: Int) {
        guard hour >= 0, hour <= 23, minute >= 0, minute <= 59 else {
            throw NapaxiError.invalidJSON("Invalid alarm time. Hour must be 0-23 and minute must be 0-59.")
        }
        return (hour, minute)
    }

    private static func parseRepeatDays(_ rawDays: NapaxiJSONValue?) throws -> [Int]? {
        guard let rawDays, rawDays != .null else { return nil }
        var days: [Int] = []
        var seen = Set<Int>()

        func addDay(_ day: Int) throws {
            guard day >= 1, day <= 7 else {
                throw NapaxiError.invalidJSON("Invalid repeat day: \(day).")
            }
            if seen.insert(day).inserted {
                days.append(day)
            }
        }

        func addAll(_ values: [Int]) throws {
            for value in values {
                try addDay(value)
            }
        }

        func parseOne(_ value: NapaxiJSONValue) throws {
            if let number = value.numberValue {
                guard number.rounded() == number else {
                    throw NapaxiError.invalidJSON("Invalid repeat day: \(number).")
                }
                try addDay(Int(number))
                return
            }
            guard let rawString = value.stringValue else {
                throw NapaxiError.invalidJSON("Invalid repeat day: \(value).")
            }

            let normalized = rawString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.isEmpty {
                return
            }
            if let preset = repeatDayPresets[normalized] {
                try addAll(preset)
                return
            }
            if normalized.contains(",") {
                for part in normalized.split(separator: ",") {
                    try parseOne(.string(String(part)))
                }
                return
            }
            guard let day = repeatDayAliases[normalized] else {
                throw NapaxiError.invalidJSON("Invalid repeat day: \(rawString).")
            }
            try addDay(day)
        }

        if let rawArray = rawDays.arrayValue {
            for value in rawArray {
                try parseOne(value)
            }
        } else {
            try parseOne(rawDays)
        }

        return days.isEmpty ? nil : days
    }

    private static let repeatDayPresets: [String: [Int]] = [
        "daily": [1, 2, 3, 4, 5, 6, 7],
        "everyday": [1, 2, 3, 4, 5, 6, 7],
        "every day": [1, 2, 3, 4, 5, 6, 7],
        "all": [1, 2, 3, 4, 5, 6, 7],
        "每天": [1, 2, 3, 4, 5, 6, 7],
        "每日": [1, 2, 3, 4, 5, 6, 7],
        "weekdays": [2, 3, 4, 5, 6],
        "weekday": [2, 3, 4, 5, 6],
        "workdays": [2, 3, 4, 5, 6],
        "workday": [2, 3, 4, 5, 6],
        "工作日": [2, 3, 4, 5, 6],
        "weekends": [1, 7],
        "weekend": [1, 7],
        "周末": [1, 7],
    ]

    private static let repeatDayAliases: [String: Int] = [
        "sunday": 1, "sun": 1, "周日": 1, "星期日": 1, "礼拜日": 1, "周天": 1, "星期天": 1, "礼拜天": 1,
        "monday": 2, "mon": 2, "周一": 2, "星期一": 2, "礼拜一": 2,
        "tuesday": 3, "tue": 3, "tues": 3, "周二": 3, "星期二": 3, "礼拜二": 3,
        "wednesday": 4, "wed": 4, "周三": 4, "星期三": 4, "礼拜三": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5, "周四": 5, "星期四": 5, "礼拜四": 5,
        "friday": 6, "fri": 6, "周五": 6, "星期五": 6, "礼拜五": 6,
        "saturday": 7, "sat": 7, "周六": 7, "星期六": 7, "礼拜六": 7,
    ]
}

public enum InstallAppTool {
    public static func execute(_ paramsJSON: String, _ context: NapaxiMobileCapabilityContext) async -> String {
        await NapaxiPlatformToolFacade.execute("install_apk", paramsJSON, context: context)
    }

    public static func execute(_ paramsJSON: String, context: NapaxiMobileCapabilityContext) async -> String {
        await execute(paramsJSON, context)
    }
}

private enum NapaxiPlatformToolFacade {
    static func execute(
        _ toolName: String,
        _ paramsJSON: String,
        context: NapaxiMobileCapabilityContext? = nil
    ) async -> String {
        let executor = NapaxiDefaultPlatformToolExecutor(
            filesDir: context?.filesDir,
            workspaceFilesDir: context?.workspaceFilesDir
        )
        return await executor.execute(toolName, paramsJSON)
    }
}

#if os(iOS)
private final class NapaxiLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func currentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            handleAuthorizationStatus(currentAuthorizationStatus())
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationStatus(currentAuthorizationStatus())
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleAuthorizationStatus(status)
    }

    private func currentAuthorizationStatus() -> CLAuthorizationStatus {
        manager.authorizationStatus
    }

    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .restricted, .denied:
            finish(.failure(NapaxiError.unavailable("Location permission denied by user.")))
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            finish(.success(location))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let location):
            continuation.resume(returning: location)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

@MainActor
private final class NapaxiImageCaptureController: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private var continuation: CheckedContinuation<UIImage, Error>?

    static func capturePhoto(from presenter: UIViewController) async throws -> UIImage {
        let controller = NapaxiImageCaptureController()
        return try await controller.capture(from: presenter)
    }

    private func capture(from presenter: UIViewController) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = self
            presenter.present(picker, animated: true)
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else {
            continuation?.resume(throwing: NapaxiError.invalidState("Camera did not return an image."))
            continuation = nil
            return
        }
        continuation?.resume(returning: image)
        continuation = nil
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        continuation?.resume(throwing: NapaxiError.unavailable("Photo cancelled by user."))
        continuation = nil
    }
}

private extension UIApplication {
    @MainActor
    func napaxiTopViewController() -> UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        if let navigation = top as? UINavigationController {
            return navigation.visibleViewController ?? navigation
        }
        if let tab = top as? UITabBarController {
            return tab.selectedViewController ?? tab
        }
        return top
    }
}
#endif
