# Third-Party Licenses

Napaxi is licensed under GPL-3.0-or-later (see `LICENSE`). However, the **distributed
mobile SDK bundles third-party native components** — most importantly an
on-device Linux sandbox — that are governed by their own licenses, including
copyleft licenses (GPL/LGPL). This file records those components, their
licenses, and how to obtain corresponding source.

This is a developer-facing record. It is **not** a legal opinion. Downstream
apps that ship the Napaxi SDK must satisfy these obligations in their own
distribution, and should have the combination reviewed by counsel.

## Bundled native components

| Component | Where | License | Linkage | Source |
| --- | --- | --- | --- | --- |
| PRoot 5.1.0 | `packages/flutter/android/jniLibs/arm64-v8a/libproot.so` | GPL-2.0-only | separate executable, invoked via process | upstream, below |
| Samba talloc | `packages/flutter/android/assets/libtalloc.so.2` | LGPL-3.0-or-later | dynamic library | upstream, below |
| musl libc loader | `packages/flutter/android/jniLibs/arm64-v8a/libldmusl.so` | MIT | dynamic loader | upstream, below |
| Alpine minirootfs | `packages/flutter/android/assets/alpine-rootfs.bin`, `packages/ios/Sources/Napaxi/Resources/alpine-rootfs.bin` | mixed (per-package) | data image | upstream, below |
| OpenAI Codex CLI 0.144.6 | inside `packages/flutter/android/assets/alpine-rootfs.bin` | Apache-2.0 | separate CLI executable launched in sandbox | npm package, below |
| `libloader.so` | `packages/flutter/android/jniLibs/arm64-v8a/libloader.so` | GPL-3.0-or-later | Napaxi sandbox loader shim | Napaxi project |

Third-party Android runtime binaries are **unmodified upstream releases**.
`libloader.so` is a first-party Napaxi runtime shim covered by the project
license. Integrity hashes and per-file detail are in
`packages/flutter/android/jniLibs/THIRD-PARTY.md`. The iOS QEMU runtime is not
bundled yet; add its provenance, hashes, and license terms here when the
compiled artifacts land.

## Copyleft obligations and written offer

For the GPL/LGPL components above, recipients of the Napaxi SDK are entitled to
the corresponding source code. Because Napaxi redistributes these binaries
**unmodified**, the obligation is met by providing the upstream source for the
exact released versions:

- **PRoot 5.1.0** (GPL-2.0-only): <https://github.com/proot-me/proot/releases/tag/v5.1.0>
- **Samba talloc** (LGPL-3.0-or-later): <https://www.samba.org/ftp/talloc/>
- **musl libc** (MIT): <https://musl.libc.org/releases.html>
- **Alpine Linux** packages: <https://alpinelinux.org/> (per-package sources via APKBUILD)
- **OpenAI Codex CLI 0.144.6** (Apache-2.0): <https://www.npmjs.com/package/@openai/codex>

If you received a binary distribution of an app built with the Napaxi SDK and
want the corresponding source for any GPL/LGPL component, the upstream links
above provide the exact versions redistributed here. Maintainers should keep
these links pinned to the versions actually shipped.

## Public release status

The native runtime inventory above has been reviewed for public release. The
GPL/LGPL components remain governed by their own licenses, and downstream apps
that redistribute Napaxi SDK binaries must continue to satisfy the source-code
availability and notice obligations documented here.

The iOS Flutter podspec license field describes the plugin source. Because the
distributed artifact also links or bundles native runtime components, downstream
packaging should include this file and the platform-specific provenance records
when redistributing an app built with the SDK.

## Rust and Dart dependencies

The Rust workspace enforces an SPDX allowlist via `deny.toml`. Those transitive
dependencies are not individually reproduced here; run `cargo deny check` and
`cargo about` to regenerate a full manifest if a complete attribution file is
required for a release.

The allowlist includes `CDLA-Permissive-2.0` for `webpki-roots`, which packages
Mozilla root certificate data used by the Rust TLS stack. Treat it as
redistributed data: preserve the CDLA Permissive 2.0 license text in generated
third-party notices when shipping artifacts that include that dependency.

One Rust dependency is **vendored and locally modified** rather than pulled
unchanged from crates.io: `libsql 0.6.0` (MIT) lives under
`vendor/libsql-patched/` and is wired in via `[patch.crates-io]` in the
workspace `Cargo.toml`. The exact deviation from upstream, the rationale, the
rebase cadence, and the exit criteria for dropping the patch are tracked in
[`vendor/libsql-patched/NAPAXI-PATCH.md`](vendor/libsql-patched/NAPAXI-PATCH.md).
The patch is MIT-licensed and permissive, so it carries no copyleft
obligation; it is called out here only because it is a modified redistribution
rather than an unmodified one.

## Idea references (no source copying)

Selected Napaxi runtime improvements (session tool-result depth cap, MCP
lazy-load tool discovery, memory-read path slimming) are self-implemented
under GPL-3.0-or-later using OpenClaw (MIT-licensed) commits as idea
references only. No OpenClaw source code is copied into this repository;
the implementations are independent and respect the GPL/MIT license boundary
as well as Napaxi's on-device redaction / no-leak posture.

- OpenClaw #186481 `c7bd622b95` — deeply nested tool result depth cap
- OpenClaw #186776 `32f9477bf4` — MCP tool discovery on demand
- OpenClaw #186483 `04681a3efc` — memory read path slimming
- OpenClaw #187653 `3f34977399` — exec `$[...]` legacy arithmetic expansion approval
- OpenClaw #187499 `f980e01150` — recursive shell assignment approval
- OpenClaw #176154 `f964859d9f` — MCP startup fail-fast (no silent success on missing tools)

## 重新实现 / Reimplemented designs (from OpenClaw, MIT)

The following Napaxi code paths re-implement design notes and boundary rules
observed in OpenClaw (MIT).  No OpenClaw source code is redistributed or
ported; the implementations are written from scratch under GPL-3.0-or-later.

- **exec policy layering (#188833)**: agent-level partial override merged on
  top of a global exec/security/approval policy.  Missing fields fall back to
  the global baseline; explicit agent fields win; bypass strings are stripped
  from both sources.  See `crates/core/src/capabilities/definitions.rs`
  (`ExecSecurityPolicy`, `ExecPolicyOverride`, `ExecApprovalMode`,
  `ExecSecurityLevel`) and `crates/core/src/capabilities/decisions.rs`
  (`apply_exec_policy_layer`).
- **bounded local skill companion read (#189165)**: companion files under a
  placement-owner-pinned `resourceRoot` are read via a bounded relative-path
  API that rejects `..`, absolute, `~`, drive-letter, symlink, hardlink,
  non-UTF-8, and NUL inputs; a missing resource root degrades gracefully via
  `tracing::debug` rather than surfacing an unhandled rejection.  See
  `crates/core/src/skills/paths.rs` (`safe_companion_relative_path`,
  `validate_companion_target`) and
  `crates/features/skills/src/registry/discovery.rs`
  (`companion_files_in_root`), where the pure-path rules are mirrored locally
  because `crates/features/*` must not depend on `crates/core` per
  `AGENTS.md`.

OpenClaw's idle PostgreSQL-connection-upper-bound design (#188614) is
recorded here as a design reference only — it is **not** re-implemented yet;
evaluation is deferred to a follow-up work item (see `.napaxi-dev/impl.md`).)
