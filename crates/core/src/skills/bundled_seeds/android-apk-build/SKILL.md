---
name: android-apk-build
version: "1.1.0"
display_name: Android APK Build
description: Build small native Android APKs inside Napaxi's phone sandbox. Use this skill whenever the user asks to write, create, generate, package, sign, install, or build an Android app/APK, including casual requests like “写一个 app”, “做个安卓应用”, “打包成 apk”, “生成能安装的应用”, “把网页/HTML 封装成 app”, or “build a simple app”, even if they do not explicitly mention this skill. This skill fixes the aarch64 Alpine + qemu-x86_64 toolchain confusion by forcing one Java-only Android template, compileSdk/targetSdk 33, minSdk 26, exactly one universal pure-Java APK, stable debug signing across rebuilds/updates, and a deterministic build.sh; Android framework WebView/local HTML assets are allowed because they need no new toolchain, but do not improvise Gradle/Kotlin/Compose/AndroidX/NDK, iOS, Flutter, React Native, split APKs, multiple variants, or legacy Android targets.
activation:
  keywords: ["android", "apk", "安卓", "应用", "网页封装", "html app", "webview", "打包", "签名", "安装包", "build apk", "写app", "做app", "生成app", "build app"]
  patterns: ["(?i)\\b(apk|android app|build app|make app|package app|sign apk|installable app)\\b", "(写|做|生成|开发|创建).{0,12}(app|应用|安卓|安装包|apk)", "(app|应用|安卓|apk).{0,12}(打包|签名|构建|安装|生成)"]
  tags: ["android", "apk", "mobile", "build"]
  max_context_tokens: 6000
---

# Android APK Build in the Napaxi phone sandbox

Use this skill to create and build a **small installable Android APK** from source in the Napaxi mobile sandbox.

The phone sandbox environment is fixed for this workflow:

- App data root on the integration device: `/data/user/0/com.napaxi.examples.androidintegration/files/`.
- Linux rootfs mounted for the AI: Alpine Linux v3.23 under `linux-env/rootfs`.
- Inside the sandbox, use `/workspace` for app source and `/opt/android/sdk` for Android SDK.
- Android SDK pieces already expected by the template: build-tools `33.0.2` and platform `android-33`.
- `aapt2` and `zipalign` in build-tools `33.0.2` are **x86_64 Linux ELF binaries**. Run them only via `qemu-x86_64 -L /opt/x86root/sysroot`.
- `qemu-x86_64` itself is an arm64 binary in the Alpine rootfs; this does not make the APK x86. It only lets the arm64 phone execute x86_64 build tools.
- `d8` and `apksigner` are Java tools. Invoke their jars with `java -cp ... com.android.tools.r8.D8` and `java -jar .../apksigner.jar`, not through qemu.

This build-host setup is separate from the APK output format. The output APK below is **pure Java/Dalvik bytecode with no native `.so` files**, so it is a single architecture-independent APK and is not “x86_64-only” or “arm64-only”.

## Non-negotiable output contract

When building an app with this skill, create exactly this kind of Android app unless the user explicitly requests a different architecture and accepts the extra work:

Before writing code, mentally pin these constants and do not reinterpret them from `uname -m` or device ABI:

| Concern | Fixed value | Why |
|---|---|---|
| Build host CPU | aarch64 Android phone / Alpine userspace | Where the AI commands run |
| x86 emulation | only for `aapt2` and `zipalign` | These two SDK binaries are x86_64 Linux executables |
| APK native ABI | none | The app contains no native libraries |
| APK compatibility format | exactly one universal APK | `classes.dex` + resources install on supported Android devices regardless of CPU |
| Signing identity | stable per project | Android treats same-package updates as valid only when signed by the same certificate |
| SDK policy | minSdk 26, targetSdk 33 | Avoid modern Android “old app” warnings and low-target install issues |


- Java only for Android code. No Kotlin, Gradle, Android Studio, Jetpack Compose, AndroidX, Maven dependencies, or NDK.
- Web-style apps are allowed only as an Android framework `WebView` wrapper around local HTML/CSS/JS assets under `app/src/main/assets/`. This still uses the same Java-only build template and produces exactly one universal APK. Do not use Capacitor/Cordova/Ionic/React Native/Flutter or any web framework that requires fetching packages or a new toolchain.
- One launcher `Activity` extending `android.app.Activity` or other framework classes from `android.jar` only.
- Resource XML under `app/src/main/res/`; Java under `app/src/main/java/`.
- `compileSdk`/platform jar: Android 33 from `/opt/android/sdk/platforms/android-33/android.jar`.
- Manifest must use `<uses-sdk android:minSdkVersion="26" android:targetSdkVersion="33"/>`.
- Do not lower `targetSdkVersion` or `minSdkVersion`. Low targets make modern Android show “built for an older version” warnings or reject installs in some flows.
- Do not add `<uses-sdk>` values via aapt2 command-line flags; keep them in `AndroidManifest.xml`.
- Do not add native libraries, ABI filters, split APKs, `armeabi-v7a`, `x86_64`, `arm64-v8a`, or “compatibility” variants. This template outputs one architecture-independent APK.
- The final APK path must be `build/<APP_NAME>.apk` and it must be the only final APK emitted by the workflow. Temporary intermediates may exist under `build/apk-work/`, but do not present or copy multiple installable APK variants.
- Keep the signing certificate stable across app updates. Generate the debug keystore only if it does not already exist, store it at `<project>/debug.keystore`, and never delete it during `rm -rf build`. Reusing this keystore lets Android install a newer APK over the previous one with the same package name.
- Do not place the keystore inside `build/`, because `build/` is cleaned on every run and would change the signature on every rebuild.
- Use the fixed `build.sh` template below. Do not rewrite the pipeline from memory.

