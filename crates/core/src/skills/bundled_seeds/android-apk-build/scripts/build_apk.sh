#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: build_apk.sh --project-dir <project> [--app-name <name>] [--without-agent-provider] [--validate-only]

Builds exactly one universal, pure-Java Android APK from the fixed Napaxi
project layout. Do not edit this script; pass parameters instead.

Options:
  --project-dir PATH   Android project root containing app/src/main (required)
  --app-name NAME      Final APK basename; defaults to APP_NAME or app
  --android-sdk PATH   Android SDK path; defaults to ANDROID_SDK or /opt/android/sdk
  --x86-sysroot PATH   x86_64 sysroot; defaults to X86_SYSROOT or /opt/x86root/sysroot
  --without-agent-provider
                       Explicitly build without Agent App Provider support
  --validate-only      Validate project/Provider wiring without Android build tools
  -h, --help           Show this help
USAGE
}

PROJECT_DIR="${PROJECT_DIR:-}"
APP_NAME="${APP_NAME:-app}"
ANDROID_SDK="${ANDROID_SDK:-/opt/android/sdk}"
X86_SYSROOT="${X86_SYSROOT:-/opt/x86root/sysroot}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
AGENT_PROVIDER_SDK_DIR="${AGENT_PROVIDER_SDK_DIR:-$SCRIPT_DIR/../sdk/java}"
WITHOUT_AGENT_PROVIDER=false
VALIDATE_ONLY=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir)
      [ "$#" -ge 2 ] || { echo "--project-dir requires a value" >&2; exit 2; }
      PROJECT_DIR="$2"
      shift 2
      ;;
    --app-name)
      [ "$#" -ge 2 ] || { echo "--app-name requires a value" >&2; exit 2; }
      APP_NAME="$2"
      shift 2
      ;;
    --android-sdk)
      [ "$#" -ge 2 ] || { echo "--android-sdk requires a value" >&2; exit 2; }
      ANDROID_SDK="$2"
      shift 2
      ;;
    --x86-sysroot)
      [ "$#" -ge 2 ] || { echo "--x86-sysroot requires a value" >&2; exit 2; }
      X86_SYSROOT="$2"
      shift 2
      ;;
    --without-agent-provider)
      WITHOUT_AGENT_PROVIDER=true
      shift
      ;;
    --validate-only)
      VALIDATE_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$PROJECT_DIR" ]; then
  echo "missing required --project-dir" >&2
  usage >&2
  exit 2
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
APP_DIR="$PROJECT_DIR/app"
SRC_DIR="$APP_DIR/src/main"
BUILD_DIR="$PROJECT_DIR/build"
GEN_DIR="$BUILD_DIR/gen"
CLASS_DIR="$BUILD_DIR/classes"
DEX_DIR="$BUILD_DIR/dex"
RES_FLAT_DIR="$BUILD_DIR/res-flat"
APK_WORK_DIR="$BUILD_DIR/apk-work"

BUILD_TOOLS="$ANDROID_SDK/build-tools/33.0.2"
ANDROID_JAR="$ANDROID_SDK/platforms/android-33/android.jar"
MIN_API=26
FINAL_APK="$BUILD_DIR/$APP_NAME.apk"
KEYSTORE="$PROJECT_DIR/debug.keystore"
ARTIFACT_DIR="$PROJECT_DIR/.mobile"
ARTIFACT_JSON="$ARTIFACT_DIR/artifact.json"

cleanup_intermediate_outputs() {
  if [ -d "$APK_WORK_DIR" ]; then
    rm -rf "$APK_WORK_DIR" 2>/dev/null || true
  fi
  if [ -d "$BUILD_DIR" ]; then
    find "$BUILD_DIR" -maxdepth 1 -type f -name '*.apk' ! -path "$FINAL_APK" -delete 2>/dev/null || true
  fi
}

# build_id is a deterministic per-build identifier (16 bytes hex, truncated to
# 32 hex chars) derived from projectDir + manifest package + versionCode +
# built_at_iso. It is NOT a content digest of the APK; two reproducible
# rebuilds at different times produce different build_ids by design so the
# install entry layer can distinguish "this exact build attempt" from "same
# bytes produced by another run".
compute_build_id() {
  local pkg vcode at
  pkg="${1:-unknown}"
  vcode="${2:-0}"
  at="${3:-}"
  printf '%s' "${PROJECT_DIR}|${pkg}|${vcode}|${at}" | sha256sum | cut -c1-32
}

# Failure-reason bookkeeping for the failed-artifact.json path. Persists the
# build_id, failure_stage, and failure_reason so the install entry layer can
# distinguish "this build attempt failed" from "no attempt was made".
FAILURE_STAGE=""
FAILURE_REASON=""

