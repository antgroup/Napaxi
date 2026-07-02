# Napaxi Android Native Demo

This app is a native Android SDK demo and integration check that consumes
`packages/android` through a Gradle composite build. It is intentionally
host-app code only: reusable SDK behavior stays in `packages/android` and
`crates/core`.

The launcher screen exposes manual demo actions for the public native SDK
facades:

- Engine/config, capability registry, custom tools, platform tools, and browser
  tools.
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

The device smoke installs the Smart Desk provider app, installs this app,
starts it with `run_smoke=true`, installs the first discovered Agent Provider,
executes a provider action result handoff, and waits for the UI to report SDK
smoke results including platform tools, provider discovery, registered Agent
App packages, provider action status, workspace/file bridge, background service
state, completion notification delivery, and APK installer result shape.

The manual **Run Full Interface Tour** button runs the same app-local host
surface across all currently exposed Android SDK facades and prints a compact
summary for each section.
