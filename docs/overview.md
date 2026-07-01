# Overview

Napaxi is a mobile-native SDK for building on-device agent experiences. A Rust
runtime kernel owns agent sessions, workspace policy, storage, tools, skills,
group collaboration, MCP, and platform hooks; thin adapter packages expose that
runtime to host apps through a single stable Core API
(`crates/core/src/api/`). Host apps embed the SDK rather than calling a desktop
or server gateway.

The repository is deliberately mobile-generic. Flutter is the first adapter and
demo target, but the SDK is not modeled as a Flutter-only project — Android,
iOS, Flutter, and future adapters share the same runtime behavior, so reusable
logic lives in `crates/`, adapter glue in `packages/`, and demo-only code in
`examples/`.

New here? Read [`architecture.md`](architecture.md) for the crate layout,
runtime boundary, and capability/policy model. The [`README`](../README.md)
covers what the SDK provides and how to get started; [`../AGENTS.md`](../AGENTS.md)
has the repository-wide rules.
