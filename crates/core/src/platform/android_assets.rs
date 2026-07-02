#[cfg(target_os = "android")]
mod android {
    use std::ffi::CString;
    use std::os::raw::{c_char, c_int, c_void};
    use std::sync::Mutex;

    use jni::JNIEnv;
    use jni::objects::JObject;
    use jni::sys::JNIEnv as RawJNIEnv;

    static ASSET_MANAGER: Mutex<Option<usize>> = Mutex::new(None);

    #[repr(C)]
    struct AAssetManager(c_void);

    #[repr(C)]
    struct AAsset(c_void);

    #[link(name = "android")]
    unsafe extern "C" {
        fn AAssetManager_fromJava(
            env: *mut RawJNIEnv,
            asset_manager: jni::sys::jobject,
        ) -> *mut AAssetManager;
        fn AAssetManager_open(
            manager: *mut AAssetManager,
            filename: *const c_char,
            mode: c_int,
        ) -> *mut AAsset;
        fn AAsset_read(asset: *mut AAsset, buf: *mut c_void, count: usize) -> c_int;
        fn AAsset_close(asset: *mut AAsset);
    }

    const AASSET_MODE_STREAMING: c_int = 2;

    pub fn register_asset_manager(env: JNIEnv, asset_manager: JObject) {
        // SAFETY: `env` and `asset_manager` are live JNI references provided by
        // the Android runtime on the JNI call; their raw forms are valid for the
        // duration of this call, which is all `AAssetManager_fromJava` requires.
        let manager = unsafe { AAssetManager_fromJava(env.get_raw(), asset_manager.as_raw()) };
        if !manager.is_null() {
            if let Ok(mut guard) = ASSET_MANAGER.lock() {
                *guard = Some(manager as usize);
            }
        }
    }

    pub fn read_asset(name: &str) -> anyhow::Result<Vec<u8>> {
        let manager = ASSET_MANAGER
            .lock()
            .map_err(|e| anyhow::anyhow!("asset manager lock poisoned: {}", e))?
            .ok_or_else(|| anyhow::anyhow!("Android AssetManager not registered"))?
            as *mut AAssetManager;
        let name = CString::new(name)?;
        // SAFETY: `manager` is a non-null `AAssetManager` pointer recovered from
        // the value registered in `register_asset_manager`, and `name` is a valid
        // NUL-terminated C string that outlives the call. `AAssetManager_open`
        // tolerates a missing asset by returning null, checked below.
        let asset = unsafe { AAssetManager_open(manager, name.as_ptr(), AASSET_MODE_STREAMING) };
        if asset.is_null() {
            anyhow::bail!("Android asset not found: {}", name.to_string_lossy());
        }

        let mut result = Vec::new();
        let mut buffer = [0u8; 8192];
        loop {
            let read =
                // SAFETY: `asset` is a non-null `AAsset` (checked after open and
                // not yet closed), and `buffer` is a live local array, so the
                // pointer/length pair passed to `AAsset_read` is valid for writes.
                unsafe { AAsset_read(asset, buffer.as_mut_ptr() as *mut c_void, buffer.len()) };
            if read < 0 {
                // SAFETY: `asset` is the still-open, non-null handle from above;
                // closing it exactly once on this error path is sound.
                unsafe { AAsset_close(asset) };
                anyhow::bail!("failed to read Android asset: {}", name.to_string_lossy());
            }
            if read == 0 {
                break;
            }
            result.extend_from_slice(&buffer[..read as usize]);
        }
        // SAFETY: `asset` is the still-open, non-null handle from above; this is
        // the single successful-path close, after which `asset` is not reused.
        unsafe { AAsset_close(asset) };
        Ok(result)
    }
}

#[cfg(target_os = "android")]
pub use android::{read_asset, register_asset_manager};
