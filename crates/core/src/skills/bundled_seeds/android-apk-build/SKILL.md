---
name: android-apk-build
version: "1.5.0"
display_name: Android APK Build
description: Build small native Android APKs inside Napaxi's phone sandbox. Use this skill whenever the user asks to write, create, generate, package, sign, install, or build an Android app/APK, including casual requests like “写一个 app”, “做个安卓应用”, “打包成 apk”, “生成能安装的应用”, “把网页/HTML 封装成 app”, or “build a simple app”, even if they do not explicitly mention this skill. This skill fixes the aarch64 Alpine + qemu-x86_64 toolchain confusion by forcing one Java-only Android template, compileSdk/targetSdk 33, minSdk 26, exactly one universal pure-Java APK, no leftover intermediate APKs, a valid deterministic vector launcher icon, stable debug signing across rebuilds/updates, and a bundled immutable build script that AI must only run with parameters; Android framework WebView/local HTML assets are allowed only when the user is asking for an installable Android app/APK wrapper; when using HTML, bundle all local resources into the APK assets and reference them with relative paths instead of fixed device/workspace paths; do not turn ordinary HTML/webpage/front-end requests into APKs by default, and do not improvise Gradle/Kotlin/Compose/AndroidX/NDK, iOS, Flutter, React Native, split APKs, multiple variants, or legacy Android targets.
activation:
  keywords: ["android", "apk", "安卓", "应用", "网页封装", "html app", "webview", "打包", "签名", "安装包", "build apk", "写app", "做app", "生成app", "build app"]
  patterns: ["(?i)\\b(apk|android app|build app|make app|package app|sign apk|installable app)\\b", "(写|做|生成|开发|创建).{0,12}(app|应用|安卓|安装包|apk)", "(app|应用|安卓|apk).{0,12}(打包|签名|构建|安装|生成)"]
  tags: ["android", "apk", "mobile", "build"]
  max_context_tokens: 6000
---

# Android APK Build in the Napaxi phone sandbox

Use this skill to create and build a **small installable Android APK** from source in the Napaxi mobile sandbox.

The phone sandbox environment is fixed for this workflow:

- App data root depends on the Napaxi host app. In the Flutter demo / 通用模式 app it is `/data/user/0/com.napa.app.test/files/`; do not use the older Android integration package path. The APK package you generate is independent from the host app package.
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
| Launcher icon | `@drawable/ic_launcher` vector | Avoid missing-icon resources and avoid generating density-specific binary variants |
| SDK policy | minSdk 26, targetSdk 33 | Avoid modern Android “old app” warnings and low-target install issues |


