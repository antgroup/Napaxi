import XCTest
@testable import Napaxi

final class AgentProviderHostTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: NapaxiAgentProviderHost.consumedTriggerRequestIdsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: NapaxiAgentProviderHost.consumedTriggerRequestIdsKey)
        super.tearDown()
    }

    func testProviderDescriptorFromURL() {
        let host = NapaxiAgentProviderHost(callbackScheme: "napaxi-test")
        let url = URL(string: "napaxi-test://provider?install_url=https%3A%2F%2Fwallet.example%2Finstall&action_url=https%3A%2F%2Fwallet.example%2Faction&label=Wallet&ios_bundle_id=com.example.wallet&ios_team_id=TEAM")!

        XCTAssertTrue(host.handleOpenURL(url))
        XCTAssertEqual(host.getPendingProviderInstallRequest()?.label, "Wallet")
        let descriptor = host.consumePendingProviderInstall()

        XCTAssertEqual(descriptor?.platform, "ios")
        XCTAssertEqual(descriptor?.label, "Wallet")
        XCTAssertEqual(descriptor?.installUrl, "https://wallet.example/install")
        XCTAssertEqual(descriptor?.actionUrl, "https://wallet.example/action")
        XCTAssertEqual(descriptor?.universalLinkDomain, "wallet.example")
        XCTAssertEqual(descriptor?.iosBundleId, "com.example.wallet")
        XCTAssertEqual(descriptor?.iosTeamId, "TEAM")
        XCTAssertNil(host.consumePendingProviderInstall())
    }

    func testProviderInstallPendingGetAndClearMirrorFlutterChannelLifecycle() {
        let host = NapaxiAgentProviderHost(callbackScheme: "napaxi-test")
        let url = URL(string: "napaxi-test://provider?install_url=https%3A%2F%2Fwallet.example%2Finstall&label=Wallet")!

        XCTAssertTrue(host.handleOpenURL(url))
        XCTAssertEqual(host.getPendingProviderInstallRequest()?.label, "Wallet")
        XCTAssertEqual(host.getPendingProviderInstallRequest()?.label, "Wallet")

        host.clearPendingProviderInstallRequest()
        XCTAssertNil(host.getPendingProviderInstallRequest())
    }

    func testTriggerRequestFromURL() {
        let host = NapaxiAgentProviderHost()
        let url = URL(string: "napaxi://provider?trigger_request=%7B%22request_id%22%3A%22r1%22%7D")!

        XCTAssertTrue(host.handleOpenURL(url))
        XCTAssertEqual(host.getPendingAgentTriggerRequestJSON(), #"{"request_id":"r1"}"#)
        XCTAssertEqual(host.consumePendingTriggerRequestJSON(), #"{"request_id":"r1"}"#)
        XCTAssertNil(host.consumePendingTriggerRequestJSON())
    }

    func testTriggerPendingGetAndClearMirrorFlutterChannelLifecycle() throws {
        let host = NapaxiAgentProviderHost()
        let url = URL(string: "napaxi://provider?trigger_request=%7B%22request_id%22%3A%22r1%22%7D")!

        XCTAssertTrue(host.handleOpenURL(url))
        XCTAssertEqual(try host.getPendingAgentTriggerRequest()?.requestId, "r1")
        XCTAssertEqual(try host.getPendingAgentTriggerRequest()?.requestId, "r1")

        host.clearPendingAgentTriggerRequest()
        XCTAssertNil(host.getPendingAgentTriggerRequestJSON())
        XCTAssertNil(try host.getPendingAgentTriggerRequest())
    }

    func testProviderAPIKeepsPendingTriggerUntilAcceptedLikeFlutter() throws {
        let host = NapaxiAgentProviderHost()
        var request = signedTrigger(expiresAt: "2030-01-01T00:00:00Z")
        request.signature = NapaxiAgentProviderHost.triggerSignature(for: request, hostSharedSecret: "secret")
        let url = URL(string: "napaxi://provider?trigger_request=\(urlEncoded(try request.toJsonString()))")!
        XCTAssertTrue(host.handleOpenURL(url))
        let api = NapaxiAgentProviderAPI(
            host: host,
            registerPackage: { try NapaxiRawJSON(jsonString: $0).value },
            getPackage: { _ in
                .object(installedPackage(
                    providerId: "wallet",
                    agentId: "wallet-agent",
                    hostInstanceId: "host-1",
                    secret: "secret"
                ))
            }
        )

        let first = try api.consumePendingTrigger()
        let second = try api.consumePendingTrigger()

        XCTAssertEqual(first?.requestId, "trigger-1")
        XCTAssertEqual(second?.requestId, "trigger-1")
        XCTAssertNotNil(host.pendingTriggerRequestJSON)

        let accepted = try api.acceptTrigger(request, now: Date(timeIntervalSince1970: 1_767_225_600))
        XCTAssertEqual(accepted.displayName, "Wallet")
        XCTAssertNil(host.pendingTriggerRequestJSON)
        XCTAssertNil(try api.consumePendingTrigger())
    }

    func testProviderDescriptorDecodesFlutterDefaults() throws {
        let json = #"{"packageName":"com.example.wallet","activityName":"InstallActivity"}"#
        let constructed = NapaxiAgentProviderDescriptor(
            packageName: "com.example.wallet",
            installActivityName: "InstallActivity",
            activityName: "InstallActivity",
            label: ""
        )
        let descriptor = try JSONDecoder().decode(
            NapaxiAgentProviderDescriptor.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(constructed.platform, "android")
        XCTAssertEqual(descriptor.platform, "android")
        XCTAssertEqual(descriptor.packageName, "com.example.wallet")
        XCTAssertEqual(descriptor.installActivityName, "InstallActivity")
        XCTAssertEqual(descriptor.activityName, "InstallActivity")
        XCTAssertEqual(descriptor.label, "")
        XCTAssertEqual(descriptor.signingCertSha256, "")
        XCTAssertEqual(descriptor.installUrl, "")
        XCTAssertEqual(descriptor.iosBundleId, "")
    }

    func testAgentProviderMapHelpersMirrorFlutterModels() throws {
        let descriptor = AgentProviderDescriptor.fromMap([
            "packageName": .string("com.example.wallet"),
            "activityName": .string("InstallActivity"),
            "label": .string("Wallet"),
            "installUrl": .string("https://wallet.example/install"),
            "iosBundleId": .string("com.example.wallet"),
        ])
        XCTAssertEqual(descriptor.platform, "android")
        XCTAssertEqual(descriptor.installActivityName, "InstallActivity")
        XCTAssertEqual(descriptor.activityName, "InstallActivity")
        XCTAssertEqual(descriptor.toJson()["installUrl"], .string("https://wallet.example/install"))
        XCTAssertEqual(descriptor.toJson()["actionUrl"], nil)

        let installRequest = AgentInstallRequest.fromMap([
            "protocol_version": .number(2),
            "request_id": .string("install-1"),
            "nonce": .string("n"),
            "host_package_name": .string("host"),
            "created_at": .string("2026-01-01T00:00:00Z"),
            "expires_at": .string("2026-01-01T00:10:00Z"),
            "host_instance_id": .string("host-1"),
            "host_shared_secret": .string("secret"),
            "background_trigger_supported": .bool(true),
        ])
        let installJSON = try NapaxiRawJSON(jsonString: installRequest.toJsonString()).value
        XCTAssertEqual(installRequest.protocolVersion, 2)
        XCTAssertEqual(installRequest.hostPackageName, "host")
        XCTAssertEqual(installRequest.toJson()["background_trigger_supported"], .bool(true))
        XCTAssertEqual(installJSON.objectValue?["request_id"], .string("install-1"))

        let trigger = try AgentTriggerRequest.fromJsonString("""
        {
          "request_id": "trigger-1",
          "provider_id": "wallet",
          "agent_id": "wallet-agent",
          "message": "hello",
          "payload": {"kind": "push"},
          "created_at": "2026-01-01T00:00:00Z",
          "expires_at": "2026-01-01T00:10:00Z",
          "nonce": "n",
          "idempotency_key": "idem",
          "signature_algorithm": "hmac-sha256-v1",
          "signature": "sig"
        }
        """)
        XCTAssertEqual(trigger.protocolVersion, 2)
        XCTAssertEqual(trigger.payload["kind"], .string("push"))
        XCTAssertEqual(trigger.toJson()["signature"], .string("sig"))
        XCTAssertEqual(try NapaxiRawJSON(jsonString: trigger.toJsonString()).value.objectValue?["provider_id"], .string("wallet"))

        let result = AgentInstallResult.fromMap([
            "status": .string("failed"),
            "request_id": .string("install-1"),
            "nonce": .string("n"),
            "error": .object(["message": .string("Denied")]),
            "completed_at": .string("2026-01-01T00:00:00Z"),
        ])
        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.errorMessage, "Denied")
    }

    func testAgentProviderCodableEncodingUsesFlutterMapShape() throws {
        let descriptor = AgentProviderDescriptor.fromMap([
            "packageName": .string("com.example.wallet"),
            "activityName": .string("InstallActivity"),
            "label": .string("Wallet"),
        ])
        let descriptorJSON = try NapaxiRawJSON(data: JSONEncoder().encode(descriptor)).value.objectValue
        XCTAssertEqual(descriptorJSON?["packageName"], .string("com.example.wallet"))
        XCTAssertEqual(descriptorJSON?["installActivityName"], .string("InstallActivity"))
        XCTAssertNil(descriptorJSON?["installUrl"])
        XCTAssertNil(descriptorJSON?["iosBundleId"])

        let installRequest = AgentInstallRequest(
            requestId: "install-1",
            nonce: "n",
            hostPackageName: "host",
            createdAt: "2026-01-01T00:00:00Z",
            expiresAt: "2026-01-01T00:10:00Z",
            hostInstanceId: "host-1",
            hostSharedSecret: "secret"
        )
        let installJSON = try NapaxiRawJSON(data: JSONEncoder().encode(installRequest)).value.objectValue
        XCTAssertEqual(installRequest.protocolVersion, 1)
        XCTAssertEqual(installJSON?["request_id"], .string("install-1"))
        XCTAssertEqual(installJSON?["protocol_version"], .number(1))
        XCTAssertEqual(installJSON?["host_instance_id"], .string("host-1"))
        XCTAssertNil(installJSON?["host_bundle_id"])
        XCTAssertNil(installJSON?["background_trigger_supported"])

        let trigger = AgentTriggerRequest(
            requestId: "trigger-1",
            providerId: "wallet",
            agentId: "wallet-agent",
            message: "hello",
            createdAt: "2026-01-01T00:00:00Z",
            expiresAt: "2026-01-01T00:10:00Z",
            nonce: "n",
            idempotencyKey: "idem"
        )
        let triggerJSON = try NapaxiRawJSON(data: JSONEncoder().encode(trigger)).value.objectValue
        XCTAssertEqual(triggerJSON?["provider_id"], .string("wallet"))
        XCTAssertEqual(triggerJSON?["payload"], .object([:]))
        XCTAssertNil(triggerJSON?["host_instance_id"])
        XCTAssertNil(triggerJSON?["signature_algorithm"])
        XCTAssertNil(triggerJSON?["signature"])
    }

    func testInstallAndTriggerRequestsDecodeFlutterDefaults() throws {
        let installRequest = try JSONDecoder().decode(
            NapaxiAgentInstallRequest.self,
            from: Data(#"{"request_id":"install-1","nonce":"n"}"#.utf8)
        )
        let installFromMap = AgentInstallRequest.fromMap([
            "protocol_version": .string("2"),
            "request_id": .string("install-map"),
            "nonce": .string("n"),
        ])
        let triggerRequest = try NapaxiAgentTriggerRequest(
            jsonString: #"{"request_id":"trigger-1","provider_id":"wallet","agent_id":"wallet-agent"}"#
        )
        let triggerWithStringVersion = try AgentTriggerRequest.fromJsonString(
            #"{"protocol_version":"3","request_id":"trigger-string","provider_id":"wallet","agent_id":"wallet-agent","payload":"ignored"}"#
        )

        XCTAssertEqual(installRequest.protocolVersion, 1)
        XCTAssertEqual(installRequest.requestId, "install-1")
        XCTAssertEqual(installRequest.nonce, "n")
        XCTAssertEqual(installRequest.hostPackageName, "")
        XCTAssertFalse(installRequest.backgroundTriggerSupported)
        XCTAssertEqual(installFromMap.protocolVersion, 1)
        XCTAssertEqual(triggerRequest.protocolVersion, 2)
        XCTAssertEqual(triggerRequest.requestId, "trigger-1")
        XCTAssertEqual(triggerRequest.providerId, "wallet")
        XCTAssertEqual(triggerRequest.message, "")
        XCTAssertEqual(triggerRequest.payload, [:])
        XCTAssertEqual(triggerWithStringVersion.protocolVersion, 2)
        XCTAssertEqual(triggerWithStringVersion.requestId, "trigger-string")
        XCTAssertEqual(triggerWithStringVersion.payload, [:])
    }

    func testInstallTimeoutMirrorsFlutterDefault() {
        XCTAssertEqual(NapaxiAgentProviderHost.defaultInstallTimeoutSeconds, 10 * 60)
        XCTAssertEqual(
            NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds,
            NapaxiAgentProviderHost.defaultInstallTimeoutSeconds
        )
    }

    func testInstallURLCarriesProtocolRequest() throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(
            bundleId: "com.example.host",
            teamId: "TEAM",
            callbackScheme: "napaxi-host"
        ))
        let provider = NapaxiAgentProviderDescriptor(
            label: "Wallet",
            installUrl: "https://wallet.example/install",
            actionUrl: "https://wallet.example/action",
            universalLinkDomain: "wallet.example",
            iosBundleId: "com.example.wallet",
            iosTeamId: "PROVIDERTEAM"
        )

        let request = host.createInstallRequest(now: Date(timeIntervalSince1970: 0))
        let url = try host.installURL(for: provider, request: request)
        let requestJSON = try XCTUnwrap(queryValue("install_request", in: url))
        let decoded = try JSONDecoder().decode(
            NapaxiAgentInstallRequest.self,
            from: Data(requestJSON.utf8)
        )

        XCTAssertEqual(decoded.protocolVersion, 2)
        XCTAssertEqual(decoded.hostPackageName, "com.example.host")
        XCTAssertEqual(decoded.hostBundleId, "com.example.host")
        XCTAssertEqual(decoded.hostTeamId, "TEAM")
        XCTAssertEqual(decoded.hostCallbackScheme, "napaxi-host")
        XCTAssertEqual(decoded.callbackUrl, "napaxi-host://agent-provider/install-callback")
    }

    func testInstallCallbackCreatesIosBinding() async throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(
            bundleId: "com.example.host",
            teamId: "HOSTTEAM",
            callbackScheme: "napaxi-host"
        ))
        let provider = NapaxiAgentProviderDescriptor(
            label: "Wallet",
            installUrl: "https://wallet.example/install",
            actionUrl: "https://wallet.example/action",
            universalLinkDomain: "wallet.example",
            iosBundleId: "com.example.wallet",
            iosTeamId: "PROVIDERTEAM"
        )
        let handoff = LockedURLBox()
        let task = Task {
            try await host.requestInstall(provider: provider) { url in
                handoff.value = url
                return true
            }
        }
        while handoff.value == nil {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let requestJSON = try XCTUnwrap(queryValue("install_request", in: handoff.value!))
        let request = try JSONDecoder().decode(NapaxiAgentInstallRequest.self, from: Data(requestJSON.utf8))
        let resultJSON = #"{"status":"succeeded","request_id":"\#(request.requestId)","nonce":"\#(request.nonce)","package":{"provider_id":"wallet","agent_id":"wallet-agent"},"completed_at":"1970-01-01T00:00:00Z"}"#
        let callback = URL(string: "napaxi-host://agent-provider/install-callback?install_result=\(urlEncoded(resultJSON))")!

        XCTAssertTrue(host.handleOpenURL(callback))
        let response = try await task.value

        XCTAssertEqual(response.installResultJSON, resultJSON)
        XCTAssertEqual(response.installBinding["platform"], .string("ios"))
        XCTAssertEqual(response.installBinding["ios_bundle_id"], .string("com.example.wallet"))
        XCTAssertEqual(response.installBinding["ios_team_id"], .string("PROVIDERTEAM"))
        XCTAssertEqual(response.installBinding["host_bundle_id"], .string("com.example.host"))
        XCTAssertEqual(response.installBinding["host_team_id"], .string("HOSTTEAM"))
        XCTAssertEqual(response.installBinding["host_callback_scheme"], .string("napaxi-host"))
        XCTAssertEqual(response.installBinding["host_instance_id"], .string(request.hostInstanceId))
        XCTAssertEqual(response.installBinding["host_shared_secret"], .string(request.hostSharedSecret))
    }

    func testInstallResponseCodableUsesFlutterPlatformChannelShape() throws {
        let resultJSON = #"{"status":"succeeded","request_id":"install-1"}"#
        let response = NapaxiAgentProviderInstallResponse(
            installResultJson: resultJSON,
            installBinding: ["platform": .string("ios")]
        )

        let encoded = try JSONEncoder().encode(response)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(decoded["installResultJson"] as? String, resultJSON)
        XCTAssertEqual((decoded["installBinding"] as? [String: Any])?["platform"] as? String, "ios")
        XCTAssertNil(decoded["installResultJSON"])

        let decodedResponse = try JSONDecoder().decode(
            NapaxiAgentProviderInstallResponse.self,
            from: Data(#"{"installResultJson":"{\"status\":\"succeeded\"}","installBinding":{"platform":"ios"}}"#.utf8)
        )
        XCTAssertEqual(decodedResponse.installResultJson, #"{"status":"succeeded"}"#)
        XCTAssertEqual(decodedResponse.installResultJSON, #"{"status":"succeeded"}"#)
        XCTAssertEqual(decodedResponse.installBinding["platform"], .string("ios"))
    }

    func testInstallResultPublicModelParsesProviderPayload() throws {
        let result = try NapaxiAgentInstallResult(
            jsonString: #"{"status":"failed","request_id":"install-1","nonce":"n","package":{"provider_id":"wallet","agent_id":"wallet-agent"},"error":{"message":"Denied"},"completed_at":"1970-01-01T00:00:00Z"}"#
        )

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.requestId, "install-1")
        XCTAssertEqual(result.nonce, "n")
        XCTAssertEqual(result.package?.providerId, "wallet")
        XCTAssertEqual(result.packageRaw?["agent_id"], .string("wallet-agent"))
        XCTAssertEqual(result.error?["message"], .string("Denied"))
        XCTAssertEqual(result.errorMessage, "Denied")
        XCTAssertEqual(result.completedAt, "1970-01-01T00:00:00Z")
    }

    func testProviderAPIRegistersReturnedPackageWithInstallBinding() async throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(
            bundleId: "com.example.host",
            teamId: "HOSTTEAM",
            callbackScheme: "napaxi-host"
        ))
        let provider = NapaxiAgentProviderDescriptor(
            label: "Wallet",
            installUrl: "https://wallet.example/install",
            actionUrl: "https://wallet.example/action",
            universalLinkDomain: "wallet.example",
            iosBundleId: "com.example.wallet",
            iosTeamId: "PROVIDERTEAM"
        )
        let handoff = LockedURLBox()
        let registered = LockedJSONBox()
        let api = NapaxiAgentProviderAPI(
            host: host,
            registerPackage: { packageJSON in
                registered.value = packageJSON
                return try NapaxiRawJSON(jsonString: packageJSON).value
            },
            getPackage: { _ in nil },
            openURL: { url in
                handoff.value = url
                return true
            }
        )

        let task = Task {
            try await api.requestInstallJSON(provider)
        }
        while handoff.value == nil {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let requestJSON = try XCTUnwrap(queryValue("install_request", in: handoff.value!))
        let request = try JSONDecoder().decode(NapaxiAgentInstallRequest.self, from: Data(requestJSON.utf8))
        let resultJSON = #"{"status":"succeeded","request_id":"\#(request.requestId)","nonce":"\#(request.nonce)","package":{"provider_id":"wallet","agent_id":"wallet-agent","display_name":"Wallet"},"completed_at":"1970-01-01T00:00:00Z"}"#
        let callback = URL(string: "napaxi-host://agent-provider/install-callback?install_result=\(urlEncoded(resultJSON))")!

        XCTAssertTrue(host.handleOpenURL(callback))
        let installed = try await task.value
        guard case .object(let installedObject) = installed,
              case .object(let binding)? = installedObject["install_binding"] else {
            return XCTFail("Expected installed package object with install binding")
        }

        XCTAssertEqual(installedObject["agent_id"], .string("wallet-agent"))
        XCTAssertEqual(binding["platform"], .string("ios"))
        XCTAssertEqual(binding["host_instance_id"], .string(request.hostInstanceId))
        XCTAssertEqual(binding["host_shared_secret"], .string(request.hostSharedSecret))
        XCTAssertTrue(registered.value?.contains("\"install_binding\"") == true)
    }

    func testInstallFromLaunchIntentClearsPendingOnlyAfterSuccessfulInstall() async throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(
            bundleId: "com.example.host",
            callbackScheme: "napaxi-host"
        ))
        let launch = URL(string: "napaxi-host://provider?install_url=https%3A%2F%2Fwallet.example%2Finstall&action_url=https%3A%2F%2Fwallet.example%2Faction&label=Wallet")!
        XCTAssertTrue(host.handleOpenURL(launch))

        let failingAPI = NapaxiAgentProviderAPI(
            host: host,
            registerPackage: { try NapaxiRawJSON(jsonString: $0).value },
            getPackage: { _ in nil },
            openURL: { _ in false }
        )

        do {
            _ = try await failingAPI.installFromLaunchIntentJSON(timeoutSeconds: 1)
            XCTFail("Expected failed handoff to throw")
        } catch {
            XCTAssertEqual(error as? NapaxiError, .invalidState("Unable to open provider install URL"))
        }
        XCTAssertEqual(host.pendingProviderInstall?.label, "Wallet")

        let handoff = LockedURLBox()
        let succeedingAPI = NapaxiAgentProviderAPI(
            host: host,
            registerPackage: { try NapaxiRawJSON(jsonString: $0).value },
            getPackage: { _ in nil },
            openURL: { url in
                handoff.value = url
                return true
            }
        )

        let task = Task {
            try await succeedingAPI.installFromLaunchIntentJSON(timeoutSeconds: 1)
        }
        while handoff.value == nil {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let requestJSON = try XCTUnwrap(queryValue("install_request", in: handoff.value!))
        let request = try JSONDecoder().decode(NapaxiAgentInstallRequest.self, from: Data(requestJSON.utf8))
        let resultJSON = #"{"status":"succeeded","request_id":"\#(request.requestId)","nonce":"\#(request.nonce)","package":{"provider_id":"wallet","agent_id":"wallet-agent","display_name":"Wallet"},"completed_at":"1970-01-01T00:00:00Z"}"#
        let callback = URL(string: "napaxi-host://agent-provider/install-callback?install_result=\(urlEncoded(resultJSON))")!

        XCTAssertTrue(host.handleOpenURL(callback))
        let installed = try await task.value
        XCTAssertEqual(installed?.objectValue?["agent_id"], .string("wallet-agent"))
        XCTAssertNil(host.pendingProviderInstall)
    }

    func testProviderAPITypedPackageConveniencesMirrorFlutterFacade() async throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(
            bundleId: "com.example.host",
            callbackScheme: "napaxi-host"
        ))
        let provider = NapaxiAgentProviderDescriptor(
            label: "Wallet",
            installUrl: "https://wallet.example/install",
            actionUrl: "https://wallet.example/action",
            universalLinkDomain: "wallet.example"
        )
        let handoff = LockedURLBox()
        let package = installedPackage(providerId: "wallet", agentId: "wallet-agent", hostInstanceId: "host-1", secret: "secret")
        let api = NapaxiAgentProviderAPI(
            host: host,
            registerPackage: { try NapaxiRawJSON(jsonString: $0).value },
            getPackage: { _ in .object(package) },
            openURL: { url in
                handoff.value = url
                return true
            }
        )

        let task = Task {
            try await api.requestInstall(provider)
        }
        while handoff.value == nil {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let requestJSON = try XCTUnwrap(queryValue("install_request", in: handoff.value!))
        let request = try JSONDecoder().decode(NapaxiAgentInstallRequest.self, from: Data(requestJSON.utf8))
        let resultJSON = #"{"status":"succeeded","request_id":"\#(request.requestId)","nonce":"\#(request.nonce)","package":{"provider_id":"wallet","agent_id":"wallet-agent","display_name":"Wallet"},"completed_at":"1970-01-01T00:00:00Z"}"#
        let callback = URL(string: "napaxi-host://agent-provider/install-callback?install_result=\(urlEncoded(resultJSON))")!

        XCTAssertTrue(host.handleOpenURL(callback))
        let installed = try await task.value
        XCTAssertEqual(installed.agentId, "wallet-agent")
        XCTAssertEqual(installed.installBinding?.platform, "ios")

        let requestInstallPackage: (NapaxiAgentProviderAPI, NapaxiAgentProviderDescriptor) async throws -> NapaxiAgentAppPackage = { api, provider in
            try await api.requestInstallPackage(provider)
        }
        let installFromLaunchIntent: (NapaxiAgentProviderAPI) async throws -> NapaxiAgentAppPackage? = { api in
            try await api.installFromLaunchIntent()
        }
        let installPackageFromLaunchIntent: (NapaxiAgentProviderAPI) async throws -> NapaxiAgentAppPackage? = { api in
            try await api.installPackageFromLaunchIntent()
        }
        let requestInstallJSON: (NapaxiAgentProviderAPI, NapaxiAgentProviderDescriptor) async throws -> NapaxiJSONValue = { api, provider in
            try await api.requestInstallJSON(provider)
        }
        let installFromLaunchIntentJSON: (NapaxiAgentProviderAPI) async throws -> NapaxiJSONValue? = { api in
            try await api.installFromLaunchIntentJSON()
        }

        XCTAssertNotNil(requestInstallPackage)
        XCTAssertNotNil(installFromLaunchIntent)
        XCTAssertNotNil(installPackageFromLaunchIntent)
        XCTAssertNotNil(requestInstallJSON)
        XCTAssertNotNil(installFromLaunchIntentJSON)

        var trigger = signedTrigger(expiresAt: "2030-01-01T00:00:00Z")
        trigger.signature = NapaxiAgentProviderHost.triggerSignature(for: trigger, hostSharedSecret: "secret")
        let validated = try api.validateTriggerPackage(
            trigger,
            now: Date(timeIntervalSince1970: 1_767_225_600)
        )
        XCTAssertEqual(validated.displayName, "Wallet")
        XCTAssertNil(try api.consumePendingTrigger())
    }

    func testInstallCallbackRejectsMismatchedNonce() async throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(callbackScheme: "napaxi-host"))
        let provider = NapaxiAgentProviderDescriptor(
            label: "Wallet",
            installUrl: "https://wallet.example/install",
            actionUrl: "https://wallet.example/action",
            universalLinkDomain: "wallet.example"
        )
        let handoff = LockedURLBox()
        let task = Task {
            try await host.requestInstall(provider: provider) { url in
                handoff.value = url
                return true
            }
        }
        while handoff.value == nil {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let requestJSON = try XCTUnwrap(queryValue("install_request", in: handoff.value!))
        let request = try JSONDecoder().decode(NapaxiAgentInstallRequest.self, from: Data(requestJSON.utf8))
        let resultJSON = #"{"status":"succeeded","request_id":"\#(request.requestId)","nonce":"wrong","package":{"provider_id":"wallet","agent_id":"wallet-agent"},"completed_at":"1970-01-01T00:00:00Z"}"#
        let callback = URL(string: "napaxi-host://agent-provider/install-callback?install_result=\(urlEncoded(resultJSON))")!

        XCTAssertTrue(host.handleOpenURL(callback))
        do {
            _ = try await task.value
            XCTFail("Expected mismatched nonce to fail")
        } catch {
            XCTAssertEqual(error as? NapaxiError, .invalidState("Install result does not match the request"))
        }
    }

    func testActionURLSanitizesHostSecretAndAddsCallback() throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(callbackScheme: "napaxi-host"))
        let requestJSON = try jsonString([
            "proposal": [
                "request_id": "req-1",
                "provider_id": "wallet",
                "agent_id": "wallet-agent",
                "action_id": "pay",
                "tool_name": "app_action_pay",
                "created_at": "1970-01-01T00:00:00Z",
                "expires_at": "1970-01-01T00:10:00Z",
                "nonce": "n",
                "idempotency_key": "idem",
            ],
            "action": [
                "action_id": "pay",
                "tool_name": "app_action_pay",
                "description": "Pay",
            ],
            "package": [
                "provider_id": "wallet",
                "agent_id": "wallet-agent",
                "install_binding": [
                    "platform": "ios",
                    "action_url": "https://wallet.example/action",
                    "host_callback_scheme": "napaxi-host",
                    "host_shared_secret": "secret",
                ],
            ],
        ])

        let url = try host.actionURL(requestJSON: requestJSON)
        let packageJSON = try XCTUnwrap(queryValue("package", in: url))
        let callbackURL = try XCTUnwrap(queryValue("callback_url", in: url))

        XCTAssertFalse(packageJSON.contains("secret"))
        XCTAssertEqual(callbackURL, "napaxi-host://agent-provider/action-callback?request_id=req-1")
        XCTAssertNotNil(queryValue("proposal", in: url))
        XCTAssertNotNil(queryValue("action", in: url))
    }

    func testActionCallbackCompletesPendingExecution() async throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(callbackScheme: "napaxi-host"))
        let requestJSON = try jsonString([
            "proposal": [
                "request_id": "req-2",
                "provider_id": "wallet",
                "agent_id": "wallet-agent",
                "action_id": "pay",
                "tool_name": "app_action_pay",
                "created_at": "1970-01-01T00:00:00Z",
                "expires_at": "1970-01-01T00:10:00Z",
                "nonce": "n",
                "idempotency_key": "idem",
            ],
            "action": ["action_id": "pay", "tool_name": "app_action_pay", "description": "Pay"],
            "package": [
                "provider_id": "wallet",
                "agent_id": "wallet-agent",
                "install_binding": [
                    "platform": "ios",
                    "action_url": "https://wallet.example/action",
                    "host_callback_scheme": "napaxi-host",
                ],
            ],
        ])
        let resultJSON = #"{"request_id":"req-2","status":"succeeded","result":{"ok":true},"completed_at":"1970-01-01T00:00:00Z"}"#

        let task = Task {
            await host.executeProviderAction(requestJSON: requestJSON) { _ in
                Task {
                    let callback = URL(string: "napaxi-host://agent-provider/action-callback?result=\(urlEncoded(resultJSON))")!
                    _ = host.handleOpenURL(callback)
                }
                return true
            }
        }

        let actionResult = await task.value
        XCTAssertEqual(actionResult, resultJSON)
    }

    func testActionCallbackWithoutResultCompletesWithFlutterFailureShape() async throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(callbackScheme: "napaxi-host"))
        let requestJSON = try jsonString([
            "proposal": [
                "request_id": "req-empty-result",
                "provider_id": "wallet",
                "agent_id": "wallet-agent",
                "action_id": "pay",
                "tool_name": "app_action_pay",
                "created_at": "1970-01-01T00:00:00Z",
                "expires_at": "1970-01-01T00:10:00Z",
                "nonce": "n",
                "idempotency_key": "idem",
            ],
            "action": ["action_id": "pay", "tool_name": "app_action_pay", "description": "Pay"],
            "package": [
                "provider_id": "wallet",
                "agent_id": "wallet-agent",
                "install_binding": [
                    "platform": "ios",
                    "action_url": "https://wallet.example/action",
                    "host_callback_scheme": "napaxi-host",
                ],
            ],
        ])

        let task = Task {
            await host.executeProviderAction(requestJSON: requestJSON) { _ in
                Task {
                    let callback = URL(string: "napaxi-host://agent-provider/action-callback")!
                    _ = host.handleOpenURL(callback)
                }
                return true
            }
        }

        let actionResult = try NapaxiAgentAppActionResult.fromMap(
            NapaxiRawJSON(jsonString: await task.value).value.objectValue ?? [:]
        )
        XCTAssertEqual(actionResult.requestId, "req-empty-result")
        XCTAssertEqual(actionResult.status, "failed")
        XCTAssertEqual(actionResult.error, "Provider action returned no result")
    }

    func testProviderActionValidationFailuresMirrorFlutterMessages() async throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(callbackScheme: "napaxi-host"))
        func result(for binding: [String: Any]) async throws -> NapaxiAgentAppActionResult {
            let requestJSON = try jsonString([
                "proposal": [
                    "request_id": "req-invalid-action",
                    "provider_id": "wallet",
                    "agent_id": "wallet-agent",
                    "action_id": "pay",
                    "tool_name": "app_action_pay",
                    "created_at": "1970-01-01T00:00:00Z",
                    "expires_at": "1970-01-01T00:10:00Z",
                    "nonce": "n",
                    "idempotency_key": "idem",
                ],
                "action": ["action_id": "pay", "tool_name": "app_action_pay", "description": "Pay"],
                "package": [
                    "provider_id": "wallet",
                    "agent_id": "wallet-agent",
                    "install_binding": binding,
                ],
            ])
            let raw = await host.executeProviderAction(requestJSON: requestJSON) { _ in
                XCTFail("Invalid action requests should not open a provider URL")
                return true
            }
            return NapaxiAgentAppActionResult.fromMap(
                try NapaxiRawJSON(jsonString: raw).value.objectValue ?? [:]
            )
        }

        let wrongPlatform = try await result(for: [
            "platform": "android",
            "action_url": "https://wallet.example/action",
            "host_callback_scheme": "napaxi-host",
        ])
        let missingActionURL = try await result(for: [
            "platform": "ios",
            "host_callback_scheme": "napaxi-host",
        ])

        XCTAssertEqual(wrongPlatform.status, "failed")
        XCTAssertEqual(wrongPlatform.error, "Provider action package is not installed with an iOS binding")
        XCTAssertEqual(missingActionURL.status, "failed")
        XCTAssertEqual(missingActionURL.error, "Provider action binding is missing action_url")
    }

    func testProviderActionExecutorUsesHostHandoff() async throws {
        let host = NapaxiAgentProviderHost(hostInfo: NapaxiAgentProviderHostInfo(callbackScheme: "napaxi-host"))
        let requestJSON = try jsonString([
            "proposal": [
                "request_id": "req-3",
                "provider_id": "wallet",
                "agent_id": "wallet-agent",
                "action_id": "pay",
                "tool_name": "app_action_pay",
                "created_at": "1970-01-01T00:00:00Z",
                "expires_at": "1970-01-01T00:10:00Z",
                "nonce": "n",
                "idempotency_key": "idem",
            ],
            "action": ["action_id": "pay", "tool_name": "app_action_pay", "description": "Pay"],
            "package": [
                "provider_id": "wallet",
                "agent_id": "wallet-agent",
                "install_binding": [
                    "platform": "ios",
                    "action_url": "https://wallet.example/action",
                    "host_callback_scheme": "napaxi-host",
                ],
            ],
        ])
        let resultJSON = #"{"request_id":"req-3","status":"succeeded","result":{"ok":true},"completed_at":"1970-01-01T00:00:00Z"}"#
        let executor = NapaxiAgentProviderActionExecutor(host: host) { _ in
            Task {
                let callback = URL(string: "napaxi-host://agent-provider/action-callback?result=\(urlEncoded(resultJSON))")!
                _ = host.handleOpenURL(callback)
            }
            return true
        }

        let actionResult = await executor.executeAgentAppAction(requestJSON: requestJSON)
        XCTAssertEqual(actionResult, resultJSON)

        let typedExecutor: AgentAppActionExecutor = executor
        let typedRequest = try JSONDecoder().decode(NapaxiAgentAppActionRequest.self, from: Data(requestJSON.utf8))
        let typedResult = try await typedExecutor.execute(typedRequest)
        XCTAssertEqual(typedResult.requestId, "req-3")
        XCTAssertEqual(typedResult.status, "succeeded")
    }

    func testAgentProviderFlutterNamedAliasesAndRequestHelper() throws {
        let host = NapaxiAgentProviderHost()
        let api: AgentProviderInstallApi = NapaxiAgentProviderAPI(
            host: host,
            registerPackage: { try NapaxiRawJSON(jsonString: $0).value },
            getPackage: { _ in nil }
        )
        let triggerApi: AgentProviderTriggerApi = api
        let executorType: IosAgentProviderActionExecutor.Type = NapaxiAgentProviderActionExecutor.self
        let androidExecutorType: AndroidAgentProviderActionExecutor.Type = NapaxiAgentProviderActionExecutor.self
        let request = NapaxiAgentAppActionRequest(
            proposal: NapaxiAgentAppActionProposal(
                requestId: "req-4",
                providerId: "wallet",
                agentId: "wallet-agent",
                actionId: "pay",
                toolName: "app_action_pay",
                createdAt: "1970-01-01T00:00:00Z",
                expiresAt: "1970-01-01T00:10:00Z",
                nonce: "n",
                idempotencyKey: "idem"
            ),
            action: NapaxiAgentAppActionManifest(
                actionId: "pay",
                toolName: "app_action_pay",
                description: "Pay"
            ),
            package: ["agent_id": .string("wallet-agent")]
        )

        let json: NapaxiJSONValue = try NapaxiRawJSON(jsonString: agentProviderRequestToJson(request)).value

        XCTAssertNotNil(triggerApi)
        XCTAssertNotNil(executorType)
        XCTAssertNotNil(androidExecutorType)
        XCTAssertNil(try api.consumePendingTrigger())
        XCTAssertEqual(json, .object([
            "proposal": .object(request.proposal.raw),
            "action": .object(request.action.raw),
            "package": .object(["agent_id": .string("wallet-agent")]),
        ]))
    }

    func testValidateAndAcceptSignedTrigger() throws {
        let host = NapaxiAgentProviderHost()
        let expiresAt = "2030-01-01T00:00:00Z"
        var request = signedTrigger(expiresAt: expiresAt)
        request.signature = NapaxiAgentProviderHost.triggerSignature(for: request, hostSharedSecret: "secret")

        let package = installedPackage(providerId: "wallet", agentId: "wallet-agent", hostInstanceId: "host-1", secret: "secret")
        let accepted = try host.acceptTrigger(
            request,
            installedPackage: package,
            now: Date(timeIntervalSince1970: 1_767_225_600)
        )

        XCTAssertEqual(accepted.request.requestId, "trigger-1")
        XCTAssertEqual(accepted.displayName, "Wallet")
        XCTAssertThrowsError(try host.validateTrigger(
            request,
            installedPackage: package,
            now: Date(timeIntervalSince1970: 1_767_225_600)
        )) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("Agent trigger has already been consumed"))
        }
    }

    func testAcceptedTriggersPersistAcrossHostsLikeFlutterPreferences() throws {
        let suiteName = "NapaxiAgentProviderHostTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removeObject(forKey: NapaxiAgentProviderHost.consumedTriggerRequestIdsKey)
        defer {
            defaults.removeObject(forKey: NapaxiAgentProviderHost.consumedTriggerRequestIdsKey)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let firstHost = NapaxiAgentProviderHost(consumedTriggerStore: defaults)
        let secondHost = NapaxiAgentProviderHost(consumedTriggerStore: defaults)
        var request = signedTrigger(expiresAt: "2030-01-01T00:00:00Z")
        request.signature = NapaxiAgentProviderHost.triggerSignature(for: request, hostSharedSecret: "secret")
        let package = installedPackage(
            providerId: "wallet",
            agentId: "wallet-agent",
            hostInstanceId: "host-1",
            secret: "secret"
        )

        _ = try firstHost.acceptTrigger(
            request,
            installedPackage: package,
            now: Date(timeIntervalSince1970: 1_767_225_600)
        )

        XCTAssertThrowsError(try secondHost.validateTrigger(
            request,
            installedPackage: package,
            now: Date(timeIntervalSince1970: 1_767_225_600)
        )) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("Agent trigger has already been consumed"))
        }
    }

    func testTriggerValidationRejectsInvalidSignature() throws {
        let host = NapaxiAgentProviderHost()
        var request = signedTrigger(expiresAt: "2030-01-01T00:00:00Z")
        request.signature = "bad"

        XCTAssertThrowsError(try host.validateTrigger(
            request,
            installedPackage: installedPackage(providerId: "wallet", agentId: "wallet-agent", hostInstanceId: "host-1", secret: "secret"),
            now: Date(timeIntervalSince1970: 1_767_225_600)
        )) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("Agent trigger signature is invalid"))
        }
    }

    func testTriggerValidationRejectsProviderMismatchAndExpiredRequest() throws {
        let host = NapaxiAgentProviderHost()
        var request = signedTrigger(expiresAt: "2030-01-01T00:00:00Z")
        request.signature = NapaxiAgentProviderHost.triggerSignature(for: request, hostSharedSecret: "secret")

        XCTAssertThrowsError(try host.validateTrigger(
            request,
            installedPackage: installedPackage(providerId: "other", agentId: "wallet-agent", hostInstanceId: "host-1", secret: "secret"),
            now: Date(timeIntervalSince1970: 1_767_225_600)
        )) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("Agent trigger provider does not match installed Agent"))
        }

        var expired = signedTrigger(expiresAt: "2020-01-01T00:00:00Z")
        expired.signature = NapaxiAgentProviderHost.triggerSignature(for: expired, hostSharedSecret: "secret")
        XCTAssertThrowsError(try host.validateTrigger(
            expired,
            installedPackage: installedPackage(providerId: "wallet", agentId: "wallet-agent", hostInstanceId: "host-1", secret: "secret"),
            now: Date(timeIntervalSince1970: 1_767_225_600)
        )) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("Agent trigger expired"))
        }
    }
}

