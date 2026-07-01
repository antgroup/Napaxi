// Keep the hand-written FFI surface `.unwrap()`-free so a regression surfaces
// as a clippy warning (a hard CI gate via `-D warnings`) instead of aborting
// the host app — mobile builds use `panic = "abort"`, and a panic across the C
// ABI is undefined behaviour. Lives at the crate root so it covers every
// hand-written module (`c_api`, `bridge/*`, `android_jni`), not just one.
// Mirrors `napaxi-core` and `napaxi_skills`. Test code is exempt — fixtures read
// fine with `.unwrap()`. `expect()` stays allowed for genuine startup
// invariants (e.g. Tokio runtime creation in `bridge::init::runtime`).
#![cfg_attr(not(test), warn(clippy::unwrap_used))]

pub mod bridge;
// The hand-written C ABI entry points. Public so an in-tree integration test
// under `tests/` can drive the real `create_engine -> call_json -> dispose`
// lifecycle through the exact FFI functions a host binds to. Only the
// already-`pub extern "C"` entry points become reachable; the module's helpers
// stay private `fn`s. (A downstream crate cannot link a dependency's
// `#[no_mangle]` symbols via `extern`, so the test calls them by Rust path.)
pub mod c_api;
// The FRB-generated bridge is machine-emitted and full of unwraps we do not
// hand-audit; the crate-level lint above is not actionable there, so exempt it.
#[allow(clippy::unwrap_used)]
#[path = "generated/frb_generated.rs"]
mod frb_generated;

#[cfg(target_os = "android")]
#[path = "android_assets.rs"]
mod android_assets;
#[cfg(target_os = "android")]
#[path = "android_jni.rs"]
mod android_jni;