- Java only for Android code. No Kotlin, Gradle, Android Studio, Jetpack Compose, AndroidX, Maven dependencies, or NDK.
- Web-style app wrappers are allowed only when the user is actually asking for an installable Android app/APK that wraps web content, such as “把这个网页封装成 app/apk” or “做一个能安装的 HTML app”. If the user merely asks for HTML, H5, a webpage, a frontend page, or web assets without asking for Android/app/APK/installable output, do not use this skill and do not wrap it as an APK. When a WebView wrapper is appropriate, put the full local web bundle under `app/src/main/assets/www/` (for example `index.html`, CSS, JS, images, fonts, JSON, and other local files), load `file:///android_asset/www/index.html`, and make HTML references relative such as `./style.css`, `./app.js`, or `images/logo.png`. Do not hard-code `/workspace/...`, `/sdcard/...`, `/data/...`, Mac/desktop paths, localhost dev-server URLs, or other fixed file paths inside Java or HTML. Use the same Java-only build template and produce exactly one universal APK. Do not use Capacitor/Cordova/Ionic/React Native/Flutter or any web framework that requires fetching packages or a new toolchain.
- One launcher `Activity` extending `android.app.Activity` or other framework classes from `android.jar` only.
- Always define a launcher icon. Use the fixed vector drawable template below at `app/src/main/res/drawable/ic_launcher.xml`, reference it from both `android:icon` and `android:roundIcon`, and keep icon colors in `colors.xml`. Do not leave icon unset and do not reference missing `@mipmap/*` assets.
- Resource XML under `app/src/main/res/`; Java under `app/src/main/java/`.
- `compileSdk`/platform jar: Android 33 from `/opt/android/sdk/platforms/android-33/android.jar`.
- Manifest must use `<uses-sdk android:minSdkVersion="26" android:targetSdkVersion="33"/>`.
- Do not lower `targetSdkVersion` or `minSdkVersion`. Low targets make modern Android show “built for an older version” warnings or reject installs in some flows.
- Do not add `<uses-sdk>` values via aapt2 command-line flags; keep them in `AndroidManifest.xml`.
- Do not add native libraries, ABI filters, split APKs, `armeabi-v7a`, `x86_64`, `arm64-v8a`, or “compatibility” variants. This template outputs one architecture-independent APK.
- The final APK path must be `build/<APP_NAME>.apk` and it must be the only final APK emitted by the workflow. The bundled build script must not emit intermediate `*.apk` files; temporary packaging files stay under `build/apk-work/` with non-APK names and the script removes that work directory before exit. Do not present or copy multiple installable APK variants.
- Keep the signing certificate stable across app updates. Generate the debug keystore only if it does not already exist, store it at `<project>/debug.keystore`, and never delete it during `rm -rf build`. Reusing this keystore lets Android install a newer APK over the previous one with the same package name.
- Do not place the keystore inside `build/`, because `build/` is cleaned on every run and would change the signature on every rebuild.
- When modifying an existing app, edit that existing project in place. Preserve its manifest package name, Java package/directory, `provider_id`, `agent_id`, and `<project>/debug.keystore`; increment `android:versionCode`; then add, remove, or update actions in `agent-app.json` and their handlers. Never change package/provider/agent identity merely to make an update install or to expose a new capability. A new identity is only for a genuinely separate app requested by the user.
- Provider-enabled apps must declare `<meta-data android:name="agent.provider.TRUSTED_REFRESH_SUPPORTED" android:value="true" />` under `<application>`. This lets a Napaxi Host with the same trusted package and signing identity refresh the provider manifest after an in-place update. It does not bypass signature or provider/agent identity checks.
- Use the bundled script resource `scripts/build_apk.sh`. Do not write, copy, patch, or regenerate a project-local `build.sh`; AI is only allowed to pass parameters to the bundled script.
- Every newly generated app must expose at least one useful Agent App action by default. Put the package declaration at `app/src/main/assets/agent-app.json`, use the bundled Java Lite SDK from `sdk/java/`, route handlers through `AgentProviderActionRegistry`, and keep UI and Agent actions on the same app-owned domain service. Do not copy or rewrite the SDK sources into the project. Only omit Provider support when the user explicitly requests it; in that case omit the declaration/Provider activities and pass `--without-agent-provider`. Existing legacy projects without a declaration remain buildable.

## Required project layout

Create files in this layout exactly:

```text
<project>/
└── app/
    └── src/
        └── main/
            ├── AndroidManifest.xml
            ├── java/
            │   └── <package path>/
            │       └── MainActivity.java
            ├── assets/                 # optional: bundled WebView app assets
            │   ├── agent-app.json      # required: Agent App Provider declaration
            │   └── www/
            │       ├── index.html
            │       ├── style.css
            │       ├── app.js
            │       └── images/
            └── res/
                ├── drawable/
                │   └── ic_launcher.xml
                └── values/
                    ├── colors.xml
                    ├── strings.xml
                    └── styles.xml
```

Minimal resource files are acceptable, but the launcher icon is not optional. For WebView wrappers, all local web resources needed at runtime must be copied into `app/src/main/assets/www/`; the APK must not depend on files left in `/workspace`, Downloads, `/sdcard`, or any other host path. If the user does not provide an icon, use the fixed vector icon template from this skill. If the user provides an icon later, keep the same resource name (`@drawable/ic_launcher`) and still emit one APK; do not create split APKs or a full mipmap density set unless the user explicitly provides those assets.

## Fixed build script resource

The build pipeline is a separate bundled skill file:

