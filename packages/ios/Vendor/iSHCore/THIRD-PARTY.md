# iOS iSHCore Runtime - Third-Party Provenance

The native Napaxi iOS Swift Package vendors the prebuilt `iSHCore 0.3.0`
headers and static libraries used by the existing Flutter iOS adapter through
the CocoaPods `iSHCore` dependency. It also bundles the iSH Alpine rootfs
archive as a SwiftPM resource so native Swift hosts can run the iSH-backed
shell capability without depending on the Flutter app's CocoaPods bundle.

These files were copied from `examples/flutter/ios/Pods/iSHCore` by
`tools/scripts/prepare_ios_ish_spm.sh`. Napaxi does not modify the iSHCore
libraries or rootfs archive. The rootfs archive is stored via Git LFS (see
`/.gitattributes`). License obligations for these files are recorded in
`/THIRD-PARTY-LICENSES.md`; this file records provenance and integrity metadata.

## Inventory

| File | Component | Upstream version | License | Modified by Napaxi |
| --- | --- | --- | --- | --- |
| `lib/libish.a` | [iSH](https://github.com/ish-app/ish) kernel/runtime | iSHCore 0.3.0 | GPL-3.0; upstream GPLv2 additional licensing notes and `LICENSE.IOS` also apply | No |
| `lib/libish_emu.a` | [iSH](https://github.com/ish-app/ish) x86 emulator | iSHCore 0.3.0 | GPL-3.0; upstream GPLv2 additional licensing notes and `LICENSE.IOS` also apply | No |
| `lib/libfakefs.a` | iSH fakefs runtime | iSHCore 0.3.0 | GPL-3.0; upstream GPLv2 additional licensing notes and `LICENSE.IOS` also apply | No |
| `lib/libfakefsify.a` | iSH fakefs import/export tool | iSHCore 0.3.0 | GPL-3.0; upstream GPLv2 additional licensing notes and `LICENSE.IOS` also apply | No |
| `lib/libarchive.a` | libarchive used by iSH rootfs import | iSHCore 0.3.0 bundle | BSD-style, see upstream | No |
| `lib/libvdso.so.elf` | iSH VDSO runtime image | iSHCore 0.3.0 | GPL-3.0; upstream GPLv2 additional licensing notes and `LICENSE.IOS` also apply | No |
| `../../Sources/Napaxi/Resources/alpine-rootfs.tar.gz` | Alpine Linux 3.21 i386 rootfs | iSHCore 0.3.0 bundle | mixed (per-package) | No |

## Integrity (SHA-256)

Verify checked-out files against the values below:

```text
d3ae22bb2c10b1c4ec44f27c7eb9af4832688b5eed20f9cd76a360ccb927b0da  lib/libarchive.a
d5fbfb482793e36e0d5f6b18848c4b0fd94a69d5a3f1c34177fe99ad621ea569  lib/libfakefs.a
dc129237180eaa32f7a40fd62e504ab50452b800f1d893169d517b48f64b0dff  lib/libfakefsify.a
b7569c806f2c86633d0b61174eb3a8e47884065a46b42e68c3a8b60e44d7b41d  lib/libish.a
82b0beae33fcf5455ac0e8bbe130610e08cccc24852c06f55346d93db9eb96ae  lib/libish_emu.a
9c90b0a7666ac4c1cabd00acbfcffb7904bb6fb416062b322ac8a26f879c1d5c  lib/libvdso.so.elf
5105ee1f45d360309e762511d21ef5e188f87783849950c45e229dcdda4c1499  ../../Sources/Napaxi/Resources/alpine-rootfs.tar.gz
```

To recompute locally:

```sh
shasum -a 256 packages/ios/Vendor/iSHCore/lib/* \
              packages/ios/Sources/Napaxi/Resources/alpine-rootfs.tar.gz
```

## Source code availability

iSHCore is based on iSH. The upstream iSH repository states that iSH is licensed
under GPLv3, with additional GPLv2 licensing notes for certain contributions,
and that `LICENSE.IOS` applies to App Store distribution. Because Napaxi
redistributes these prebuilt files unmodified, corresponding source should be
made available from the upstream iSH project:

- iSH source: <https://github.com/ish-app/ish>
- Alpine Linux package sources: <https://alpinelinux.org/>

See `/THIRD-PARTY-LICENSES.md` for the repository-level written offer and
license notes.