private final class LockedURLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: URL?

    var value: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private final class LockedJSONBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String?

    var value: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private func queryValue(_ name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == name })?
        .value
}

private func urlEncoded(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
}

private func jsonString(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return String(data: data, encoding: .utf8) ?? "{}"
}

private func signedTrigger(expiresAt: String) -> NapaxiAgentTriggerRequest {
    NapaxiAgentTriggerRequest(
        requestId: "trigger-1",
        providerId: "wallet",
        agentId: "wallet-agent",
        message: "Pay Alice",
        source: "provider",
        eventType: "shortcut",
        payload: [
            "amount": .number(12),
            "memo": .string("lunch"),
        ],
        createdAt: "2026-01-01T00:00:00Z",
        expiresAt: expiresAt,
        nonce: "nonce-1",
        idempotencyKey: "idem-1",
        hostInstanceId: "host-1",
        signatureAlgorithm: NapaxiAgentProviderHost.triggerSignatureAlgorithm
    )
}

private func installedPackage(
    providerId: String,
    agentId: String,
    hostInstanceId: String,
    secret: String
) -> [String: NapaxiJSONValue] {
    [
        "provider_id": .string(providerId),
        "agent_id": .string(agentId),
        "display_name": .string("Wallet"),
        "install_binding": .object([
            "platform": .string("ios"),
            "host_instance_id": .string(hostInstanceId),
            "host_shared_secret": .string(secret),
        ]),
    ]
}