## Required project layout

Create files in this layout exactly:

```text
<project>/
├── build.sh
└── app/
    └── src/
        └── main/
            ├── AndroidManifest.xml
            ├── java/
            │   └── <package path>/
            │       └── MainActivity.java
            ├── assets/                 # optional: local HTML/CSS/JS for WebView apps
            │   └── index.html
            └── res/
                ├── drawable/
                ├── mipmap-hdpi/
                └── values/
                    ├── colors.xml
                    ├── strings.xml
                    └── styles.xml
```

Minimal resource files are acceptable. If there is no image/icon asset, use default label-only app metadata and avoid inventing binary assets.

## Fixed `build.sh` template

Write this file verbatim as `<project>/build.sh`, then only change `APP_NAME` through the environment if needed (`APP_NAME=MyApp bash build.sh`). Do not hard-code a user-specific project path.

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$PROJECT_DIR/app"
SRC_DIR="$APP_DIR/src/main"
BUILD_DIR="$PROJECT_DIR/build"
GEN_DIR="$BUILD_DIR/gen"
CLASS_DIR="$BUILD_DIR/classes"
DEX_DIR="$BUILD_DIR/dex"
RES_FLAT_DIR="$BUILD_DIR/res-flat"
APK_WORK_DIR="$BUILD_DIR/apk-work"

ANDROID_SDK="${ANDROID_SDK:-/opt/android/sdk}"
BUILD_TOOLS="$ANDROID_SDK/build-tools/33.0.2"
ANDROID_JAR="$ANDROID_SDK/platforms/android-33/android.jar"
X86_SYSROOT="${X86_SYSROOT:-/opt/x86root/sysroot}"
APP_NAME="${APP_NAME:-app}"
MIN_API=26

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

require_file "$ANDROID_JAR"
require_file "$BUILD_TOOLS/aapt2"
require_file "$BUILD_TOOLS/lib/d8.jar"
require_file "$BUILD_TOOLS/zipalign"
require_file "$BUILD_TOOLS/lib/apksigner.jar"
require_file "$SRC_DIR/AndroidManifest.xml"
require_dir "$SRC_DIR/java"
require_dir "$SRC_DIR/res"

KEYSTORE="$PROJECT_DIR/debug.keystore"

rm -rf "$BUILD_DIR"
mkdir -p "$GEN_DIR" "$CLASS_DIR" "$DEX_DIR" "$RES_FLAT_DIR" "$APK_WORK_DIR"

echo "[1/7] aapt2 compile resources"
run_x86_64 "$BUILD_TOOLS/aapt2" compile --dir "$SRC_DIR/res" -o "$RES_FLAT_DIR"

echo "[2/7] aapt2 link resources"
mapfile -t FLAT_RES < <(find "$RES_FLAT_DIR" -name '*.flat' | sort)
if [ "${#FLAT_RES[@]}" -eq 0 ]; then
  echo "aapt2 produced no .flat resources" >&2
  exit 1
fi
run_x86_64 "$BUILD_TOOLS/aapt2" link \
  -I "$ANDROID_JAR" \
  --manifest "$SRC_DIR/AndroidManifest.xml" \
  --java "$GEN_DIR" \
  --auto-add-overlay \
  -o "$APK_WORK_DIR/base.apk" \
  "${FLAT_RES[@]}"

echo "[3/7] javac Java sources"
mapfile -t JAVA_SOURCES < <(find "$SRC_DIR/java" "$GEN_DIR" -name '*.java' | sort)
if [ "${#JAVA_SOURCES[@]}" -eq 0 ]; then
  echo "no Java sources found" >&2
  exit 1
fi
javac -source 11 -target 11 \
  -classpath "$ANDROID_JAR" \
  -d "$CLASS_DIR" \
  "${JAVA_SOURCES[@]}"

echo "[4/7] d8 classes.dex"
mapfile -t CLASS_FILES < <(find "$CLASS_DIR" -name '*.class' | sort)
java -cp "$BUILD_TOOLS/lib/d8.jar" com.android.tools.r8.D8 \
  --min-api "$MIN_API" \
  --lib "$ANDROID_JAR" \
  --output "$DEX_DIR" \
  "${CLASS_FILES[@]}"
require_file "$DEX_DIR/classes.dex"

echo "[5/7] package classes.dex"
cp "$APK_WORK_DIR/base.apk" "$APK_WORK_DIR/unsigned.apk"
(
  cd "$DEX_DIR"
  zip -q -j "$APK_WORK_DIR/unsigned.apk" classes.dex
)

