Place `alpine-rootfs.tar.gz` here by running:

```sh
./tools/scripts/prepare_ios_ish_spm.sh
```

The native Swift Package uses this bundled archive to enable the iSH-backed
shell capability at engine creation time.
