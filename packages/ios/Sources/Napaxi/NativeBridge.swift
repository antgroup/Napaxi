import Foundation

#if os(iOS)
import NapaxiApiBridge
#endif

enum NapaxiNativeBridge {
    static func string(from pointer: UnsafeMutablePointer<CChar>?) throws -> String {
        guard let pointer else {
            throw NapaxiError.unavailable("Napaxi native bridge returned null")
        }
        #if os(iOS)
        defer { napaxi_api_string_free(pointer) }
        #endif
        return String(cString: pointer)
    }

    static func createEngine(configJSON: String, platformContextJSON: String) throws -> Int64 {
        #if os(iOS)
        let handle = configJSON.withCString { configPtr in
            platformContextJSON.withCString { contextPtr in
                napaxi_api_create_engine(configPtr, contextPtr)
            }
        }
        guard handle != 0 else {
            throw NapaxiError.nativeError(code: "create_engine_failed", message: "Failed to create Napaxi engine")
        }
        return handle
        #else
        throw NapaxiError.unavailable("Napaxi native engine is only available on iOS")
        #endif
    }

    static func updateConfig(handle: Int64, configJSON: String) throws -> Bool {
        #if os(iOS)
        return configJSON.withCString { napaxi_api_update_config(handle, $0) }
        #else
        throw NapaxiError.unavailable("Napaxi native engine is only available on iOS")
        #endif
    }

    static func getConfig(handle: Int64) throws -> NapaxiJSONValue {
        #if os(iOS)
        return try decodeEnvelope(string(from: napaxi_api_get_config(handle)))
        #else
        throw NapaxiError.unavailable("Napaxi native engine is only available on iOS")
        #endif
    }

    static func ensureAgentReady(handle: Int64, configJSON: String) throws -> Bool {
        #if os(iOS)
        return configJSON.withCString { napaxi_api_ensure_agent_ready(handle, $0) }
        #else
        throw NapaxiError.unavailable("Napaxi native engine is only available on iOS")
        #endif
    }

    static func disposeEngine(handle: Int64) {
        #if os(iOS)
        napaxi_api_dispose_engine(handle)
        #endif
    }

    static func call(handle: Int64, namespace: String, method: String, payload: [String: NapaxiJSONValue]) throws -> NapaxiJSONValue {
        #if os(iOS)
        let payloadJSON = try payload.jsonString()
        let raw = try namespace.withCString { namespacePtr in
            try method.withCString { methodPtr in
                try payloadJSON.withCString { payloadPtr in
                    try string(from: napaxi_api_call_json(handle, namespacePtr, methodPtr, payloadPtr))
                }
            }
        }
        return try decodeEnvelope(raw)
        #else
        throw NapaxiError.unavailable("Napaxi native engine is only available on iOS")
        #endif
    }

    static func sendMessage(handle: Int64, configJSON: String, message: String, attachmentsJSON: String, maxIterations: Int32) throws -> NapaxiJSONValue {
        #if os(iOS)
        let raw = try configJSON.withCString { configPtr in
            try message.withCString { messagePtr in
                try attachmentsJSON.withCString { attachmentsPtr in
                    try string(from: napaxi_api_send_message(handle, configPtr, messagePtr, attachmentsPtr, maxIterations))
                }
            }
        }
        return try decodeEnvelope(raw)
        #else
        throw NapaxiError.unavailable("Napaxi native engine is only available on iOS")
        #endif
    }

    static func sendToSession(handle: Int64, configJSON: String, agentId: String, sessionKeyJSON: String, message: String, attachmentsJSON: String, maxIterations: Int32) throws -> NapaxiJSONValue {
        #if os(iOS)
        let raw = try configJSON.withCString { configPtr in
            try agentId.withCString { agentPtr in
                try sessionKeyJSON.withCString { sessionPtr in
                    try message.withCString { messagePtr in
                        try attachmentsJSON.withCString { attachmentsPtr in
                            try string(from: napaxi_api_send_to_session(handle, configPtr, agentPtr, sessionPtr, messagePtr, attachmentsPtr, maxIterations))
                        }
                    }
                }
            }
        }
        return try decodeEnvelope(raw)
        #else
        throw NapaxiError.unavailable("Napaxi native engine is only available on iOS")
        #endif
    }

    static func sendMessageStream(
        handle: Int64,
        configJSON: String,
        message: String,
        attachmentsJSON: String,
        maxIterations: Int32
    ) -> AsyncThrowingStream<NapaxiChatEvent, Error> {
        AsyncThrowingStream { continuation in
            #if os(iOS)
            let box = NapaxiStreamBox(continuation: continuation)
            let opaque = Unmanaged.passRetained(box).toOpaque()
            Task.detached {
                let success = configJSON.withCString { configPtr in
                    message.withCString { messagePtr in
                        attachmentsJSON.withCString { attachmentsPtr in
                            napaxi_api_send_message_stream(
                                handle,
                                configPtr,
                                messagePtr,
                                attachmentsPtr,
                                maxIterations,
                                napaxiSwiftStreamCallback,
                                opaque
                            )
                        }
                    }
                }
                if !success {
                    continuation.finish(throwing: NapaxiError.nativeError(
                        code: "stream_failed",
                        message: "Napaxi stream call failed"
                    ))
                } else {
                    continuation.finish()
                }
                Unmanaged<NapaxiStreamBox>.fromOpaque(opaque).release()
            }
            #else
            continuation.finish(throwing: NapaxiError.unavailable("Napaxi streams are only available on iOS"))
            #endif
        }
    }