fail_build() {
  local reason="$1"
  echo "[build_apk.sh] gate failed: $reason" >&2
  FAILURE_REASON="$reason"
  if [ -d "$BUILD_DIR" ]; then
    find "$BUILD_DIR" -maxdepth 1 -type f -name '*.apk' -delete 2>/dev/null || true
  fi
  # Persist a gate=failed artifact.json so the install entry can refuse the
  # APK explicitly (rather than hiding behind an absent file). Keep build_id,
  # failure_stage, failure_reason so downstream UI can show "this build
  # failed at stage X" instead of "no artifact".
  write_failed_artifact_json "$reason" 2>/dev/null || rm -f "$ARTIFACT_JSON" 2>/dev/null || true
  exit 1
}

write_failed_artifact_json() {
  local reason="${1:-unknown}"
  local stage="${FAILURE_STAGE:-unknown}"
  local built_at_iso
  built_at_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local pkg vcode
  pkg="$(
    sed -n 's/^[[:space:]]*package="\(.*\)".*/\1/p' "$SRC_DIR/AndroidManifest.xml" | head -n1 | tr -d ' '
  )"
  vcode="$(
    sed -n 's/^[[:space:]]*android:versionCode="\([0-9]*\)".*/\1/p' "$SRC_DIR/AndroidManifest.xml" | head -n1 | tr -d ' '
  )"
  [ -n "$pkg" ] || pkg="unknown"
  [ -n "$vcode" ] || vcode="0"
  local build_id
  build_id="$(compute_build_id "$pkg" "$vcode" "$built_at_iso")"
  mkdir -p "$ARTIFACT_DIR"
  cat >"$ARTIFACT_JSON" <<JSON
{
  "gate": "failed",
  "build_id": "$build_id",
  "builder": "napaxi-bundled-android-apk-build",
  "built_at_iso": "$built_at_iso",
  "failure_stage": "$stage",
  "failure_reason": "$reason",
  "validation_rule_version": "android-apk-build.gate.v1"
}
JSON
}

write_artifact_json() {
  # $1 = "ok" or "failed"; remaining fields derived from manifest/zip/apk via python below.
  # Expects the following shell vars to be set on success:
  #   APK_GATE_CHECKS_JSON   (json array of {"name":..,"result":..} entries)
  #   APK_SIGNED_V1 / APK_SIGNED_V2 / APK_SIGNED_V3  (true/false strings)
  #   APK_SIGNING_CERT_FINGERPRINT_SHA256  (hex or "")
  #   APK_TARGET_SDK  (integer)
  mkdir -p "$ARTIFACT_DIR"
  local apk_abs_path
  apk_abs_path="$(cd "$BUILD_DIR" && pwd)/$APP_NAME.apk"
  local manifest_pkg manifest_vcode manifest_vname
  manifest_pkg="$(
    sed -n 's/^[[:space:]]*package="\(.*\)".*/\1/p' "$SRC_DIR/AndroidManifest.xml" | head -n1 | tr -d ' '
  )"
  manifest_vcode="$(
    sed -n 's/^[[:space:]]*android:versionCode="\([0-9]*\)".*/\1/p' "$SRC_DIR/AndroidManifest.xml" | head -n1 | tr -d ' '
  )"
  manifest_vname="$(
    sed -n 's/^[[:space:]]*android:versionName="\([^"]*\)".*/\1/p' "$SRC_DIR/AndroidManifest.xml" | head -n1
  )"
  [ -n "$manifest_pkg" ] || manifest_pkg="unknown"
  [ -n "$manifest_vcode" ] || manifest_vcode="0"
  [ -n "$manifest_vname" ] || manifest_vname="0"
  local built_at_iso
  built_at_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local build_id
  build_id="$(compute_build_id "$manifest_pkg" "$manifest_vcode" "$built_at_iso")"
  if [ "$1" = "failed" ]; then
    FAILURE_STAGE="${FAILURE_STAGE:-unknown}"
    FAILURE_REASON="${FAILURE_REASON:-unknown}"
    cat >"$ARTIFACT_JSON" <<JSON
{
  "gate": "failed",
  "build_id": "$build_id",
  "builder": "napaxi-bundled-android-apk-build",
  "built_at_iso": "$built_at_iso",
  "failure_stage": "$FAILURE_STAGE",
  "failure_reason": "$FAILURE_REASON",
  "validation_rule_version": "android-apk-build.gate.v1"
}
JSON
    return 0
  fi
  local sha size
  sha="$(sha256sum "$FINAL_APK" | awk '{print $1}')"
  size="$(stat -c %s "$FINAL_APK" 2>/dev/null || stat -f %z "$FINAL_APK")"
  local signed_v1="${APK_SIGNED_V1:-false}"
  local signed_v2="${APK_SIGNED_V2:-false}"
  local signed_v3="${APK_SIGNED_V3:-false}"
  local cert_fp="${APK_SIGNING_CERT_FINGERPRINT_SHA256:-}"
  local target_sdk="${APK_TARGET_SDK:-33}"
  local verified_at_iso
  verified_at_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local gate_checks="${APK_GATE_CHECKS_JSON:-[]}"
  # APKSIGN_VERIFY_VERBOSE, APKSIGN_VERIFY_OUTPUT captured earlier in step 8.
  cat >"$ARTIFACT_JSON" <<JSON
{
  "gate": "ok",
  "build_id": "$build_id",
  "apk_abs_path": "$apk_abs_path",
  "sha256": "$sha",
  "size": $size,
  "packageName": "$manifest_pkg",
  "versionCode": "$manifest_vcode",
  "versionName": "$manifest_vname",
  "target_sdk": $target_sdk,
  "arsc_uncompressed": true,
  "arsc_aligned": true,
  "signed_v1": $signed_v1,
  "signed_v2": $signed_v2,
  "signed_v3": $signed_v3,
  "zip_ok": true,
  "signing_cert_fingerprint_sha256": "$cert_fp",
  "build_tool_version": "33.0.2",
  "validation_rule_version": "android-apk-build.gate.v1",
  "built_at_iso": "$built_at_iso",
  "verified_at_iso": "$verified_at_iso",
  "builder": "napaxi-bundled-android-apk-build",
  "gate_checks": $gate_checks,
  "failure_stage": null,
  "failure_reason": null
}
JSON
}
run_x86_64() {
  qemu-x86_64 -L "$X86_SYSROOT" "$@"
}