echo "[6/7] zipalign"
run_x86_64 "$BUILD_TOOLS/zipalign" -f -p 4 \
  "$APK_WORK_DIR/unsigned.apk" \
  "$APK_WORK_DIR/aligned.apk"

echo "[7/7] debug sign and verify"
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
  --out "$BUILD_DIR/$APP_NAME.apk" \
  "$APK_WORK_DIR/aligned.apk"

java -jar "$BUILD_TOOLS/lib/apksigner.jar" verify --verbose "$BUILD_DIR/$APP_NAME.apk"
APK_COUNT=$(find "$BUILD_DIR" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d ' ')
if [ "$APK_COUNT" != "1" ]; then
  echo "expected exactly one final APK in $BUILD_DIR, found $APK_COUNT" >&2
  find "$BUILD_DIR" -maxdepth 1 -type f -name '*.apk' -print >&2
  exit 1
fi
ls -lh "$BUILD_DIR/$APP_NAME.apk"
echo "Build complete: $BUILD_DIR/$APP_NAME.apk"
echo "Signing keystore reused from: $KEYSTORE"
```

## Minimal app template

Use reverse-domain lowercase package names such as `com.napaxi.generated.todo`. Keep package name, directory path, and activity references consistent.

`app/src/main/AndroidManifest.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.napaxi.generated.sample"
    android:versionCode="1"
    android:versionName="1.0">

    <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="33" />

    <application
        android:theme="@style/AppTheme"
        android:label="@string/app_name"
        android:allowBackup="false"
        android:supportsRtl="true">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

`app/src/main/res/values/strings.xml`:

```xml
<resources>
    <string name="app_name">Sample</string>
</resources>
```

`app/src/main/res/values/colors.xml`:

```xml
<resources>
    <color name="background">#FFFFFF</color>
    <color name="foreground">#202124</color>
</resources>
```

`app/src/main/res/values/styles.xml`:

```xml
<resources>
    <style name="AppTheme" parent="android:style/Theme.Material.Light.NoActionBar">
        <item name="android:fontFamily">sans</item>
        <item name="android:windowLightStatusBar">true</item>
        <item name="android:statusBarColor">@color/background</item>
        <item name="android:navigationBarColor">@color/background</item>
    </style>
</resources>
```

`app/src/main/java/com/napaxi/generated/sample/MainActivity.java`:

```java
package com.napaxi.generated.sample;

import android.app.Activity;
import android.os.Bundle;
import android.graphics.Color;
import android.view.Gravity;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView view = new TextView(this);
        view.setText("Hello from Napaxi");
        view.setTextColor(Color.rgb(32, 33, 36));
        view.setTextSize(24);
        view.setGravity(Gravity.CENTER);
        setContentView(view);
    }
}
```

## Build workflow

1. Create the fixed layout and write `build.sh` exactly from this skill.
2. Keep the app simple and framework-only. Build UI programmatically in Java, with basic XML resources, or with a Java `WebView` loading local files from `app/src/main/assets/` when the user asks for a web/HTML-style app.
3. Run `chmod +x build.sh && bash build.sh` from the project root.
4. If build succeeds, report exactly one APK path and note it is a debug-signed, universal pure-Java APK targeting SDK 33 with min SDK 26. Also mention the stable keystore path (`<project>/debug.keystore`) so the next update can reuse the same signing certificate.
5. If the user asks to install, use the available APK install flow/tool if present; otherwise provide the APK path.

## Common mistakes to avoid

- Do not inspect the sandbox architecture and then choose APK ABI from it. The sandbox is aarch64, `aapt2`/`zipalign` run under qemu x86_64, and the APK is universal because it contains `classes.dex` and resources only.
- Do not “fix” qemu/x86_64 by producing an x86 APK. qemu is only a build-tool runner.
- Do not “fix” the phone being arm64 by producing an arm64 APK. Pure Java APKs do not need arm64 native output.
- Do not create hard-coded scripts like `PROJECT=/workspace/expense-tracker`; the fixed script derives `PROJECT_DIR` from its own path.
- Do not output both unsigned/aligned/signed APKs as final artifacts. Only `build/<APP_NAME>.apk` is the final APK; intermediates stay in `build/apk-work/`.
- Do not regenerate or relocate the keystore on every build. If the package name is unchanged, Android requires the update APK to be signed with the same certificate as the installed APK.
- Do not use `minSdkVersion="21"` or a low `targetSdkVersion`; use min 26 / target 33.
- Do not reject a web/网页/HTML-style app just because it is web-like. If it can be implemented with Android's built-in `android.webkit.WebView` and local assets, it is supported by this toolchain.
- Do not fetch Gradle, Maven, AndroidX, Compose, Cordova, Capacitor, Ionic, Flutter, React Native, npm packages, or iOS tooling to “improve compatibility”. That makes builds slower, requires unsupported tools, or leaves this phone sandbox workflow.
- Do not produce multiple APKs for arm64/x86 unless the app actually contains native code, which this skill forbids by default.
