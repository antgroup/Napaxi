# Napaxi Android Native Demo

This app is a native Android SDK demo and integration check that consumes
`packages/android` through a Gradle composite build. It is intentionally
host-app code only: reusable SDK behavior stays in `packages/android` and
`crates/core`.

The launcher screen exposes manual demo actions for the public native SDK
facades:

- Engine/config, capability registry, custom tools, platform tools, browser
  tools, and the Codex app-server engine probe.
- Sessions, chat streaming, session runs, agents, groups, workspace, memory,
  file bridge, skills, and evolution.
- Background service/notifications, automation jobs, MCP server/OAuth shape,
  A2A pairing/task surfaces, Agent App packages/results, Agent Provider
  discovery/install/action handoff, and APK installer result handling.

Network-backed, LLM-backed, provider-backed, media, and APK install operations
show their Android host integration shape without requiring a real API key,
server, provider app, camera flow, microphone flow, or APK path. When those
external inputs are absent, the result panel reports the stable SDK error/result
shape instead of treating the missing environment as a demo failure.

Build it with the repository Gradle wrapper:

```sh
cd examples/integration/android
../../flutter/android/gradlew assembleDebug
```

Run the Android integration device smoke from the repository root:

```sh
./tools/scripts/build.sh check-android-integration-device
```

For a live Codex app-server probe, provide the selected profile key through an
environment variable before launching the device check. The script forwards it
to the debug app launch intent, and the app stores it in the `local-dev` profile
without hardcoding it in source. If the device network requires an
OpenAI-compatible gateway, pass the Base URL and model explicitly instead of
changing source code:

```sh
NAPAXI_ANDROID_INTEGRATION_API_KEY=... \
NAPAXI_ANDROID_INTEGRATION_BASE_URL=https://gateway.example/v1 \
NAPAXI_ANDROID_INTEGRATION_MODEL=gpt-4.1 \
  ./tools/scripts/build.sh check-android-integration-device
```

If the device must route Codex CLI traffic through a proxy, pass proxy
settings explicitly. These values are attached only to the Codex probe agent's
`engine_config.network_env` and are exported only for the sandboxed
`codex app-server` process:

```sh
NAPAXI_ANDROID_INTEGRATION_API_KEY=... \
NAPAXI_ANDROID_INTEGRATION_HTTPS_PROXY=http://proxy.example:7890 \
NAPAXI_ANDROID_INTEGRATION_NO_PROXY=localhost,127.0.0.1 \
  ./tools/scripts/build.sh check-android-integration-device
```

Set `NAPAXI_ANDROID_INTEGRATION_RUN_CODEX_PROBE=1` to have the device check tap
**Codex Engine Probe** and require sanitized diagnostics such as
`codexConfigSuccess`, `hostApiNetwork`, `codexNetworkEnv`, and `chatTimedOut`.
Set `NAPAXI_ANDROID_INTEGRATION_EXPECT_CODEX_LIVE=1` only when the device has a
real reachable model endpoint; that stricter mode also requires a non-timeout
turn, proof that the attached text file and PNG image were reflected in the
model response, plus the custom dynamic tool and `get_device_info` platform-tool
results.

The device smoke installs the Smart Desk provider app, installs this app,
starts it with `run_smoke=true`, installs the first discovered Agent Provider,
executes a provider action result handoff, and waits for the UI to report SDK
smoke results including platform tools, provider discovery, registered Agent
App packages, provider action status, workspace/file bridge, background service
state, completion notification delivery, and APK installer result shape.

The manual **Codex Engine Probe** action syncs the selected model into the
Codex app-server engine, creates a Codex-backed agent, sends local text and PNG
attachments by host path, requires the response to echo text/image sentinels,
admits a custom host tool plus the non-disruptive
`napaxi.platform_tool.get_device_info`, and prints streamed event/tool evidence.
It also prints a sanitized `hostApiNetwork` HTTPS check from the Android app
process when the selected profile has an explicit Base URL, so transport
failures can be separated from Codex-in-sandbox failures without embedding a
demo-only endpoint default.
This is intended for emulator/device verification of the app-server path without
moving reusable runtime behavior into the demo app.

The manual **Run Full Interface Tour** button runs the same app-local host
surface across all currently exposed Android SDK facades and prints a compact
summary for each section.
