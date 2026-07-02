#[cfg(target_os = "android")]
mod android {
    use jni::objects::{GlobalRef, JClass, JObject, JString, JValue};
    use jni::sys::{JNI_FALSE, JNI_TRUE, jboolean, jint, jlong, jstring};
    use jni::{JNIEnv, JavaVM};
    use serde_json::json;
    use std::ptr;
    use std::sync::{Arc, Mutex, OnceLock};

    struct AndroidCallback {
        vm: JavaVM,
        callback: GlobalRef,
    }

    static TOOL_REQUEST_CALLBACK: OnceLock<Mutex<Option<AndroidCallback>>> = OnceLock::new();

    fn callback_slot() -> &'static Mutex<Option<AndroidCallback>> {
        TOOL_REQUEST_CALLBACK.get_or_init(|| Mutex::new(None))
    }

    fn jstring_to_string(env: &mut JNIEnv, value: JString) -> String {
        env.get_string(&value)
            .map(|s| s.into())
            .unwrap_or_else(|_| String::new())
    }

    fn string_to_jstring(env: &mut JNIEnv, value: String) -> jstring {
        env.new_string(value)
            .map(|s| s.into_raw())
            .unwrap_or(ptr::null_mut())
    }

    fn bool_to_jboolean(value: bool) -> jboolean {
        if value { JNI_TRUE } else { JNI_FALSE }
    }

    #[allow(dead_code)]
    const ANDROID_BRIDGE_METHODS: &[&str] = &[
        "agent.delete",
        "agent.send",
        "agent_app.accept_trigger",
        "agent_app.delete",
        "agent_app.get",
        "agent_app.get_proposal",
        "agent_app.list",
        "agent_app.list_proposals",
        "agent_app.register",
        "agent_app.submit_result",
        "a2a.accept_deep_link",
        "a2a.accept_peer_invite",
        "a2a.agent_card",
        "a2a.build_result_link",
        "a2a.create_peer_invite",
        "a2a.create_task_message",
        "a2a.create_task_progress_message",
        "a2a.create_task_result_message",
        "a2a.delete_peer",
        "a2a.get_task",
        "a2a.list_delivery_records",
        "a2a.list_peer_messages",
        "a2a.list_peer_sessions",
        "a2a.list_peers",
        "a2a.list_tasks",
        "a2a.open_peer_session",
        "a2a.record_delivery_status",
        "a2a.record_peer_message",
        "a2a.record_result",
        "a2a.run_task",
        "agent_engine.run_event",
        "agent_defs.create",
        "agent_defs.create_agent",
        "agent_defs.delete",
        "agent_defs.get",
        "agent_defs.import_md",
        "agent_defs.list",
        "agent_defs.list_available_tools",
        "agent_defs.update",
        "automation.create",
        "automation.delete",
        "automation.get",
        "automation.list",
        "automation.next_wake",
        "automation.record_wake",
        "automation.run",
        "automation.runs",
        "automation.update",
        "capability.definitions",
        "capability.agent_engine_id",
        "capability.install_scenario",
        "capability.provider_id",
        "capability.remove_scenario",
        "capability.scenario",
        "capability.scenario_status",
        "capability.scenarios",
        "capability.status",
        "capability.tool_id",
        "evolution.apply",
        "evolution.consolidation_review",
        "evolution.diagnostics",
        "evolution.pending",
        "evolution.reject",
        "evolution.runs",
        "file_bridge.delete_attachments",
        "file_bridge.delete_sandbox",
        "file_bridge.delete_sandbox_scoped",
        "file_bridge.detect_refs",
        "file_bridge.detect_refs_scoped",
        "file_bridge.init",
        "file_bridge.init_scoped",
        "file_bridge.list_fs",
        "file_bridge.list_fs_scoped",
        "file_bridge.load_attachments",
        "file_bridge.real_to_sandbox",
        "file_bridge.real_to_sandbox_scoped",
        "file_bridge.rootfs_dir",
        "file_bridge.sandbox_to_real",
        "file_bridge.sandbox_to_real_scoped",
        "file_bridge.save_attachments",
        "file_bridge.skills_dir",
        "file_bridge.workspace_dir",
        "file_bridge.workspace_dir_scoped",
        "file_bridge.workspace_size",
        "file_bridge.workspace_size_scoped",
        "group.clear",
        "group.create",
        "group.delete",
        "group.export",
        "group.get",
        "group.import",
        "group.list",
        "group.messages",
        "group.rename",
        "group.set_prompt",
        "group.update_members",
        "mcp.activate_server",
        "mcp.add_server",
        "mcp.deactivate_server",
        "mcp.finish_oauth",
        "mcp.list_servers",
        "mcp.list_tools",
        "mcp.remove_server",
        "mcp.start_oauth",
        "session.answer_human_request",
        "session.clear",
        "session.compact_context",
        "session.context_status",
        "session.delete",
        "session.history_page",
        "session.inject_message",
        "session.retract_injected_message",
        "session_runs.active",
        "session_runs.get",
        "session_runs.list",
        "skill.archive",
        "skill.check",
        "skill.commands",
        "skill.curator",
        "skill.get",
        "skill.get_catalog_skill",
        "skill.get_snapshot",
        "skill.get_status",
        "skill.install",
        "skill.install_from_catalog",
        "skill.list",
        "skill.pin",
        "skill.read_support_file",
        "skill.record_secret_availability",
        "skill.record_requirement_resolution",
        "skill.record_source_changed",
        "skill.reload",
        "skill.remediation_actions",
        "skill.remediation_runs",
        "skill.remove",
        "skill.request_remediation",
        "skill.resolve_command",
        "skill.restore",
        "skill.run_command",
        "skill.search_catalog",
        "skill.secret_requirements",
        "skill.set_enabled",
        "skill.snapshots",
        "skill.sources",
        "skill.status",
        "skill.unpin",
        "skill.update_config",
        "skill.update_remediation_run",
        "skill.usage",
        "tools.is_platform_tool",
        "tools.is_browser_tool",
        "tools.browser_tool_descriptors",
        "tools.platform_descriptors",
        "workspace.append",
        "workspace.delete",
        "workspace.list",
        "workspace.list_journal_days",
        "workspace.read",
        "workspace.read_journal_day",
        "workspace.rebuild_recall_index",
        "workspace.recall_index_stats",
        "workspace.recall_sessions",
        "workspace.reseed",
        "workspace.search_memory",
        "workspace.system_prompt",
        "workspace.write",
    ];

    fn call_void_string_method(callback: &AndroidCallback, method: &str, payload: &str) {
        let Ok(mut env) = callback.vm.attach_current_thread() else {
            return;
        };
        let Ok(j_payload) = env.new_string(payload) else {
            return;
        };
        let payload_object = JObject::from(j_payload);
        let _ = env.call_method(
            callback.callback.as_obj(),
            method,
            "(Ljava/lang/String;)V",
            &[JValue::Object(&payload_object)],
        );
    }

    fn call_void_method(callback: &AndroidCallback, method: &str) {
        let Ok(mut env) = callback.vm.attach_current_thread() else {
            return;
        };
        let _ = env.call_method(callback.callback.as_obj(), method, "()V", &[]);
    }

    fn emit_tool_request(
        request_id: u64,
        tool_name: &str,
        params_json: &str,
        context_json: String,
    ) {
        let payload = json!({
            "request_id": request_id,
            "tool_name": tool_name,
            "params_json": params_json,
            "context": serde_json::from_str::<serde_json::Value>(&context_json)
                .unwrap_or(serde_json::Value::Null),
        })
        .to_string();

        let Ok(guard) = callback_slot().lock() else {
            return;
        };
        let Some(callback) = guard.as_ref() else {
            return;
        };
        call_void_string_method(callback, "onToolRequest", &payload);
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_registerAssetManager(
        env: JNIEnv,
        _class: JClass,
        asset_manager: JObject,
    ) {
        napaxi_core::api::platform::register_asset_manager(env, asset_manager);
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_registerToolRequestCallback(
        env: JNIEnv,
        _class: JClass,
        callback: JObject,
    ) {
        if callback.is_null() {
            if let Ok(mut guard) = callback_slot().lock() {
                *guard = None;
            }
            return;
        }

        let Ok(vm) = env.get_java_vm() else {
            return;
        };
        let Ok(global_ref) = env.new_global_ref(callback) else {
            return;
        };
        if let Ok(mut guard) = callback_slot().lock() {
            *guard = Some(AndroidCallback {
                vm,
                callback: global_ref,
            });
        }

        let dispatcher: napaxi_core::api::tools::ToolRequestDispatcher = Arc::new(
            move |request_id: u64, tool_name: &str, params_json: &str, context| {
                let context_json = context
                    .map(|value| {
                        serde_json::to_string(&value).unwrap_or_else(|_| "null".to_string())
                    })
                    .unwrap_or_else(|| "null".to_string());
                emit_tool_request(request_id, tool_name, params_json, context_json);
            },
        );
        napaxi_core::api::engine::set_tool_request_dispatcher(dispatcher);
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_createEngine(
        mut env: JNIEnv,
        _class: JClass,
        config_json: JString,
        platform_context_json: JString,
    ) -> jlong {
        crate::bridge::init::create_engine(
            jstring_to_string(&mut env, config_json),
            jstring_to_string(&mut env, platform_context_json),
        ) as jlong
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_updateConfig(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
        config_json: JString,
    ) -> jboolean {
        bool_to_jboolean(crate::bridge::init::update_config(
            handle as i64,
            jstring_to_string(&mut env, config_json),
        ))
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_getConfig(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
    ) -> jstring {
        string_to_jstring(&mut env, crate::bridge::init::get_config(handle as i64))
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_ensureAgentReady(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
        config_json: JString,
    ) -> jboolean {
        bool_to_jboolean(crate::bridge::init::ensure_agent_ready(
            handle as i64,
            jstring_to_string(&mut env, config_json),
        ))
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_disposeEngine(
        _env: JNIEnv,
        _class: JClass,
        handle: jlong,
    ) {
        crate::bridge::init::dispose_engine(handle as i64);
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_getOrCreateAgent(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
        agent_id: JString,
        config_json: JString,
    ) -> jstring {
        let result = crate::bridge::agent::get_or_create_agent(
            handle as i64,
            jstring_to_string(&mut env, agent_id),
            jstring_to_string(&mut env, config_json),
        );
        string_to_jstring(&mut env, result)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_listAgents(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
    ) -> jstring {
        string_to_jstring(&mut env, crate::bridge::agent::list_agents(handle as i64))
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_createSession(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
        config_json: JString,
        agent_id: JString,
        channel_type: JString,
        account_id: JString,
        existing_thread_id: JString,
    ) -> jstring {
        let existing = jstring_to_string(&mut env, existing_thread_id);
        let result = crate::bridge::session::create_session(
            handle as i64,
            jstring_to_string(&mut env, config_json),
            jstring_to_string(&mut env, agent_id),
            jstring_to_string(&mut env, channel_type),
            jstring_to_string(&mut env, account_id),
            if existing.is_empty() {
                None
            } else {
                Some(existing)
            },
        );
        string_to_jstring(&mut env, result)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_sendToSession(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
        config_json: JString,
        agent_id: JString,
        session_key_json: JString,
        message: JString,
        attachments_json: JString,
        max_iterations: jint,
    ) -> jstring {
        let result = crate::bridge::init::send_to_session(
            handle as i64,
            jstring_to_string(&mut env, config_json),
            jstring_to_string(&mut env, agent_id),
            jstring_to_string(&mut env, session_key_json),
            jstring_to_string(&mut env, message),
            jstring_to_string(&mut env, attachments_json),
            max_iterations as i32,
        );
        string_to_jstring(&mut env, result)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_sendToSessionStream(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
        config_json: JString,
        agent_id: JString,
        session_key_json: JString,
        message: JString,
        attachments_json: JString,
        max_iterations: jint,
        callback: JObject,
    ) {
        let Ok(vm) = env.get_java_vm() else {
            return;
        };
        let Ok(callback_ref) = env.new_global_ref(callback) else {
            return;
        };
        let callback = AndroidCallback {
            vm,
            callback: callback_ref,
        };
        let config = jstring_to_string(&mut env, config_json);
        let agent = jstring_to_string(&mut env, agent_id);
        let session_key = jstring_to_string(&mut env, session_key_json);
        let body = jstring_to_string(&mut env, message);
        let attachments = jstring_to_string(&mut env, attachments_json);

        crate::bridge::init::runtime().block_on(
            napaxi_core::api::engine::stream_to_session_handle(
                handle as i64,
                &config,
                &agent,
                &session_key,
                &body,
                &attachments,
                max_iterations as i32,
                |event| call_void_string_method(&callback, "onEvent", &event),
            ),
        );
        call_void_method(&callback, "onComplete");
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_cancelSession(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
        config_json: JString,
        agent_id: JString,
        session_key_json: JString,
    ) -> jboolean {
        bool_to_jboolean(crate::bridge::session::cancel_session(
            handle as i64,
            jstring_to_string(&mut env, config_json),
            jstring_to_string(&mut env, agent_id),
            jstring_to_string(&mut env, session_key_json),
        ))
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_listSessions(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
        config_json: JString,
        agent_id: JString,
        account_id: JString,
    ) -> jstring {
        let result = crate::bridge::session::list_sessions(
            handle as i64,
            jstring_to_string(&mut env, config_json),
            jstring_to_string(&mut env, agent_id),
            jstring_to_string(&mut env, account_id),
        );
        string_to_jstring(&mut env, result)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_getHistory(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
        config_json: JString,
        agent_id: JString,
        thread_id: JString,
    ) -> jstring {
        let result = crate::bridge::session::get_history(
            handle as i64,
            jstring_to_string(&mut env, config_json),
            jstring_to_string(&mut env, agent_id),
            jstring_to_string(&mut env, thread_id),
        );
        string_to_jstring(&mut env, result)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_updateCustomTools(
        mut env: JNIEnv,
        _class: JClass,
        handle: jlong,
        tools_json: JString,
    ) -> jboolean {
        bool_to_jboolean(crate::bridge::init::update_custom_tools(
            handle as i64,
            jstring_to_string(&mut env, tools_json),
        ))
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_resolveToolExecution(
        mut env: JNIEnv,
        _class: JClass,
        request_id: jlong,
        result: JString,
        is_error: jboolean,
    ) -> jboolean {
        bool_to_jboolean(crate::bridge::init::resolve_tool_execution(
            request_id as u64,
            jstring_to_string(&mut env, result),
            is_error != JNI_FALSE,
        ))
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_android_NapaxiNative_callBridge(
        mut env: JNIEnv,
        _class: JClass,
        method: JString,
        handle: jlong,
        args_json: JString,
    ) -> jstring {
        let result = crate::c_api::call_bridge_method(
            handle as i64,
            &jstring_to_string(&mut env, method),
            &jstring_to_string(&mut env, args_json),
        );
        string_to_jstring(&mut env, result)
    }
}
