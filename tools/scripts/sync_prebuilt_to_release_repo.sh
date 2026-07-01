#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE_SDK="$ROOT_DIR/packages/flutter"
DEFAULT_RELEASE_REPO="${NAPAXI_FLUTTER_RELEASE_REPO:-$(cd "$ROOT_DIR/.." && pwd)/napaxi_flutter_release}"

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [path/to/napaxi_flutter_release_repo]" >&2
  echo "Default: sibling repo at ../napaxi_flutter_release, or NAPAXI_FLUTTER_RELEASE_REPO if set" >&2
  exit 1
fi

RELEASE_REPO="${1:-$DEFAULT_RELEASE_REPO}"

if [ ! -d "$RELEASE_REPO" ]; then
  echo "Release repo not found: $RELEASE_REPO" >&2
  echo "Usage: $0 [path/to/napaxi_flutter_release_repo]" >&2
  exit 1
fi

copy_dir() {
  local name="$1"
  local src="$2"
  local dst="$3"
  if [ ! -d "$src" ]; then
    echo "Missing source directory: $src" >&2
    exit 1
  fi
  echo "Syncing $name..."
  mkdir -p "$dst"
  rsync -a --delete "$src/" "$dst/"
}

copy_file() {
  local name="$1"
  local src="$2"
  local dst="$3"
  if [ ! -f "$src" ]; then
    echo "Missing source file: $src" >&2
    exit 1
  fi
  echo "Syncing $name..."
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

copy_dir "android" "$SOURCE_SDK/android" "$RELEASE_REPO/android"
copy_dir "ios" "$SOURCE_SDK/ios" "$RELEASE_REPO/ios"
copy_dir "lib" "$SOURCE_SDK/lib" "$RELEASE_REPO/lib"
copy_file "pubspec.yaml" "$SOURCE_SDK/pubspec.yaml" "$RELEASE_REPO/pubspec.yaml"
copy_file "README.md" "$SOURCE_SDK/README.md" "$RELEASE_REPO/README.md"

echo "Done."
echo "Next steps:"
echo "  cd $RELEASE_REPO"
echo "  git status --short"
echo "  git add android ios lib pubspec.yaml README.md"
echo "  git commit -m \"napaxi: sync flutter sdk package\""