require_file() {
  if [ ! -f "$1" ]; then
    echo "missing required file: $1" >&2
    exit 1
  fi
}

require_dir() {
  if [ ! -d "$1" ]; then
    echo "missing required directory: $1" >&2
    exit 1
  fi
}

case "$APP_NAME" in
  ''|*/*|*'..'*|*.apk)
    echo "invalid --app-name: use a simple basename without slashes, '..', or .apk" >&2
    exit 2
    ;;
esac

require_file "$SRC_DIR/AndroidManifest.xml"
require_dir "$SRC_DIR/java"
require_dir "$SRC_DIR/res"

if [ -d "$SRC_DIR/assets/www" ] && [ ! -f "$SRC_DIR/assets/www/index.html" ]; then
  echo "WebView assets directory exists but index.html is missing: $SRC_DIR/assets/www/index.html" >&2
  exit 1
fi

PROVIDER_ENABLED=false
if [ -f "$SRC_DIR/assets/agent-app.json" ]; then
  if [ "$WITHOUT_AGENT_PROVIDER" = true ]; then
    echo "--without-agent-provider conflicts with assets/agent-app.json; remove the declaration and Provider manifest entries" >&2
    exit 1
  fi
  PROVIDER_ENABLED=true
elif grep -q 'agent.provider.action.INSTALL_AGENT\|agent.provider.action.HANDLE_PROPOSAL' "$SRC_DIR/AndroidManifest.xml"; then
  echo "AndroidManifest.xml exposes Agent Provider entry points but assets/agent-app.json is missing" >&2
  exit 1
elif [ "$WITHOUT_AGENT_PROVIDER" = true ]; then
  echo "      Agent App Provider explicitly disabled"
else
  echo "      Legacy project without Agent App Provider; new projects enable it by default"
fi

if [ "$PROVIDER_ENABLED" = true ]; then
  if ! grep -q '"provider_id"' "$SRC_DIR/assets/agent-app.json" || \
     ! grep -q '"agent_id"' "$SRC_DIR/assets/agent-app.json" || \
     ! grep -q '"display_name"' "$SRC_DIR/assets/agent-app.json" || \
     ! grep -q '"actions"' "$SRC_DIR/assets/agent-app.json"; then
    echo "invalid assets/agent-app.json: provider_id, agent_id, display_name, and actions are required" >&2
    exit 1
  fi
  if ! grep -q 'agent.provider.action.INSTALL_AGENT' "$SRC_DIR/AndroidManifest.xml" || \
     ! grep -q 'agent.provider.action.HANDLE_PROPOSAL' "$SRC_DIR/AndroidManifest.xml"; then
    echo "AndroidManifest.xml must expose Agent Provider install and action entry points" >&2
    exit 1
  fi
  if ! grep -q 'agent.provider.TRUSTED_REFRESH_SUPPORTED' "$SRC_DIR/AndroidManifest.xml"; then
    echo "AndroidManifest.xml must opt in to trusted same-identity Provider refresh" >&2
    exit 1
  fi
  if ! grep -q 'agent.provider.action.GET_DIAGNOSTICS' "$SRC_DIR/AndroidManifest.xml" || \
     ! grep -q 'AgentProviderDiagnosticsInitializer' "$SRC_DIR/AndroidManifest.xml"; then
    echo "      Existing Provider app has no Napaxi diagnostics entry point"
  fi
  if ! grep -R -q 'AgentProviderActionRegistry' "$SRC_DIR/java"; then
    echo "Provider apps must route actions through AgentProviderActionRegistry" >&2
    exit 1
  fi
  DECLARED_ACTION_IDS=()
  while IFS= read -r action_id; do
    DECLARED_ACTION_IDS+=("$action_id")
  done < <(
    sed -n 's/^[[:space:]]*"action_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$SRC_DIR/assets/agent-app.json"
  )
  if [ "${#DECLARED_ACTION_IDS[@]}" -eq 0 ]; then
    echo "assets/agent-app.json must declare at least one action_id" >&2
    exit 1
  fi
  if printf '%s\n' "${DECLARED_ACTION_IDS[@]}" | sort | uniq -d | grep -q .; then
    echo "assets/agent-app.json contains duplicate action_id values" >&2
    exit 1
  fi
  while IFS= read -r confirmation_policy; do
    case "$confirmation_policy" in
      none|provider_required)
        ;;
      provider)
        echo "      Deprecated confirmation_policy 'provider' treated as 'provider_required'; regenerate the manifest" >&2
        ;;
      *)
        echo "invalid confirmation_policy '$confirmation_policy': use 'none' or 'provider_required'" >&2
        exit 1
        ;;
    esac
  done < <(
    sed -n 's/^[[:space:]]*"confirmation_policy"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$SRC_DIR/assets/agent-app.json"
  )
  REGISTERED_ACTION_IDS=()
  while IFS= read -r java_source; do
    while IFS= read -r action_id; do
      REGISTERED_ACTION_IDS+=("$action_id")
    done < <(
      sed -n 's/.*\.register[[:space:]]*([[:space:]]*"\([^"]*\)".*/\1/p' "$java_source"
    )
  done < <(find "$SRC_DIR/java" -type f -name '*.java' | sort)
  if [ "${#REGISTERED_ACTION_IDS[@]}" -eq 0 ]; then
    echo "Provider app has no AgentProviderActionRegistry handlers" >&2
    exit 1
  fi
  if printf '%s\n' "${REGISTERED_ACTION_IDS[@]}" | sort | uniq -d | grep -q .; then
    echo "Provider app contains duplicate AgentProviderActionRegistry handlers" >&2
    exit 1
  fi
  for action_id in "${DECLARED_ACTION_IDS[@]}"; do
    registered=false
    for registered_action_id in "${REGISTERED_ACTION_IDS[@]}"; do
      if [ "$registered_action_id" = "$action_id" ]; then
        registered=true
        break
      fi
    done
    if [ "$registered" = false ]; then
      echo "No AgentProviderActionRegistry handler for declared action_id: $action_id" >&2
      exit 1
    fi
  done
  for action_id in "${REGISTERED_ACTION_IDS[@]}"; do
    declared=false
    for declared_action_id in "${DECLARED_ACTION_IDS[@]}"; do
      if [ "$declared_action_id" = "$action_id" ]; then
        declared=true
        break
      fi
    done
    if [ "$declared" = false ]; then
      echo "AgentProviderActionRegistry handler is not declared in agent-app.json: $action_id" >&2
      exit 1
    fi
  done