```text
/skills/android-apk-build/scripts/build_apk.sh
```

Treat this script as immutable. Do not create a project-local `build.sh`, do not paste the script into the generated app, and do not edit the script to “fix” build behavior. If the skill is mounted at a different root, locate this skill directory and run its `scripts/build_apk.sh` file in place. The only allowed customization is passing parameters:

```bash
bash /skills/android-apk-build/scripts/build_apk.sh --project-dir <project> --app-name <APP_NAME>
```

The script owns the full APK pipeline, including qemu usage for x86_64 SDK binaries, Java `d8`/`apksigner`, stable `<project>/debug.keystore`, Android assets packaging via `app/src/main/assets`, and cleanup verification. After it exits successfully, there must be exactly one APK: `<project>/build/<APP_NAME>.apk`. Intermediate package files use non-APK names inside `build/apk-work/`, that work directory is removed before exit, and additional final APK variants must not exist under `build/`.

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
        android:icon="@drawable/ic_launcher"
        android:roundIcon="@drawable/ic_launcher"
        android:allowBackup="false"
        android:supportsRtl="true">
        <meta-data
            android:name="agent.provider.TRUSTED_REFRESH_SUPPORTED"
            android:value="true" />
        <activity
            android:name="agent.provider.lite.AgentProviderInstallActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="agent.provider.action.INSTALL_AGENT" />
                <category android:name="android.intent.category.DEFAULT" />
            </intent-filter>
        </activity>
        <activity
            android:name=".NapaxiActionActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="agent.provider.action.HANDLE_PROPOSAL" />
                <category android:name="android.intent.category.DEFAULT" />
            </intent-filter>
        </activity>
        <provider
            android:name="agent.provider.lite.AgentProviderDiagnosticsInitializer"
            android:authorities="com.napaxi.generated.sample.napaxi-diagnostics"
            android:exported="false" />
        <activity
            android:name="agent.provider.lite.AgentProviderDiagnosticsActivity"
            android:exported="true"
            android:theme="@android:style/Theme.NoDisplay">
            <intent-filter>
                <action android:name="agent.provider.action.GET_DIAGNOSTICS" />
                <category android:name="android.intent.category.DEFAULT" />
            </intent-filter>
        </activity>
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
    <color name="icon_background">#2F6BFF</color>
    <color name="icon_foreground">#FFFFFF</color>
</resources>
```

`app/src/main/res/drawable/ic_launcher.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="48dp"
    android:height="48dp"
    android:viewportWidth="48"
    android:viewportHeight="48">
    <path
        android:fillColor="@color/icon_background"
        android:pathData="M24,4C12.95,4 4,12.95 4,24s8.95,20 20,20 20,-8.95 20,-20S35.05,4 24,4z" />
    <path
        android:fillColor="@color/icon_foreground"
        android:pathData="M24,10l3.7,7.5 8.3,1.2 -6,5.8 1.4,8.2L24,28.8l-7.4,3.9 1.4,-8.2 -6,-5.8 8.3,-1.2z" />
