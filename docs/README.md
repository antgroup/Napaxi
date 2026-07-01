# Napaxi Documentation

简体中文文档入口：[`README.zh-CN.md`](README.zh-CN.md).

This folder is the documentation surface for Napaxi. Start with
[`overview.md`](overview.md) if you are new, or jump straight to
[`architecture.md`](architecture.md) for ownership boundaries.

For repository-wide rules and AI-tool guidance see
[`../AGENTS.md`](../AGENTS.md). For contribution flow see
[`../CONTRIBUTING.md`](../CONTRIBUTING.md), and for Contributor License
Agreement requirements see [`../CLA.md`](../CLA.md). For security disclosure see
[`../SECURITY.md`](../SECURITY.md).

## Stable References

These documents describe the current SDK shape and are the authoritative source
when something is unclear.

| Document | Purpose |
| --- | --- |
| [`overview.md`](overview.md) | One-paragraph project summary. |
| [`architecture.md`](architecture.md) | Crate layout, runtime boundary, capability and policy model, adapter rules. |
| [`api-contract.md`](api-contract.md) | Two-layer Core API contract and the structured error model crossing the adapter boundary. |
| [`capability-admission.md`](capability-admission.md) | How capability admission gates work, where they live, and how to add new ones safely. |
| [`channel-capabilities.md`](channel-capabilities.md) | Channel capability contract for host-carried IM/device interaction surfaces. |
| [`sdk-integration.md`](sdk-integration.md) | Building, packaging, and verifying the Flutter SDK and native artifacts. |
| [`sdk-adapter-parity.md`](sdk-adapter-parity.md) | Rules for keeping Flutter, Android, and iOS SDK contracts aligned across new features, changes, and bug fixes. |
| [`mobile-capabilities.md`](mobile-capabilities.md) | Capability registry, kinds, activation modes, and adding a new capability. |
| [`channel-provider-architecture.md`](channel-provider-architecture.md) | Channel Provider contract for QQ/WeChat/Feishu/device adapters and its relationship to Agent Provider. |
| [`local-a2a-xchannel.md`](local-a2a-xchannel.md) | Local A2A over xChannel layering and end-to-end task flow. |
| [`agent-app-actions.md`](agent-app-actions.md) | Host-side runtime flow for Agent App Action proposals, signing, and results. |
| [`agent-provider-protocol.md`](agent-provider-protocol.md) | Provider-side SDK contract, Android install/action intents, and trust model. |
| [`ai-coding-guidelines.md`](ai-coding-guidelines.md) | Repository conventions for AI coding tools and reviewers. |
| [`demo-guide.md`](demo-guide.md) | Notes on the Flutter demo app under `examples/flutter/`. |
| [`naming-migration.md`](naming-migration.md) | Plan and timeline for retiring the legacy `Mobile*` naming on the public API surface. |

## Module Guides

Internals-oriented maps for the larger runtime modules — what each owns, how the
pieces connect, and where to make a change. Aimed at contributors working inside
`crates/core`.

| Document | Purpose |
| --- | --- |
| [`module-turn.md`](module-turn.md) | The chat-turn lifecycle: stages, hooks, collected/streaming drivers, context-overflow retry (`crates/core/src/turn/`). |
| [`module-skills.md`](module-skills.md) | Skill subsystem across `features/skills` (domain) and `core/src/skills` (runtime), v1/v2 split, trust model. |
| [`module-evolution.md`](module-evolution.md) | Memory/skill self-improvement: post-turn propose-then-apply flow across `features/evolution` and `core/src/evolution`. |
| [`module-tools.md`](module-tools.md) | Tool subsystem: registry boundary, LLM tool loop, and built-in tool groups including the shell security stack (`crates/core/src/tools/`). |
| [`module-llm.md`](module-llm.md) | HTTP LLM adapter: provider wire formats, streaming/collected dispatch, cache/output-cap policy, error classification (`crates/core/src/llm/`). |
| [`module-mcp.md`](module-mcp.md) | MCP subsystem: server lifecycle, remote tool loading/prefixing, OAuth flow, and transports (`crates/core/src/mcp/`). |
| [`module-context.md`](module-context.md) | Context engine: token budgeting, model-window inference, history compaction, and context status (`crates/core/src/context/`). |
| [`module-workspace.md`](module-workspace.md) | Workspace subsystem: memory/journal files, profile storage, system-prompt assembly, search and indexed recall (`crates/core/src/workspace/`). |