fi

if [ "$VALIDATE_ONLY" = true ]; then
  echo "Agent App project validation passed"
  exit 0
fi

require_file "$ANDROID_JAR"
require_file "$BUILD_TOOLS/aapt2"
require_file "$BUILD_TOOLS/lib/d8.jar"
require_file "$BUILD_TOOLS/zipalign"
require_file "$BUILD_TOOLS/lib/apksigner.jar"

rm -rf "$BUILD_DIR"
mkdir -p "$GEN_DIR" "$CLASS_DIR" "$DEX_DIR" "$RES_FLAT_DIR" "$APK_WORK_DIR"
trap cleanup_intermediate_outputs EXIT

echo "[1/9] aapt2 compile resources"
run_x86_64 "$BUILD_TOOLS/aapt2" compile --dir "$SRC_DIR/res" -o "$RES_FLAT_DIR"

echo "[2/9] aapt2 link resources and assets"
mapfile -t FLAT_RES < <(find "$RES_FLAT_DIR" -name '*.flat' | sort)
if [ "${#FLAT_RES[@]}" -eq 0 ]; then
  echo "aapt2 produced no .flat resources" >&2
  exit 1
fi
ASSET_ARGS=()
if [ -d "$SRC_DIR/assets" ]; then
  ASSET_ARGS=(-A "$SRC_DIR/assets")
fi
run_x86_64 "$BUILD_TOOLS/aapt2" link \
  -I "$ANDROID_JAR" \
  --manifest "$SRC_DIR/AndroidManifest.xml" \
  --java "$GEN_DIR" \
  --auto-add-overlay \
  --no-compress arsc \
  "${ASSET_ARGS[@]}" \
  -o "$APK_WORK_DIR/base.zip" \
  "${FLAT_RES[@]}"

