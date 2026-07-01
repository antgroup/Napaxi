import Flutter
import Foundation
import Photos
import UIKit

@_silgen_name("napaxi_ios_ish_register_rootfs_archive_path")
private func napaxi_ios_ish_register_rootfs_archive_path(_ path: UnsafePointer<CChar>?)
@_silgen_name("napaxi_force_link")
private func napaxi_force_link()

public class NapaxiFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private static var didRegisterSandboxResources = false
    private static var activeInstance: NapaxiFlutterPlugin?

    private var eventSink: FlutterEventSink?
    private var backgroundEventChannel: FlutterEventChannel?
    private var a2aLocalTransport: A2ALocalTransport?
    private var pendingProviderInstallResult: FlutterResult?
    private var pendingProviderInstall: [String: Any]?
    private var pendingProviderInstallLaunch: [String: String]?
    private var pendingAgentTriggerLaunch: [String: String]?
    private var pendingA2ADeepLinkLaunch: [String: String]?
    private var pendingAgentActionResult: FlutterResult?
    private var pendingAgentActionRequestId: String?

    public static func register(with registrar: FlutterPluginRegistrar) {
        napaxi_force_link()

        let instance = NapaxiFlutterPlugin()
        activeInstance = instance
        let platformChannel = FlutterMethodChannel(
            name: "com.napaxi.flutter/platform_context",
            binaryMessenger: registrar.messenger()
        )
        platformChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "getPlatformContext":
                result([
                    "platform": "ios",
                    "filesDir": filesDir(),
                    "userTimezone": TimeZone.current.identifier,
                ])
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let backgroundChannel = FlutterMethodChannel(
            name: "com.napaxi.flutter/background",
            binaryMessenger: registrar.messenger()
        )
        backgroundChannel.setMethodCallHandler(instance.handleBackgroundCall)
        let mediaLibraryChannel = FlutterMethodChannel(
            name: "com.napaxi.flutter/media_library",
            binaryMessenger: registrar.messenger()
        )
        mediaLibraryChannel.setMethodCallHandler(instance.handleMediaLibraryCall)
        let eventChannel = FlutterEventChannel(
            name: "com.napaxi.flutter/background_events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
        instance.backgroundEventChannel = eventChannel
        instance.a2aLocalTransport = A2ALocalTransport { [weak instance] in instance?.eventSink }
        registrar.addApplicationDelegate(instance)
        registerIosSandboxResourcesIfNeeded()
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    @objc public static func handleOpenURL(_ url: URL) -> Bool {
        NSLog("NapaxiFlutterPlugin: scene URL %@", url.absoluteString)
        let handled = activeInstance?.handleAgentProviderURL(url) ?? false
        NSLog("NapaxiFlutterPlugin: scene URL handled=%@", handled ? "true" : "false")
        return handled
    }

    private func handleBackgroundCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "listAgentProviders":
            result([])
        case "getAgentProviderHostInfo":
            result(agentProviderHostInfo())
        case "requestAgentProviderInstall":
            let args = call.arguments as? [String: Any]
            requestAgentProviderInstall(args: args, result: result)
        case "getPendingProviderInstallRequest":
            result(pendingProviderInstallLaunch)
        case "clearPendingProviderInstallRequest":
            pendingProviderInstallLaunch = nil
            result(nil)
        case "getPendingAgentTriggerRequest":
            result(pendingAgentTriggerLaunch)
        case "clearPendingAgentTriggerRequest":
            pendingAgentTriggerLaunch = nil
            result(nil)
        case "getPendingA2ADeepLink":
            result(pendingA2ADeepLinkLaunch)
        case "clearPendingA2ADeepLink":
            pendingA2ADeepLinkLaunch = nil
            result(nil)
        case "a2aLocalTransportStatus":
            result(a2aLocalTransport?.status() ?? a2aLocalTransportUnavailable())
        case "checkA2ALocalPermission":
            result(a2aLocalTransport?.hasRequiredLocalNetworkDeclarations() ?? false)
        case "requestA2ALocalPermission":
            result(a2aLocalTransport?.hasRequiredLocalNetworkDeclarations() ?? false)
        case "startA2ALocalTransport":
            result(a2aLocalTransport?.start(args: call.arguments as? [String: Any]) ?? a2aLocalTransportUnavailable())
        case "stopA2ALocalTransport":
            result(a2aLocalTransport?.stop() ?? a2aLocalTransportUnavailable())
        case "discoverA2ALocalPeers":
            result(a2aLocalTransport?.discover(args: call.arguments as? [String: Any]) ?? [
                "started": false,
                "peers": [],
                "reason": "ios_a2a_transport_unavailable"
            ])
        case "sendA2ALocalMessage":
            result(a2aLocalTransport?.send(args: call.arguments as? [String: Any]) ?? [
                "sent": false,
                "reason": "ios_a2a_transport_unavailable"
            ])
        case "drainA2ALocalTransportEvents":
            result(a2aLocalTransport?.drainEvents() ?? [])
        case "executeAgentProviderAction":
            let args = call.arguments as? [String: Any]
            executeAgentProviderAction(args: args, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleMediaLibraryCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "mediaLibrary" else {
            result(FlutterMethodNotImplemented)
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        let action = (args["action"] as? String ?? "status").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch action {
        case "status":
            result(mediaLibraryStatus(types: mediaTypes(args)))
        case "search":
            withMediaLibraryAuthorization(args: args, result: result) { [weak self] in
                guard let self else { return }
                result(self.searchMediaAssetsResult(args: args))
            }
        case "import":
            withMediaLibraryAuthorization(args: args, result: result) { [weak self] in
                guard let self else { return }
                self.importMediaAssets(args: args, result: result)
            }
        default:
            result([
                "success": false,
                "supported": true,
                "action": action,
                "error": "Unsupported media_library action: \(action)",
            ])
        }
    }

    private func withMediaLibraryAuthorization(
        args: [String: Any],
        result: @escaping FlutterResult,
        perform: @escaping () -> Void
    ) {
        let types = mediaTypes(args)
        let status = photoAuthorizationStatus()
        if photoStatusGranted(status) {
            perform()
            return
        }
        let requestPermission = boolArg(args, snakeKey: "request_permission", camelKey: "requestPermission", defaultValue: true)
        guard requestPermission else {
            result(mediaLibraryPermissionRequired(types: types, requestable: true))
            return
        }
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.photoStatusGranted(newStatus) {
                        perform()
                    } else {
                        result(self.mediaLibraryPermissionRequired(types: types, requestable: true))
                    }
                }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.photoStatusGranted(newStatus) {
                        perform()
                    } else {
                        result(self.mediaLibraryPermissionRequired(types: types, requestable: true))
                    }
                }
            }
        }
    }

    private func mediaLibraryStatus(types: Set<String>) -> [String: Any] {
        let status = photoAuthorizationStatus()
        let granted = photoStatusGranted(status)
        return [
            "success": true,
            "supported": true,
            "action": "status",
            "mediaTypes": Array(types).sorted(),
            "permissionStatus": photoStatusString(status),
            "granted": granted,
            "permissionRequired": !granted,
            "canRequest": true,
            "pickAvailable": true,
        ]
    }

    private func mediaLibraryPermissionRequired(types: Set<String>, requestable: Bool) -> [String: Any] {
        var status = mediaLibraryStatus(types: types)
        status["success"] = false
        status["canRequest"] = requestable
        status["error"] = "Media library permission is required."
        return status
    }

    private func searchMediaAssetsResult(args: [String: Any]) -> [String: Any] {
        let assets = searchMediaAssets(args: args)
        return [
            "success": true,
            "supported": true,
            "action": "search",
            "assets": assets.map(mediaAssetPublicMap),
            "count": assets.count,
            "permissionStatus": photoStatusString(photoAuthorizationStatus()),
        ]
    }

    private func importMediaAssets(args: [String: Any], result: @escaping FlutterResult) {
        guard let outputDir = args["outputDir"] as? String, !outputDir.isEmpty else {
            result([
                "success": false,
                "supported": true,
                "action": "import",
                "error": "outputDir is required",
            ])
            return
        }
        let sandboxPrefix = (args["sandboxPrefix"] as? String ?? "/workspace/attachments/media")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = "/\(sandboxPrefix)"
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let limit = intArg(args, keys: ["limit", "max_count", "maxCount"]) ?? 20
        let assetIds = stringListArg(args, keys: ["asset_ids", "assetIds"])
        let assets = assetIds.isEmpty ? Array(searchMediaAssets(args: args).prefix(limit)) : assetsByIds(assetIds)
        guard !assets.isEmpty else {
            result([
                "success": true,
                "supported": true,
                "action": "import",
                "artifacts": [],
                "attachments": [],
                "count": 0,
                "permissionStatus": photoStatusString(photoAuthorizationStatus()),
            ])
            return
        }

        let group = DispatchGroup()
        let lockQueue = DispatchQueue(label: "com.napaxi.flutter.media_library.import")
        var artifacts: [[String: Any]] = []
        var errors: [String] = []
        for (index, asset) in assets.prefix(limit).enumerated() {
            group.enter()
            importAsset(asset, outputDir: outputDir, sandboxPrefix: prefix, index: index) { artifact, error in
                lockQueue.async {
                    if let artifact { artifacts.append(artifact) }
                    if let error { errors.append(error) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            var response: [String: Any] = [
                "success": errors.isEmpty || !artifacts.isEmpty,
                "supported": true,
                "action": "import",
                "artifacts": artifacts,
                "attachments": artifacts,
                "count": artifacts.count,
                "permissionStatus": self.photoStatusString(self.photoAuthorizationStatus()),
            ]
            if !errors.isEmpty { response["errors"] = errors }
            result(response)
        }
    }

    private func searchMediaAssets(args: [String: Any]) -> [PHAsset] {
        let types = mediaTypes(args)
        let limit = intArg(args, keys: ["limit", "max_count", "maxCount"]) ?? 20
        let startMs = int64Arg(args, keys: ["start_ms", "startMs"])
        let endMs = int64Arg(args, keys: ["end_ms", "endMs"])
        var assets: [PHAsset] = []
        for type in types {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = limit
            var predicates: [NSPredicate] = []
            if let startMs {
                predicates.append(NSPredicate(format: "creationDate >= %@", Date(timeIntervalSince1970: Double(startMs) / 1000.0) as NSDate))
            }
            if let endMs {
                predicates.append(NSPredicate(format: "creationDate < %@", Date(timeIntervalSince1970: Double(endMs) / 1000.0) as NSDate))
            }
            if !predicates.isEmpty {
                options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            }
            let mediaType: PHAssetMediaType = type == "video" ? .video : .image
            let fetched = PHAsset.fetchAssets(with: mediaType, options: options)
            fetched.enumerateObjects { asset, _, stop in
                assets.append(asset)
                if assets.count >= limit { stop.pointee = true }
            }
            if assets.count >= limit { break }
        }
        return assets.sorted {
            ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
        }.prefix(limit).map { $0 }
    }

    private func assetsByIds(_ ids: [String]) -> [PHAsset] {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assetsById: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in assetsById[asset.localIdentifier] = asset }
        return ids.compactMap { assetsById[$0] }
    }

    private func importAsset(
        _ asset: PHAsset,
        outputDir: String,
        sandboxPrefix: String,
        index: Int,
        completion: @escaping ([String: Any]?, String?) -> Void
    ) {
        guard let resource = PHAssetResource.assetResources(for: asset).first else {
            completion(nil, "Asset resource unavailable")
            return
        }
        let mimeType = mimeTypeForResource(resource)
        let filename = safeMediaFilename(resource.originalFilename, mimeType: mimeType, index: index)
        let fileURL = URL(fileURLWithPath: outputDir).appendingPathComponent(filename)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            completion(nil, "Unable to create media artifact")
            return
        }
        PHAssetResourceManager.default().requestData(for: resource, options: nil) { data in
            handle.write(data)
        } completionHandler: { error in
            handle.closeFile()
            if let error {
                completion(nil, error.localizedDescription)
                return
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            let sandboxPath = "\(sandboxPrefix)/\(filename)"
            completion([
                "artifactId": filename,
                "kind": asset.mediaType == .image ? "image" : "file",
                "mimeType": mimeType,
                "mime_type": mimeType,
                "name": resource.originalFilename,
                "filename": filename,
                "uri": sandboxPath,
                "sandbox_path": sandboxPath,
                "sizeBytes": size,
                "size_bytes": size,
                "metadata": self.mediaAssetMetadata(asset),
            ], nil)
        }
    }

    private func mediaAssetPublicMap(_ asset: PHAsset) -> [String: Any] {
        let resource = PHAssetResource.assetResources(for: asset).first
        var map: [String: Any] = [
            "assetId": asset.localIdentifier,
            "mediaType": asset.mediaType == .video ? "video" : "image",
            "mimeType": resource.map { self.mimeTypeForResource($0) } ?? (asset.mediaType == .video ? "video/mp4" : "image/jpeg"),
            "name": resource?.originalFilename ?? asset.localIdentifier,
            "width": asset.pixelWidth,
            "height": asset.pixelHeight,
        ]
        if let creationDate = asset.creationDate {
            map["createdAtMs"] = Int64(creationDate.timeIntervalSince1970 * 1000.0)
        }
        if asset.mediaType == .video {
            map["durationMs"] = Int64(asset.duration * 1000.0)
        }
        return map
    }

    private func mediaAssetMetadata(_ asset: PHAsset) -> [String: Any] {
        var map: [String: Any] = [
            "source": "media_library",
            "assetId": asset.localIdentifier,
            "mediaType": asset.mediaType == .video ? "video" : "image",
            "width": asset.pixelWidth,
            "height": asset.pixelHeight,
        ]
        if let creationDate = asset.creationDate {
            map["createdAtMs"] = Int64(creationDate.timeIntervalSince1970 * 1000.0)
        }
        if asset.mediaType == .video {
            map["durationMs"] = Int64(asset.duration * 1000.0)
        }
        return map
    }

    private func photoAuthorizationStatus() -> PHAuthorizationStatus {
        if #available(iOS 14, *) {
            return PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        return PHPhotoLibrary.authorizationStatus()
    }

    private func photoStatusGranted(_ status: PHAuthorizationStatus) -> Bool {
        if #available(iOS 14, *), status == .limited { return true }
        return status == .authorized
    }

    private func photoStatusString(_ status: PHAuthorizationStatus) -> String {
        if #available(iOS 14, *), status == .limited { return "limited" }
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "permission_required"
        @unknown default:
            return "unknown"
        }
    }

    private func mediaTypes(_ args: [String: Any]) -> Set<String> {
        let raw = args["media_types"] ?? args["mediaTypes"]
        let values: [String]
        if let list = raw as? [Any] {
            values = list.map { "\($0)" }
        } else if let string = raw as? String {
            values = string.split(separator: ",").map(String.init)
        } else {
            values = []
        }
        let normalized = Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { $0 == "image" || $0 == "video" })
        return normalized.isEmpty ? ["image"] : normalized
    }

    private func intArg(_ args: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = args[key] as? Int { return value }
            if let value = args[key] as? NSNumber { return value.intValue }
            if let value = args[key] as? String, let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return intValue }
        }
        return nil
    }

    private func int64Arg(_ args: [String: Any], keys: [String]) -> Int64? {
        for key in keys {
            if let value = args[key] as? Int64 { return value }
            if let value = args[key] as? Int { return Int64(value) }
            if let value = args[key] as? NSNumber { return value.int64Value }
            if let value = args[key] as? String, let intValue = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return intValue }
        }
        return nil
    }

    private func boolArg(_ args: [String: Any], snakeKey: String, camelKey: String, defaultValue: Bool) -> Bool {
        let value = args[snakeKey] ?? args[camelKey]
        if let bool = value as? Bool { return bool }
        if let string = value as? String { return string.caseInsensitiveCompare("true") == .orderedSame }
        return defaultValue
    }

    private func stringListArg(_ args: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let list = args[key] as? [Any] {
                return list.map { "\($0)".trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            if let string = args[key] as? String {
                return string.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
        }
        return []
    }

    private func safeMediaFilename(_ originalName: String, mimeType: String, index: Int) -> String {
        let ext = extensionForMedia(originalName, mimeType: mimeType)
        let rawStem = (originalName as NSString).deletingPathExtension
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let stem = rawStem.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        let safeStem = String((stem.isEmpty ? "media" : stem).prefix(48))
        return "\(safeStem)_\(Int(Date().timeIntervalSince1970 * 1000))_\(index)\(ext)"
    }

    private func extensionForMedia(_ name: String, mimeType: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if !ext.isEmpty { return ".\(ext)" }
        switch mimeType.lowercased() {
        case "image/png": return ".png"
        case "image/heic": return ".heic"
        case "image/webp": return ".webp"
        case "image/gif": return ".gif"
        case "video/quicktime": return ".mov"
        default: return mimeType.lowercased().hasPrefix("video/") ? ".mp4" : ".jpg"
        }
    }

    private func mimeTypeForResource(_ resource: PHAssetResource) -> String {
        let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "mov": return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        default:
            return resource.type == .video ? "video/mp4" : "image/jpeg"
        }
    }

    private func a2aLocalTransportUnavailable() -> [String: Any] {
        [
            "supported": false,
            "running": false,
            "transport": "lan_tcp_jsonl",
            "serviceType": "_napaxi-a2a._tcp.",
            "reason": "ios_a2a_transport_unavailable"
        ]
    }

    public func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        handleAgentProviderURL(url)
    }

    public func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([Any]) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }
        return handleAgentProviderURL(url)
    }

    private func handleAgentProviderURL(_ url: URL) -> Bool {
        NSLog("NapaxiFlutterPlugin: handling URL %@", url.absoluteString)
        if queryValue("install_result", in: url) != nil {
            handleAgentProviderInstallCallback(url)
            return true
        }
        if queryValue("result", in: url) != nil {
            handleAgentProviderActionCallback(url)
            return true
        }
        if let triggerJson = queryValue("trigger_request", in: url) {
            pendingAgentTriggerLaunch = ["triggerRequestJson": triggerJson]
            return true
        }
        if let envelopeJson = queryValue("envelope", in: url) {
            pendingA2ADeepLinkLaunch = [
                "envelopeJson": envelopeJson,
                "source": url.scheme ?? "url"
            ]
            return true
        }
        if let descriptor = providerDescriptor(from: url) {
            pendingProviderInstallLaunch = descriptor
            return true
        }
        return false
    }

    private func providerDescriptor(from url: URL) -> [String: String]? {
        let installURL = queryValue("install_url", in: url)
        let actionURL = queryValue("action_url", in: url)
        guard let installURL, !installURL.isEmpty else {
            return nil
        }
        let universalDomain = queryValue("universal_link_domain", in: url)
            ?? URL(string: installURL)?.host
            ?? ""
        return [
            "platform": "ios",
            "packageName": "",
            "installActivityName": "",
            "activityName": "",
            "label": queryValue("label", in: url) ?? universalDomain,
            "signingCertSha256": "",
            "installUrl": installURL,
            "actionUrl": actionURL ?? installURL,
            "universalLinkDomain": universalDomain,
            "iosBundleId": queryValue("ios_bundle_id", in: url) ?? "",
            "iosTeamId": queryValue("ios_team_id", in: url) ?? "",
        ]
    }

    private func requestAgentProviderInstall(args: [String: Any]?, result: @escaping FlutterResult) {
        guard pendingProviderInstallResult == nil else {
            result(FlutterError(
                code: "IN_PROGRESS",
                message: "Agent provider install already in progress",
                details: nil
            ))
            return
        }
        guard let provider = args?["provider"] as? [String: Any],
              let requestJson = args?["requestJson"] as? String,
              let installURLString = provider["installUrl"] as? String,
              let installURL = URL(string: installURLString),
              !requestJson.isEmpty else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "provider installUrl and requestJson are required",
                details: nil
            ))
            return
        }
        guard !callbackScheme().isEmpty else {
            result(FlutterError(
                code: "CALLBACK_SCHEME_UNAVAILABLE",
                message: "Host app must declare a URL scheme for iOS provider callbacks",
                details: nil
            ))
            return
        }
        guard let handoffURL = appendQueryItem("install_request", value: requestJson, to: installURL) else {
            result(FlutterError(code: "INVALID_URL", message: "Unable to build install URL", details: nil))
            return
        }

        pendingProviderInstallResult = result
        pendingProviderInstall = [
            "provider": provider,
            "requestJson": requestJson,
        ]
        NSLog("NapaxiFlutterPlugin: opening provider install URL %@", handoffURL.absoluteString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let pendingResult = self?.pendingProviderInstallResult else { return }
            NSLog("NapaxiFlutterPlugin: provider install callback timed out")
            self?.pendingProviderInstallResult = nil
            self?.pendingProviderInstall = nil
            pendingResult(FlutterError(
                code: "INSTALL_CALLBACK_TIMEOUT",
                message: "Timed out waiting for provider install callback",
                details: nil
            ))
        }
        UIApplication.shared.open(handoffURL, options: [:]) { [weak self] success in
            NSLog("NapaxiFlutterPlugin: provider install open success=%@", success ? "true" : "false")
            guard !success else { return }
            self?.pendingProviderInstallResult = nil
            self?.pendingProviderInstall = nil
            result(FlutterError(
                code: "INSTALL_HANDOFF_FAILED",
                message: "Unable to open provider install URL",
                details: nil
            ))
        }
    }

    private func handleAgentProviderInstallCallback(_ url: URL) {
        guard let result = pendingProviderInstallResult else {
            NSLog("NapaxiFlutterPlugin: install callback ignored because no pending result")
            return
        }
        NSLog("NapaxiFlutterPlugin: provider install callback received")
        let pending = pendingProviderInstall
        pendingProviderInstallResult = nil
        pendingProviderInstall = nil
        guard let installResultJson = queryValue("install_result", in: url),
              let pending,
              let provider = pending["provider"] as? [String: Any],
              let requestJson = pending["requestJson"] as? String,
              let request = parseJsonObject(requestJson) else {
            result([
                "success": false,
                "error": "Provider install result missing",
            ])
            return
        }
        let installResult = parseJsonObject(installResultJson)
        let installBinding: [String: Any] = [
            "platform": "ios",
            "app_package_name": "",
            "activity_name": "",
            "signing_cert_sha256": "",
            "installed_at": isoNow(),
            "install_request_id": installResult?["request_id"] as? String ?? "",
            "protocol_version": request["protocol_version"] as? Int ?? 1,
            "host_package_name": request["host_package_name"] as? String ?? "",
            "host_signing_cert_sha256": request["host_signing_cert_sha256"] as? String ?? "",
            "host_instance_id": request["host_instance_id"] as? String ?? "",
            "host_shared_secret": request["host_shared_secret"] as? String ?? "",
            "ios_bundle_id": provider["iosBundleId"] as? String ?? "",
            "ios_team_id": provider["iosTeamId"] as? String ?? "",
            "install_url": provider["installUrl"] as? String ?? "",
            "action_url": provider["actionUrl"] as? String ?? "",
            "universal_link_domain": provider["universalLinkDomain"] as? String ?? "",
            "host_bundle_id": request["host_bundle_id"] as? String ?? "",
            "host_team_id": request["host_team_id"] as? String ?? "",
            "host_callback_scheme": request["host_callback_scheme"] as? String ?? "",
        ]
        result([
            "success": true,
            "installResultJson": installResultJson,
            "installBinding": installBinding,
        ])
    }

    private func executeAgentProviderAction(args: [String: Any]?, result: @escaping FlutterResult) {
        guard pendingAgentActionResult == nil else {
            result([
                "success": false,
                "error": "Agent provider action already in progress",
            ])
            return
        }
        guard let requestJson = args?["requestJson"] as? String,
              let request = parseJsonObject(requestJson),
              let proposal = request["proposal"] as? [String: Any],
              let action = request["action"] as? [String: Any],
              let package = request["package"] as? [String: Any],
              let binding = package["install_binding"] as? [String: Any] else {
            result([
                "success": false,
                "error": "Invalid provider action request JSON",
            ])
            return
        }
        guard binding["platform"] as? String == "ios" else {
            result([
                "success": false,
                "error": "Provider action package is not installed with an iOS binding",
            ])
            return
        }
        guard let actionURLString = binding["action_url"] as? String,
              let actionURL = URL(string: actionURLString),
              !actionURLString.isEmpty else {
            result([
                "success": false,
                "error": "Provider action binding is missing action_url",
            ])
            return
        }
        let scheme = binding["host_callback_scheme"] as? String ?? callbackScheme()
        guard !scheme.isEmpty else {
            result([
                "success": false,
                "error": "Host callback scheme is unavailable",
            ])
            return
        }
        let requestId = proposal["request_id"] as? String ?? ""
        let callbackURL = "\(scheme)://agent-provider/action-callback?request_id=\(urlEncode(requestId))"
        let sanitizedPackage = sanitizePackageForProvider(package)
        guard
            let proposalJson = jsonString(proposal),
            let actionJson = jsonString(action),
            let packageJson = jsonString(sanitizedPackage),
            let withProposal = appendQueryItem("proposal", value: proposalJson, to: actionURL),
            let withAction = appendQueryItem("action", value: actionJson, to: withProposal),
            let withPackage = appendQueryItem("package", value: packageJson, to: withAction),
            let handoffURL = appendQueryItem("callback_url", value: callbackURL, to: withPackage)
        else {
            result([
                "success": false,
                "error": "Unable to build provider action URL",
            ])
            return
        }

        pendingAgentActionResult = result
        pendingAgentActionRequestId = requestId
        UIApplication.shared.open(handoffURL, options: [:]) { [weak self] success in
            guard !success else { return }
            self?.pendingAgentActionResult = nil
            self?.pendingAgentActionRequestId = nil
            result([
                "success": false,
                "resultJson": self?.failedActionResultJson(
                    requestId: requestId,
                    message: "Provider action handoff failed"
                ) ?? "{}",
            ])
        }
    }

    private func handleAgentProviderActionCallback(_ url: URL) {
        guard let result = pendingAgentActionResult else {
            return
        }
        let requestId = pendingAgentActionRequestId
        pendingAgentActionResult = nil
        pendingAgentActionRequestId = nil
        guard let resultJson = queryValue("result", in: url), !resultJson.isEmpty else {
            result([
                "success": false,
                "resultJson": failedActionResultJson(
                    requestId: requestId ?? "",
                    message: "Provider action returned no result"
                ),
            ])
            return
        }
        result([
            "success": true,
            "resultJson": resultJson,
        ])
    }

    private func agentProviderHostInfo() -> [String: String] {
        let scheme = callbackScheme()
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let teamId = hostTeamId()
        return [
            "packageName": bundleId,
            "bundleId": bundleId,
            "teamId": teamId,
            "callbackScheme": scheme,
        ]
    }

    private func callbackScheme() -> String {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        return schemes.first(where: { $0.localizedCaseInsensitiveContains("agent") })
            ?? schemes.first
            ?? ""
    }

    private func hostTeamId() -> String {
        ""
    }

    private func sanitizePackageForProvider(_ package: [String: Any]) -> [String: Any] {
        var copy = package
        if var binding = copy["install_binding"] as? [String: Any] {
            binding.removeValue(forKey: "host_shared_secret")
            copy["install_binding"] = binding
        }
        return copy
    }

    private func failedActionResultJson(requestId: String, message: String) -> String {
        jsonString([
            "request_id": requestId,
            "status": "failed",
            "result": [:],
            "error": message,
            "completed_at": isoNow(),
        ]) ?? "{}"
    }

    private static func filesDir() -> String {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return url.appendingPathComponent("napaxi_data", isDirectory: true).path
    }

    private static func registerIosSandboxResourcesIfNeeded() {
        guard !didRegisterSandboxResources else { return }
        didRegisterSandboxResources = true

        guard let rootfsArchive = bundledRootfsArchive() else {
            NSLog("NapaxiFlutterPlugin: alpine-rootfs.tar.gz not found")
            return
        }

        rootfsArchive.path.withCString { path in
            napaxi_ios_ish_register_rootfs_archive_path(path)
        }
        NSLog("NapaxiFlutterPlugin: registered iSH rootfs archive at %@", rootfsArchive.path)
    }

    private static func bundledRootfsArchive() -> URL? {
        if let bundleURL = Bundle.main.url(forResource: "iSHCore", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL),
           let tarURL = bundle.url(forResource: "alpine-rootfs.tar", withExtension: "gz") {
            return tarURL
        }

        return Bundle.main.url(forResource: "alpine-rootfs.tar", withExtension: "gz")
    }
}

private func parseJsonObject(_ value: String) -> [String: Any]? {
    guard let data = value.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let map = object as? [String: Any] else {
        return nil
    }
    return map
}

private func jsonString(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func queryValue(_ name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == name })?
        .value
}

private func appendQueryItem(_ name: String, value: String, to url: URL) -> URL? {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return nil
    }
    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: name, value: value))
    components.queryItems = items
    return components.url
}

private func urlEncode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
}

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