    static func sendToSessionStream(
        handle: Int64,
        configJSON: String,
        agentId: String,
        sessionKeyJSON: String,
        message: String,
        attachmentsJSON: String,
        maxIterations: Int32
    ) -> AsyncThrowingStream<NapaxiChatEvent, Error> {
        AsyncThrowingStream { continuation in
            #if os(iOS)
            let box = NapaxiStreamBox(continuation: continuation)
            let opaque = Unmanaged.passRetained(box).toOpaque()
            Task.detached {
                let success = configJSON.withCString { configPtr in
                    agentId.withCString { agentPtr in
                        sessionKeyJSON.withCString { sessionPtr in
                            message.withCString { messagePtr in
                                attachmentsJSON.withCString { attachmentsPtr in
                                    napaxi_api_send_to_session_stream(
                                        handle,
                                        configPtr,
                                        agentPtr,
                                        sessionPtr,
                                        messagePtr,
                                        attachmentsPtr,
                                        maxIterations,
                                        napaxiSwiftStreamCallback,
                                        opaque
                                    )
                                }
                            }
                        }
                    }
                }
                if !success {
                    continuation.finish(throwing: NapaxiError.nativeError(
                        code: "stream_failed",
                        message: "Napaxi session stream call failed"
                    ))
                } else {
                    continuation.finish()
                }
                Unmanaged<NapaxiStreamBox>.fromOpaque(opaque).release()
            }
            #else
            continuation.finish(throwing: NapaxiError.unavailable("Napaxi streams are only available on iOS"))
            #endif
        }
    }

    static func updateCustomTools(handle: Int64, toolsJSON: String) throws -> Bool {
        #if os(iOS)
        return toolsJSON.withCString { napaxi_api_update_custom_tools(handle, $0) }
        #else
        throw NapaxiError.unavailable("Napaxi native engine is only available on iOS")
        #endif
    }

    static func resolveToolExecution(requestId: UInt64, resultJSON: String, isError: Bool) throws -> Bool {
        #if os(iOS)
        return resultJSON.withCString { napaxi_api_resolve_tool_execution(requestId, $0, isError) }
        #else
        throw NapaxiError.unavailable("Napaxi native engine is only available on iOS")
        #endif
    }

    static func registerToolRequestRouter(_ router: NapaxiToolRequestRouter) throws -> Bool {
        #if os(iOS)
        let opaque = Unmanaged.passUnretained(router).toOpaque()
        return napaxi_api_register_tool_request_callback(napaxiSwiftToolRequestCallback, opaque)
        #else
        throw NapaxiError.unavailable("Napaxi tool routing is only available on iOS")
        #endif
    }

    static func clearToolRequestRouter() {
        #if os(iOS)
        napaxi_api_clear_tool_request_callback()
        #endif
    }

    static func registerIshRootfsArchive(path: String) {
        #if os(iOS)
        path.withCString { napaxi_api_ios_ish_register_rootfs_archive_path($0) }
        #endif
    }

    static func isIshReady(filesDir: String) -> Bool {
        #if os(iOS)
        filesDir.withCString { napaxi_api_ios_ish_is_ready($0) }
        #else
        false
        #endif
    }

    static func decodeEnvelope(_ raw: String) throws -> NapaxiJSONValue {
        let envelope: NapaxiAPIEnvelope
        do {
            envelope = try JSONDecoder().decode(NapaxiAPIEnvelope.self, from: Data(raw.utf8))
        } catch {
            throw NapaxiError.invalidJSON(raw)
        }
        if envelope.ok {
            return envelope.value ?? .null
        }
        let native = envelope.error
        throw NapaxiError.nativeError(
            code: native?.code ?? "native_error",
            message: native?.message ?? "Napaxi native call failed"
        )
    }
}

private final class NapaxiStreamBox: @unchecked Sendable {
    let continuation: AsyncThrowingStream<NapaxiChatEvent, Error>.Continuation

    init(continuation: AsyncThrowingStream<NapaxiChatEvent, Error>.Continuation) {
        self.continuation = continuation
    }
}

#if os(iOS)
private func napaxiSwiftStreamCallback(
    eventJSON: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) {
    guard let eventJSON, let userData else {
        return
    }
    let box = Unmanaged<NapaxiStreamBox>.fromOpaque(userData).takeUnretainedValue()
    let raw = String(cString: eventJSON)
    do {
        let value = try NapaxiRawJSON(jsonString: raw).value
        box.continuation.yield(NapaxiChatEvent(raw: value))
    } catch {
        box.continuation.finish(throwing: NapaxiError.invalidJSON(raw))
    }
}

private func napaxiSwiftToolRequestCallback(
    requestJSON: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) {
    guard let requestJSON, let userData else {
        return
    }
    let router = Unmanaged<NapaxiToolRequestRouter>.fromOpaque(userData).takeUnretainedValue()
    let raw = String(cString: requestJSON)
    Task {
        await router.handle(requestJSON: raw)
    }
}
#endif