echo "[3/9] javac Java sources"
mapfile -t JAVA_SOURCES < <(find "$SRC_DIR/java" "$GEN_DIR" -name '*.java' | sort)
if [ "$PROVIDER_ENABLED" = true ]; then
  require_dir "$AGENT_PROVIDER_SDK_DIR"
  mapfile -t PROVIDER_SDK_SOURCES < <(find "$AGENT_PROVIDER_SDK_DIR" -name '*.java' | sort)
  if [ "${#PROVIDER_SDK_SOURCES[@]}" -eq 0 ]; then
    echo "Agent Provider Lite SDK contains no Java sources: $AGENT_PROVIDER_SDK_DIR" >&2
    exit 1
  fi
  JAVA_SOURCES+=("${PROVIDER_SDK_SOURCES[@]}")
  echo "      Agent App Provider support enabled"
fi
if [ "${#JAVA_SOURCES[@]}" -eq 0 ]; then
  echo "no Java sources found" >&2
  exit 1
fi
javac --release 11 \
  -classpath "$ANDROID_JAR" \
  -d "$CLASS_DIR" \
  "${JAVA_SOURCES[@]}"

echo "[4/9] d8 classes.dex"
mapfile -t CLASS_FILES < <(find "$CLASS_DIR" -name '*.class' | sort)
java -cp "$BUILD_TOOLS/lib/d8.jar" com.android.tools.r8.D8 \
  --min-api "$MIN_API" \
  --lib "$ANDROID_JAR" \
  --output "$DEX_DIR" \
  "${CLASS_FILES[@]}"
require_file "$DEX_DIR/classes.dex"

echo "[5/9] package classes.dex"
cp "$APK_WORK_DIR/base.zip" "$APK_WORK_DIR/unsigned.zip"
(
  cd "$DEX_DIR"
  zip -q -j "$APK_WORK_DIR/unsigned.zip" classes.dex
)

echo "[6/9] zipalign"
run_x86_64 "$BUILD_TOOLS/zipalign" -f -p 4 \
  "$APK_WORK_DIR/unsigned.zip" \
  "$APK_WORK_DIR/aligned.zip"
# G9: zipalign verify on the aligned-but-unsigned artifact. aapt2 link used
# --no-compress arsc; zipalign -p 4 page-aligns STORED entries; an explicit
# verify catches a broken toolchain before signing consumes the bad APK.
if ! run_x86_64 "$BUILD_TOOLS/zipalign" -c -v 4 "$APK_WORK_DIR/aligned.zip" >/dev/null 2>&1; then
  FAILURE_STAGE="zipalign"
  fail_build "zipalign_check failed on aligned.zip"
fi

# Expected manifest fields parsed from the source AndroidManifest.xml. These
# are the values the gated APK MUST report via `aapt2 dump badging`; using them
# for post-link parity catches a regression where the wrong manifest or stale
# resources slipped into the APK.
EXPECTED_MANIFEST_PKG="$(
  sed -n 's/^[[:space:]]*package="\(.*\)".*/\1/p' "$SRC_DIR/AndroidManifest.xml" | head -n1 | tr -d ' '
)"
EXPECTED_MANIFEST_VCODE="$(
  sed -n 's/^[[:space:]]*android:versionCode="\([0-9]*\)".*/\1/p' "$SRC_DIR/AndroidManifest.xml" | head -n1 | tr -d ' '
)"
EXPECTED_MANIFEST_VNAME="$(
  sed -n 's/^[[:space:]]*android:versionName="\([^"]*\)".*/\1/p' "$SRC_DIR/AndroidManifest.xml" | head -n1
)"
EXPECTED_TARGET_SDK="$(
  sed -n 's/^[[:space:]]*android:targetSdkVersion="\([0-9]*\)".*/\1/p' "$SRC_DIR/AndroidManifest.xml" | head -n1 | tr -d ' '
)"
[ -n "$EXPECTED_TARGET_SDK" ] || EXPECTED_TARGET_SDK="33"
APK_TARGET_SDK="$EXPECTED_TARGET_SDK"

