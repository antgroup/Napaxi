#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="${1:-$ROOT_DIR/examples/flutter/ios/Pods/iSHCore}"
DEST="$ROOT_DIR/packages/ios/Vendor/iSHCore"
RESOURCE_DIR="$ROOT_DIR/packages/ios/Sources/Napaxi/Resources"
EXPECTED_VERSION="0.3.0"

if [ ! -d "$SOURCE/include" ] || [ ! -d "$SOURCE/lib" ]; then
  echo "iSHCore pod not found at $SOURCE" >&2
  echo "Run pod install for examples/flutter/ios, or pass a path to an iSHCore pod directory." >&2
  exit 1
fi

if [ ! -f "$SOURCE/rootfs/alpine-rootfs.tar.gz" ]; then
  echo "Missing iSH rootfs: $SOURCE/rootfs/alpine-rootfs.tar.gz" >&2
  exit 1
fi

POD_LOCK="$ROOT_DIR/examples/flutter/ios/Podfile.lock"
if [ "$SOURCE" = "$ROOT_DIR/examples/flutter/ios/Pods/iSHCore" ] && [ -f "$POD_LOCK" ]; then
  if ! grep -q -- "- iSHCore ($EXPECTED_VERSION)" "$POD_LOCK"; then
    ACTUAL_VERSION="$(sed -n 's/^  - iSHCore (\(.*\))$/\1/p' "$POD_LOCK" | head -n 1)"
    echo "Unsupported iSHCore version: ${ACTUAL_VERSION:-unknown}" >&2
    echo "Expected iSHCore $EXPECTED_VERSION. Run pod install with the pinned Napaxi Flutter podspec before preparing SwiftPM assets." >&2
    exit 1
  fi
elif [ "$SOURCE" != "$ROOT_DIR/examples/flutter/ios/Pods/iSHCore" ]; then
  echo "Warning: unable to verify iSHCore version; expected $EXPECTED_VERSION." >&2
else
  echo "Missing Podfile.lock for iSHCore version verification: $POD_LOCK" >&2
  exit 1
fi

mkdir -p "$DEST" "$RESOURCE_DIR"
rsync -a --delete "$SOURCE/include/" "$DEST/include/"
rsync -a --delete "$SOURCE/lib/" "$DEST/lib/"
cp "$SOURCE/rootfs/alpine-rootfs.tar.gz" "$RESOURCE_DIR/alpine-rootfs.tar.gz"

echo "Prepared iSHCore for SwiftPM:"
echo "  headers/libs: $DEST"
echo "  rootfs: $RESOURCE_DIR/alpine-rootfs.tar.gz"
