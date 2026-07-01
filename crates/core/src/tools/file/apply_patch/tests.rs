//! Integration tests for the apply_patch submodule. The bulk of behaviour is
//! exercised through `tools/file/tests.rs`; this file holds the lower-level
//! parser/seek/apply unit tests that live inside each submodule's `#[cfg(test)]`
//! block. Keep this file as the named entry point referenced from `mod.rs`.

#[test]
fn module_loads() {
    // The real coverage lives in submodule `#[cfg(test)] mod tests` blocks
    // (parser.rs, seek.rs) plus the end-to-end suite in `tools/file/tests.rs`.
    // This shim exists so `mod tests;` in `apply_patch/mod.rs` compiles.
}
