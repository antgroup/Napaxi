#[cfg(target_os = "android")]
mod android {
    use jni::JNIEnv;
    use jni::objects::{JObject, JString};
    use jni::sys::{jint, jlong, jstring};

    fn register_asset_manager(env: JNIEnv, asset_manager: JObject) {
        napaxi_core::api::platform::register_asset_manager(env, asset_manager);
    }

    fn jstring_to_string(env: &mut JNIEnv, value: JString) -> String {
        env.get_string(&value)
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default()
    }

    fn string_to_jstring(env: &mut JNIEnv, value: String) -> jstring {
        env.new_string(value)
            .map(|s| s.into_raw())
            .unwrap_or(std::ptr::null_mut())
    }

    fn jlong_to_u64(value: jlong) -> u64 {
        u64::try_from(value).unwrap_or_default()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_sdk_NapaxiSdkPlugin_registerAssetManager(
        env: JNIEnv,
        _this: JObject,
        asset_manager: JObject,
    ) {
        register_asset_manager(env, asset_manager);
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_flutter_NapaxiFlutterPlugin_registerAssetManager(
        env: JNIEnv,
        _this: JObject,
        asset_manager: JObject,
    ) {
        register_asset_manager(env, asset_manager);
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_flutter_NapaxiFlutterPlugin_executeLinuxProgram(
        mut env: JNIEnv,
        _this: JObject,
        request_json: JString,
    ) -> jstring {
        let result = napaxi_core::api::tools::execute_linux_program_json(&jstring_to_string(
            &mut env,
            request_json,
        ));
        string_to_jstring(&mut env, result)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_flutter_NapaxiFlutterPlugin_openLinuxPtySession(
        mut env: JNIEnv,
        _this: JObject,
        request_json: JString,
    ) -> jstring {
        let result = napaxi_core::api::tools::open_linux_pty_session_json(&jstring_to_string(
            &mut env,
            request_json,
        ));
        string_to_jstring(&mut env, result)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_flutter_NapaxiFlutterPlugin_writeLinuxPtySession(
        mut env: JNIEnv,
        _this: JObject,
        session_id: jlong,
        data: JString,
    ) -> jstring {
        let result = napaxi_core::api::tools::write_linux_pty_session_json(
            jlong_to_u64(session_id),
            &jstring_to_string(&mut env, data),
        );
        string_to_jstring(&mut env, result)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_flutter_NapaxiFlutterPlugin_resizeLinuxPtySession(
        mut env: JNIEnv,
        _this: JObject,
        session_id: jlong,
        cols: jint,
        rows: jint,
    ) -> jstring {
        let result = napaxi_core::api::tools::resize_linux_pty_session_json(
            jlong_to_u64(session_id),
            u16::try_from(cols).unwrap_or(80),
            u16::try_from(rows).unwrap_or(24),
        );
        string_to_jstring(&mut env, result)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_flutter_NapaxiFlutterPlugin_closeLinuxPtySession(
        mut env: JNIEnv,
        _this: JObject,
        session_id: jlong,
    ) -> jstring {
        let result =
            napaxi_core::api::tools::close_linux_pty_session_json(jlong_to_u64(session_id));
        string_to_jstring(&mut env, result)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_napaxi_flutter_NapaxiFlutterPlugin_drainLinuxPtyEvents(
        mut env: JNIEnv,
        _this: JObject,
        session_id: jlong,
    ) -> jstring {
        let result = napaxi_core::api::tools::drain_linux_pty_events_json(jlong_to_u64(session_id));
        string_to_jstring(&mut env, result)
    }
}