# G2/G3/G4: ZIP integrity + resources.arsc STORED + 4-byte alignment +
# G5: manifest re-parse via `aapt2 dump badging` (post-link parity with the
# source manifest). The same function runs on the final signed APK as a
# post-sign guard against signing-induced layout regressions.
assert_apk_compliant() {
  local apk="$1"
  local reason
  reason="$(python3 - "$apk" <<'PY' || echo "PYTHON_UNAVAILABLE"
import sys, zipfile, re
path = sys.argv[1]
try:
    zf = zipfile.ZipFile(path, "r")
except Exception as e:
    print("zip_unreadable: {}".format(e))
    sys.exit(1)
bad = zipfile.ZipFile(path).testzip()
if bad is not None:
    print("zip_corrupt: {}".format(bad))
    sys.exit(1)
has_application_in_manifest = False
try:
    with open(path, "rb") as fh:
        # We cannot cheaply parse the binary manifest here; treat
        # the presence of AndroidManifest.xml in the APK plus the
        # source-manifest scan done by the shell as the application
        # indicator. We only enforce resources.arsc presence when
        # resources.arsc was emitted by aapt2 link.
        pass
except Exception:
    pass
names = {info.filename for info in zf.infolist()}
if "classes.dex" not in names:
    print("classes_dex_missing")
    sys.exit(1)
arsc_present = "resources.arsc" in names
if arsc_present:
    for info in zf.infolist():
        if info.filename == "resources.arsc":
            if info.compress_type != zipfile.ZIP_STORED:
                print("arsc_compressed: compress_type={}".format(info.compress_type))
                sys.exit(1)
            header_offset = info.header_offset
            # local file header is 30 bytes + name len + extra len; offset of
            # the stored data must be 4-byte aligned for Android R+ mmap.
            with open(path, "rb") as f:
                f.seek(header_offset)
                sig = f.read(4)
                if sig != b"PK\x03\x04":
                    print("bad_local_header: {}".format(sig.hex()))
                    sys.exit(1)
                name_len = int.from_bytes(f.read(2), "little")
                extra_len = int.from_bytes(f.read(2), "little")
                data_offset = header_offset + 30 + name_len + extra_len
                if data_offset % 4 != 0:
                    print("arsc_unaligned: data_offset={} mod4={}".format(data_offset, data_offset % 4))
                    sys.exit(1)
            break
# G7: business assets expected by the source project (assets/www/index.html)
# must be in the APK when the source includes them.
try:
    src_assets_index = None
    # Caller signs the source-project paths via env: we cannot see project dir
    # here, so the shell wrapper feeds a comma list as argv[2].
    expected_assets = sys.argv[2].split(",") if len(sys.argv) > 2 and sys.argv[2] else []
    for a in expected_assets:
        a = a.strip()
        if not a:
            continue
        if a not in names:
            print("assets_missing: {}".format(a))
            sys.exit(1)
except Exception as e:
    print("assets_check_failed: {}".format(e))
    sys.exit(1)
sys.exit(0)
PY
)"
  local rc=$?
  if [ "$reason" = "PYTHON_UNAVAILABLE" ] || [ $rc -ne 0 ]; then
    if [ "$reason" = "PYTHON_UNAVAILABLE" ]; then
      reason="python3 missing or zip parse failed"
    fi
    fail_build "assert_apk_compliant failed ($reason) on $apk"
  fi
}

