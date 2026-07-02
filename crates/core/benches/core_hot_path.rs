//! Bench scaffold for Napaxi core hot paths.
//!
//! This file deliberately starts small: it exercises a couple of
//! adapter-facing entry points so we have a baseline and a place to add
//! domain-specific benches as the public API grows. Hot-path internals
//! (LLM SSE parsing, tool loop dispatch, workspace recall) are private
//! `mod`s today; to bench them we need to either widen visibility or add
//! a dedicated `pub(crate)` bench-only adapter — both intentionally out of
//! scope for this scaffold.
//!
//! Run all benches:
//!     cargo bench -p napaxi-core
//!
//! Run a single bench by name:
//!     cargo bench -p napaxi-core -- platform_tool_descriptors_json
//!
//! Bench results live under `target/criterion/`. This bench is NOT wired
//! into CI; treat it as a local pre-release sanity tool.

use criterion::{Criterion, criterion_group, criterion_main};
use napaxi_core::api::tools::{
    browser_tool_descriptors, browser_tool_descriptors_json, platform_tool_descriptors,
    platform_tool_descriptors_json,
};
use std::hint::black_box;

fn bench_platform_tool_descriptors(c: &mut Criterion) {
    c.bench_function("platform_tool_descriptors_json", |b| {
        b.iter(|| {
            let s = platform_tool_descriptors_json();
            black_box(s);
        });
    });

    c.bench_function("platform_tool_descriptors_typed", |b| {
        b.iter(|| {
            let v = platform_tool_descriptors();
            black_box(v);
        });
    });
}

fn bench_browser_tool_descriptors(c: &mut Criterion) {
    c.bench_function("browser_tool_descriptors_json", |b| {
        b.iter(|| {
            let s = browser_tool_descriptors_json();
            black_box(s);
        });
    });

    c.bench_function("browser_tool_descriptors_typed", |b| {
        b.iter(|| {
            let v = browser_tool_descriptors();
            black_box(v);
        });
    });
}

criterion_group!(
    benches,
    bench_platform_tool_descriptors,
    bench_browser_tool_descriptors,
);
criterion_main!(benches);