</vector>
```

## Default Agent App Provider contract

For every new app, first identify stable domain operations that are useful from
Napaxi. Expose business operations such as `note.create`, `task.complete`, or
`expense.list`; do not expose brittle UI operations such as `tap_button_3`.
The launcher Activity and Provider action Activity must call the same domain
service so manual and Agent-driven changes stay consistent.

Create `app/src/main/assets/agent-app.json`. This is the single source of truth
for Provider metadata and action schemas. The first version uses the existing
protocol-v2 `AgentPackage` wire shape for Host compatibility, but the generated
Agent id is an internal legacy identifier and must not be presented as a
switchable Agent in the app UI.

Start from `templates/agent-app.json.template` and
`templates/NapaxiActionActivity.java.template` beside this skill. Replace every
`{{PLACEHOLDER}}`; do not leave template markers in generated source. The
manifest action array and registry registrations are the only app-specific
capability declarations. Domain handler bodies remain app-owned.

```json
{
  "provider_id": "com.napaxi.generated.sample",
  "agent_id": "com.napaxi.generated.sample.agent",
  "display_name": "Sample",
  "description": "Capabilities provided by the generated Sample app.",
  "system_prompt": "",
  "actions": [
    {
      "action_id": "sample.item.create",
      "tool_name": "app_action_sample_item_create",
      "display_name": "Create item",
      "localized_display_names": {"zh-CN": "创建项目"},
      "description": "Create an item in Sample.",
      "localized_descriptions": {"zh-CN": "在 Sample 中创建一个新项目。"},
      "parameters": {
        "type": "object",
        "properties": {"content": {"type": "string"}},
        "required": ["content"]
      },
      "result_schema": {"type": "object"},
      "risk": "low",
      "confirmation_policy": "none",
      "execution_modes": ["android_activity_result"],
      "timeout_seconds": 600
    }
  ],
  "handoff": {"mode": "android_activity_result"},
  "result": {"mode": "activity_result"}
}
```

Every action must provide a short, user-facing `display_name` and
`description`. Add `localized_display_names` and `localized_descriptions` for
each locale supported by the app. Napaxi uses these fields in the Agent App
capability detail page; keep technical identifiers such as `action_id` and
`tool_name` out of user-facing copy.

`confirmation_policy` has exactly two supported values: use `none` only when
the action may execute without Provider-owned confirmation, and use
`provider_required` whenever the Provider must ask the user before execution.
Never emit the legacy value `provider`; the runtime accepts it only to keep
already-installed Agent Apps fail-closed during migration.

Create an exported `.NapaxiActionActivity` that:

1. Calls `AgentProviderLite.validateTrustedProposal(this)` before reading any
   arguments or touching app data.
2. Immediately returns `AgentProviderLite.validationFailureResult(validation)`
   when validation fails.
3. Creates an `AgentProviderActionRegistry` and registers every declared action
   id exactly once with the same domain service used by the UI. Keep each
   `.register("<action_id>", ...)` literal on one line so the build validator can
   compare source handlers with the manifest.
4. Shows Provider-owned confirmation UI when
   `validation.requiresProviderConfirmation()` is true. High and critical risk
   actions must never auto-execute.
5. Marks mutating handlers as non-idempotent in the registry. The shared SDK
   persists replay state immediately before the domain operation executes.
6. Executes through `registry.execute(this, validation)` so missing/extra
   handlers fail closed and exactly one result is returned.

The reusable SDK files live beside this skill under `sdk/java/`. The bundled
build script automatically compiles them when `assets/agent-app.json` exists
and verifies that declared action ids have matching registry handlers.
Do not copy them into the generated project and do not implement custom HMAC,
caller-certificate, expiry, nonce, idempotency, or replay validation.

Every newly generated Provider app also includes the fixed diagnostics
initializer and diagnostics Activity shown in the manifest template above.
Use the app package followed by `.napaxi-diagnostics` as the initializer
authority so it stays unique. The SDK captures uncaught Java exceptions,
recent Android process-exit information, and structured runtime logs into
bounded private storage. Napaxi retrieves them through a Host-signed internal
request; diagnostics are not business actions, never appear in the model tool
list, and do not depend on explicit `@` selection or automatic invocation.

Instrument every generated app's important local runtime boundaries with
`AgentProviderDiagnostics.log(context, level, module, event, message, metadata,
traceId)`. Record normal lifecycle and successful domain operations at `info`,
recoverable degradation or retry at `warning`, and caught network, database,
background, or UI-domain failures at `error`. Use `debug` only for extra detail;
the SDK drops it unless the user enables detailed logging in Napaxi. Reuse one
generated trace id across the UI event, domain service, storage or network step,
and outcome. Agent actions already reuse their request id as the trace id. For
WebView apps, forward sanitized semantic load or JavaScript failure events from
the Java host; never persist raw page contents or arbitrary console output.

The SDK retains at most 300 log entries or 512 KiB for three days and sanitizes
common credential and phone fields. Metadata must still be deliberately small
and non-sensitive: never record passwords, credentials, tokens, cookies, full
request or response bodies, raw user content, contact details, or entire
database rows. `recordBreadcrumb` remains available for the small crash-context
trail, but structured `log` calls are the normal debugging surface.

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

1. Create the fixed project layout, `assets/agent-app.json`, a shared domain service, a validated `NapaxiActionActivity`, and the fixed diagnostics manifest entries. Do not create, edit, or copy `build.sh`; the build script lives in this skill at `scripts/build_apk.sh`.
2. Keep the app simple and framework-only. Build UI programmatically in Java, with basic XML resources, or with a Java `WebView` loading `file:///android_asset/www/index.html` only when the user asks for a web/HTML-style installable Android app or APK wrapper. Put every local HTML/CSS/JS/image/font/data asset under `app/src/main/assets/www/` and use relative links inside the HTML bundle; never reference fixed workspace/device paths.
3. Run `bash /skills/android-apk-build/scripts/build_apk.sh --project-dir <project> --app-name <APP_NAME>` (or the same `scripts/build_apk.sh` path from the active skill directory if `/skills` is mounted differently). If and only if the user explicitly opted out, omit all Provider files/manifest entries and add `--without-agent-provider`. A legacy project that predates Provider-by-default can still rebuild without that flag when it has no Provider declaration.
4. If build succeeds, report exactly one APK path and summarize the generated Provider id and exact action ids/tool names. Note it is a debug-signed, universal pure-Java APK targeting SDK 33 with min SDK 26 and that the bundled script cleaned and verified the absence of intermediate APK files. Also mention the stable keystore path (`<project>/debug.keystore`) so the next update can reuse the same signing certificate, and confirm the launcher icon resource is `@drawable/ic_launcher`.
5. If the user asks to install, use the available APK install flow/tool if present; otherwise provide the APK path.