# G5: manifest parity re-parse via aapt2 dump badging on the aligned APK.
# Verifies packageName/versionCode/versionName/targetSdk in the packaged
# AndroidManifest match the source manifest the build was invoked with.
assert_manifest_parity() {
  local apk="$1"
  local badging pkg vcode vname tsdk
  badging="$(run_x86_64 "$BUILD_TOOLS/aapt2" dump badging "$apk" 2>/dev/null || true)"
  if [ -z "$badging" ]; then
    FAILURE_STAGE="manifest_parse"
    fail_build "manifest_unparseable: aapt2 dump badging produced no output for $apk"
  fi
  pkg="$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n1)"
  vcode="$(printf '%s\n' "$badging" | sed -n "s/^package: name='[^']*' versionCode='\([0-9]*\)'.*/\1/p" | head -n1)"
  vname="$(printf '%s\n' "$badging" | sed -n "s/^package: name='[^']*' versionCode='[0-9]*' versionName='\([^']*\)'.*/\1/p" | head -n1)"
  # targetSdk appears on the sdkVersion/targetSdkVersion line in aapt2 badging.
  tsdk="$(printf '%s\n' "$badging" | sed -n "s/^targetSdkVersion: '\([0-9]*\)'.*/\1/p" | head -n1)"
  [ -n "$tsdk" ] || tsdk="$(printf '%s\n' "$badging" | sed -n 's/^.*targetSdkVersion: *\([0-9]*\).*/\1/p' | head -n1)"
  if [ -z "$pkg" ] || [ -z "$vcode" ]; then
    FAILURE_STAGE="manifest_parse"
    fail_build "manifest_mismatch: aapt2 dump badging could not extract package/versionCode for $apk"
  fi
  if [ "$pkg" != "$EXPECTED_MANIFEST_PKG" ]; then
    FAILURE_STAGE="manifest_parse"
    fail_build "manifest_mismatch: package '$pkg' != expected '$EXPECTED_MANIFEST_PKG'"
  fi
  if [ "$vcode" != "$EXPECTED_MANIFEST_VCODE" ]; then
    FAILURE_STAGE="manifest_parse"
    fail_build "manifest_mismatch: versionCode '$vcode' != expected '$EXPECTED_MANIFEST_VCODE'"
  fi
  if [ -n "$EXPECTED_MANIFEST_VNAME" ] && [ -n "$vname" ] && [ "$vname" != "$EXPECTED_MANIFEST_VNAME" ]; then
    FAILURE_STAGE="manifest_parse"
    fail_build "manifest_mismatch: versionName '$vname' != expected '$EXPECTED_MANIFEST_VNAME'"
  fi
  if [ -n "$tsdk" ] && [ "$tsdk" != "$EXPECTED_TARGET_SDK" ]; then
    FAILURE_STAGE="manifest_parse"
    fail_build "manifest_mismatch: targetSdk '$tsdk' != expected '$EXPECTED_TARGET_SDK'"
  fi
}

# G2: when the source manifest declares <application> and res/ contains
# non-trivial resources, the APK MUST contain resources.arsc (targetSdk 33
# resource index). aapt2 link with --no-compress arsc emits it; a missing
# arsc means the resources failed to compile.
HAS_APPLICATION_ELEMENT=false
if grep -q '<application' "$SRC_DIR/AndroidManifest.xml"; then
  HAS_APPLICATION_ELEMENT=true
fi
RES_NONEMPTY=false
if [ -d "$SRC_DIR/res" ] && [ -n "$(find "$SRC_DIR/res" -type f 2>/dev/null | head -n1)" ]; then
  RES_NONEMPTY=true
fi
if [ "$HAS_APPLICATION_ELEMENT" = true ] && [ "$RES_NONEMPTY" = true ]; then
  ARSC_PRESENT="$(python3 - "$APK_WORK_DIR/aligned.zip" <<'PY'
import sys, zipfile
try:
    zf = zipfile.ZipFile(sys.argv[1])
    print("yes" if "resources.arsc" in {info.filename for info in zf.infolist()} else "no")
except Exception:
    print("error")
PY
)"
  if [ "$ARSC_PRESENT" != "yes" ]; then
    FAILURE_STAGE="arsc_missing"
    fail_build "arsc_missing: project has <application> and res/ but APK has no resources.arsc"
  fi
fi

# G7: collect expected asset names for the python-side assets check.
EXPECTED_ASSETS_CSV=""
if [ -f "$SRC_DIR/assets/www/index.html" ]; then
  EXPECTED_ASSETS_CSV="assets/www/index.html"
fi

# Run the pre-sign gate (zip integrity + arsc STORED + arsc aligned + dex +
# expected assets) and the manifest parity gate on the aligned APK.
echo "[7/9] pre-sign compliance gate (zip + arsc stored/aligned + manifest parity)"
FAILURE_STAGE="pre_sign_gate"
assert_apk_compliant "$APK_WORK_DIR/aligned.zip" "$EXPECTED_ASSETS_CSV"
assert_manifest_parity "$APK_WORK_DIR/aligned.zip"

# Capture pre-sign content digest for classes.dex + resources.arsc so we can
# detect any post-sign tampering that does not flow through apksigner.
presign_digest() {
  python3 - "$1" <<'PY'
import sys, hashlib, zipfile
zf = zipfile.ZipFile(sys.argv[1])
out = []
for name in ("classes.dex", "resources.arsc"):
    try:
        data = zf.read(name)
    except KeyError:
        out.append("{}:missing".format(name))
        continue
    out.append("{}:{}".format(name, hashlib.sha256(data).hexdigest()))
print("\n".join(out))
PY
}
PRESIGN_DIGESTS="$(presign_digest "$APK_WORK_DIR/aligned.zip")"

echo "[8/9] debug sign and verify"
if [ ! -f "$KEYSTORE" ]; then
  keytool -genkeypair -v \
    -keystore "$KEYSTORE" \
    -storepass android \
    -alias androiddebugkey \
    -keypass android \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi

rm -f "$BUILD_DIR"/*.apk
java -jar "$BUILD_TOOLS/lib/apksigner.jar" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias androiddebugkey \
  --ks-pass pass:android \
  --key-pass pass:android \
  --out "$FINAL_APK" \
  "$APK_WORK_DIR/aligned.zip"

# G10: real parsing of `apksigner verify --verbose` output for v1/v2/v3.
APKSIGN_VERIFY_OUTPUT="$(java -jar "$BUILD_TOOLS/lib/apksigner.jar" verify --verbose "$FINAL_APK" 2>&1)"
echo "$APKSIGN_VERIFY_OUTPUT"
APK_SIGNED_V1=false
APK_SIGNED_V2=false
APK_SIGNED_V3=false
if printf '%s\n' "$APKSIGN_VERIFY_OUTPUT" | grep -q 'Verified using v1 scheme: true'; then
  APK_SIGNED_V1=true
fi
if printf '%s\n' "$APKSIGN_VERIFY_OUTPUT" | grep -q 'Verified using v2 scheme: true'; then
  APK_SIGNED_V2=true
fi
if printf '%s\n' "$APKSIGN_VERIFY_OUTPUT" | grep -q 'Verified using v3 scheme: true'; then
  APK_SIGNED_V3=true
fi
if [ "$APK_SIGNED_V1" != true ] && [ "$APK_SIGNED_V2" != true ] && [ "$APK_SIGNED_V3" != true ]; then
  FAILURE_STAGE="apksigner_verify"
  fail_build "apksigner_verify_failed: verify did not report v1/v2/v3 true"
fi

# Signing certificate SHA-256 fingerprint for the artifact registry; taken
# from the debug keystore that just signed this APK. Never embeds the
# keystore password.
APK_SIGNING_CERT_FINGERPRINT_SHA256=""
APK_SIGNING_CERT_FINGERPRINT_SHA256="$(
  keytool -list -v -keystore "$KEYSTORE" -storepass android 2>/dev/null \
    | grep -i 'SHA256:' | head -n1 | sed -n 's/^[[:space:]]*SHA256:[[:space:]]*\([0-9A-Fa-f:]*\).*/\1/p' | tr -d ' '
)"

echo "[9/9] post-sign content immutability gate"
FAILURE_STAGE="post_sign_digest"
POSTSIGN_DIGESTS="$(presign_digest "$FINAL_APK")"
if [ "$PRESIGN_DIGESTS" != "$POSTSIGN_DIGESTS" ]; then
  fail_build "post_sign_content_mismatch: classes.dex/resources.arsc changed after signing"
fi
# Re-assert zip + arsc + manifest parity on the final signed APK; signing
# must not invalidate ZIP layout or stir up its central directory.
FAILURE_STAGE="post_sign_gate"
assert_apk_compliant "$FINAL_APK" "$EXPECTED_ASSETS_CSV"
assert_manifest_parity "$FINAL_APK"
# zipalign must remain valid after signing (apksigner copies the APK).
if ! run_x86_64 "$BUILD_TOOLS/zipalign" -c -v 4 "$FINAL_APK" >/dev/null 2>&1; then
  fail_build "zipalign_check failed on final apk"
fi

cleanup_intermediate_outputs
if [ -e "$APK_WORK_DIR" ]; then
  FAILURE_STAGE="cleanup"
  echo "expected no APK work directory after cleanup: $APK_WORK_DIR" >&2
  fail_build "cleanup_left_apk_work_dir: $APK_WORK_DIR"
fi
APK_COUNT=$(find "$BUILD_DIR" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d ' ')
if [ "$APK_COUNT" != "1" ]; then
  FAILURE_STAGE="final_apk_count"
  echo "expected exactly one final APK in $BUILD_DIR, found $APK_COUNT" >&2
  find "$BUILD_DIR" -maxdepth 1 -type f -name '*.apk' -print >&2
  fail_build "expected_exactly_one_apk: found $APK_COUNT"
fi
# Re-assert on the final, signed APK (catches regressions where signing changed layout).
FAILURE_STAGE="post_sign_assert"
assert_apk_compliant "$FINAL_APK" "$EXPECTED_ASSETS_CSV"

# Build the gate_checks[] array summarizing each gate decision for the artifact
# registry, so the install entry layer can show "this build passed: zip, arsc,
# manifest, zipalign, apksigner, post-sign digest".
build_gate_checks_json() {
  local schemes=""
  local sep=""
  if [ "$APK_SIGNED_V1" = true ]; then schemes="${schemes}${sep}\"v1\""; sep=","; fi
  if [ "$APK_SIGNED_V2" = true ]; then schemes="${schemes}${sep}\"v2\""; sep=","; fi
  if [ "$APK_SIGNED_V3" = true ]; then schemes="${schemes}${sep}\"v3\""; sep=","; fi
  [ -n "$schemes" ] || schemes='"none"'
  cat <<JSON
[
  {"name": "zip_integrity", "result": "pass"},
  {"name": "arsc_uncompressed", "result": "pass"},
  {"name": "arsc_aligned", "result": "pass"},
  {"name": "manifest_parse", "result": "pass"},
  {"name": "zipalign_check", "result": "pass"},
  {"name": "apksigner_verify", "result": "pass", "scheme": [$schemes]},
  {"name": "post_sign_digest", "result": "pass"}
]
JSON
}
APK_GATE_CHECKS_JSON="$(build_gate_checks_json)"

write_artifact_json ok
ls -lh "$FINAL_APK"
echo "Build complete: $FINAL_APK"
echo "Signing keystore reused from: $KEYSTORE"
echo "Artifact manifest: $ARTIFACT_JSON"
