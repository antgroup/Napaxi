# Android Prebuilt Native Runtime — Third-Party Provenance

The Napaxi Android SDK ships a small set of prebuilt native binaries that
provide the on-device Linux sandbox (a PRoot-based user-mode chroot running an
Alpine rootfs). Third-party binaries are unmodified upstream release artifacts;
`libloader.so` is a first-party Napaxi runtime shim. They are stored via
**Git LFS** (see `/.gitattributes`). License obligations for these binaries are
recorded in `/THIRD-PARTY-LICENSES.md`; this file records provenance and
integrity metadata.

Napaxi's own native bridge library (`libnapaxi_api_bridge.so`) is a first-party
build artifact, is `.gitignore`'d, and is **not** covered here.

## Inventory

| File | Component | Upstream version | License | Modified by Napaxi |
| --- | --- | --- | --- | --- |
| `jniLibs/arm64-v8a/libproot.so` | [PRoot](https://github.com/proot-me/proot) | 5.1.0 | GPL-2.0-only | No |
| `assets/libtalloc.so.2` | [talloc](https://talloc.samba.org/) (Samba) | 2.x | LGPL-3.0-or-later | No |
| `jniLibs/arm64-v8a/libldmusl.so` | [musl libc](https://musl.libc.org/) dynamic loader (aarch64) | — | MIT | No |
| `jniLibs/arm64-v8a/libloader.so` | Napaxi aarch64 sandbox loader shim | — | Apache-2.0 | First-party |
| `assets/alpine-rootfs.bin` | [Alpine Linux](https://alpinelinux.org/) minirootfs | — | mixed (per-package) | No |

## Integrity (SHA-256)

Verify a checked-out binary against the value below (these match the Git LFS
object IDs):

```
125dff2415ae1dcb8b1ae97c51357de73ef11f28268b86cd50a0f13aa1c3ea91  jniLibs/arm64-v8a/libproot.so
c51792635038f3fcfb27f44f977181c5bb043150a0d3074e0db7e3b3477a0ce0  jniLibs/arm64-v8a/libldmusl.so
44ef39c1e1a18c09f6e4c4b5d6f8bba82d30596598bd155ec162d05c5122ff04  jniLibs/arm64-v8a/libloader.so
3c9b207c0a6ea2896b7523e03f55d9ab0d9e88baa115d4c32b84058ff4246fbb  assets/libtalloc.so.2
```

`alpine-rootfs.bin` integrity is tracked by its Git LFS object id
(`02205b38b17b08dc652df6a07ce989d245eb8fc6cfbfc39ef5bb7417777a2ef0`).

To recompute locally:

```sh
shasum -a 256 packages/flutter/android/jniLibs/arm64-v8a/*.so \
              packages/flutter/android/assets/libtalloc.so.2
```

## Source code availability (GPL/LGPL)

PRoot (GPL-2.0-only) and talloc (LGPL-3.0-or-later) require that corresponding
source be available to recipients. Because these are unmodified upstream
releases, the obligation is satisfied by pointing to upstream:

- PRoot 5.1.0 source: <https://github.com/proot-me/proot/releases/tag/v5.1.0>
- talloc source: <https://www.samba.org/ftp/talloc/>
- musl libc source: <https://musl.libc.org/releases.html>

See `/THIRD-PARTY-LICENSES.md` for the full written offer and license texts.
