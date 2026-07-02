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
| Alpine minirootfs | `packages/flutter/android/assets/alpine-rootfs.bin`, `packages/ios/Sources/Napaxi/Resources/alpine-rootfs.tar.gz` | mixed (per-package) | data image | upstream, below |
| `libloader.so` | `packages/flutter/android/jniLibs/arm64-v8a/libloader.so` | GPL-3.0-or-later | Napaxi sandbox loader shim | Napaxi project |
| iSHCore 0.3.0 | `packages/ios/Vendor/iSHCore`, iOS CocoaPods dependency | GPL-3.0; upstream GPLv2 additional licensing notes and `LICENSE.IOS` also apply | static libraries | <https://github.com/ish-app/ish> |

Third-party Android and iOS runtime binaries are **unmodified upstream
releases**. `libloader.so` is a first-party Napaxi runtime shim covered by the
project license. Integrity hashes and per-file detail are in
`packages/flutter/android/jniLibs/THIRD-PARTY.md` and
`packages/ios/Vendor/iSHCore/THIRD-PARTY.md`.

## Copyleft obligations and written offer

For the GPL/LGPL components above, recipients of the Napaxi SDK are entitled to
the corresponding source code. Because Napaxi redistributes these binaries
**unmodified**, the obligation is met by providing the upstream source for the
exact released versions:

- **PRoot 5.1.0** (GPL-2.0-only): <https://github.com/proot-me/proot/releases/tag/v5.1.0>
- **Samba talloc** (LGPL-3.0-or-later): <https://www.samba.org/ftp/talloc/>
- **musl libc** (MIT): <https://musl.libc.org/releases.html>
- **iSHCore / iSH** (GPL-3.0; upstream GPLv2 additional licensing notes and
  `LICENSE.IOS` also apply): <https://github.com/ish-app/ish>
- **Alpine Linux** packages: <https://alpinelinux.org/> (per-package sources via APKBUILD)

If you received a binary distribution of an app built with the Napaxi SDK and
want the corresponding source for any GPL/LGPL component, the upstream links
above provide the exact versions redistributed here. Maintainers should keep
these links pinned to the versions actually shipped.

The upstream iSH repository states that iSH is licensed under GPLv3, with
additional GPLv2 licensing notes for certain contributions, and that `LICENSE.IOS`
applies to App Store distribution. Napaxi records the vendored iSHCore runtime
as GPLv3-governed unless a downstream distributor independently confirms a
different permitted licensing path for the exact shipped artifacts.

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