## Common mistakes to avoid

- Do not inspect the sandbox architecture and then choose APK ABI from it. The sandbox is aarch64, `aapt2`/`zipalign` run under qemu x86_64, and the APK is universal because it contains `classes.dex` and resources only.
- Do not “fix” qemu/x86_64 by producing an x86 APK. qemu is only a build-tool runner.
- Do not “fix” the phone being arm64 by producing an arm64 APK. Pure Java APKs do not need arm64 native output.
- Do not create project-local build scripts at all, including hard-coded scripts like `PROJECT=/workspace/expense-tracker`. Run the bundled skill script and pass `--project-dir` / `--app-name` only.
- Do not output both unsigned/aligned/signed APKs as final artifacts. Only `build/<APP_NAME>.apk` is the final APK; the bundled script must not leave intermediate APKs or a packaging work directory behind.
- Do not regenerate or relocate the keystore on every build. If the package name is unchanged, Android requires the update APK to be signed with the same certificate as the installed APK.
- Do not use `minSdkVersion="21"` or a low `targetSdkVersion`; use min 26 / target 33.
- Do not omit the launcher icon and do not reference nonexistent `@mipmap/ic_launcher` resources. Use `@drawable/ic_launcher` unless the user explicitly supplies a complete replacement icon asset.
- Do not automatically convert plain HTML/H5/webpage/frontend requests into APK projects. Web content is supported here only when the user wants an Android app/APK/installable wrapper; in that case use Android's built-in `android.webkit.WebView`, bundle the complete local web asset tree under `app/src/main/assets/www/`, load `file:///android_asset/www/index.html`, and keep all resource references relative. Do not point at `/workspace`, `/sdcard`, `/data`, Downloads, localhost, or machine-specific absolute paths.
- Do not fetch Gradle, Maven, AndroidX, Compose, Cordova, Capacitor, Ionic, Flutter, React Native, npm packages, or iOS tooling to “improve compatibility”. That makes builds slower, requires unsupported tools, or leaves this phone sandbox workflow.
- Do not omit `agent-app.json` from a newly generated app unless the user explicitly opts out. Do not copy the Lite SDK into the app project, invent a second protocol implementation, bypass `AgentProviderActionRegistry`, or expose high-risk actions without Provider-owned confirmation UI.
- Do not produce multiple APKs for arm64/x86 unless the app actually contains native code, which this skill forbids by default.
