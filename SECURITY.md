# Security Policy

Napaxi is a mobile-native agent SDK. A vulnerability here can land on
end-user devices, so we treat security reports seriously and ask reporters
to follow a coordinated disclosure process.

## Supported Versions

Napaxi is pre-1.0. Security fixes target the current `master` branch and the
most recent tagged release. Older snapshots receive fixes only if they are
still consumed by an active downstream.

| Version | Supported |
| --- | --- |
| `master` (HEAD) | Yes |
| Most recent release tag | Yes |
| Older tags | Best-effort |

## Reporting a Vulnerability

**Do not** open a public GitHub issue, pull request, discussion, or chat
message for security vulnerabilities.

Report privately by email to **`wenyu.mwt@antgroup.com`**. Include:

- A description of the issue and the impact you observed.
- Steps to reproduce, ideally with a minimal sample or proof of concept.
- The affected component (`crates/core/...`, `packages/flutter/...`,
  `packages/agent_provider/...`, etc.) and the commit hash or release tag
  you tested.
- Your assessment of severity and any suggested mitigation.

If you would like an encrypted channel, ask in your first message and we will
provide a PGP key fingerprint.

## Response Process

We aim to:

- Acknowledge receipt within **3 business days**.
- Provide an initial assessment within **10 business days**.
- Ship a fix or a documented mitigation, and coordinate a disclosure
  timeline with you, before the issue is made public.

If we cannot reproduce the issue, we will follow up rather than close
silently.

## Scope

The following components are in scope:

- The Rust runtime kernel under `crates/core/`, including the API boundary
  (`napaxi_core::api`), capability registry, tool admission, MCP handling, and
  LLM provider routing.
- The Flutter Rust Bridge layer under `packages/api_bridge/`.
- The Flutter adapter under `packages/flutter/`, including platform tool
  wrappers, browser surface, and background services.
- The Agent Provider SDK under `packages/agent_provider/`, including the
  Android install/action protocol, HMAC-SHA256 v1 proposal signing, and
  trust-store handling.
- Build and packaging scripts under `tools/scripts/` insofar as they affect
  what ships in a release artifact.
- Patched third-party code under `vendor/` to the extent the patch
  introduces the issue.

Out of scope:

- Issues in unmodified third-party dependencies. Report those upstream;
  feel free to also let us know so we can pin or work around.
- Demo apps under `examples/`. They exist to exercise the SDK and are not
  intended for production use.
- Self-inflicted misconfiguration in host apps (for example, granting
  capabilities the SDK warns against).

## Hardening Notes for Integrators

If you embed Napaxi in a host app, the following areas deserve careful
review:

- **Capability profile**: declare only the capabilities the host can safely
  carry. The registry separates `Registered` / `Available` / `Enabled` for
  this reason.
- **Agent App Action signing**: when using the provider protocol with
  `protocol_version >= 2`, validate the HMAC-SHA256 signature, `nonce`, and
  `expires_at` on every proposal before executing.
- **Browser tool**: keep the WebView visible for login and high-risk
  operations, redact password-like fields from snapshots, and require user
  approval for form submission, payment, send/post, delete, file upload, and
  similar mutating flows.
- **Workspace and skill storage**: paths and admission rules are core
  concerns. Do not bypass them from the host.

See [`docs/mobile-capabilities.md`](docs/mobile-capabilities.md) and
[`docs/agent-app-actions.md`](docs/agent-app-actions.md) for the full
contract.

## Credit

With your permission we will credit you in the release notes that ship the
fix. If you would rather remain anonymous, tell us in your initial report.
