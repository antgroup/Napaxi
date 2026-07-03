# Napaxi Examples

This directory contains integration examples and demo applications that show
how to embed the Napaxi SDK in a host application.

## Flutter Demo (`flutter/`)

The primary demo: a thin chat UI built on `package:napaxi_flutter`. It
demonstrates the core SDK integration pattern:

1. **Engine creation** — Configure LLM provider and create an `NapaxiEngine`.
2. **Chat sessions** — Open a session, stream messages, handle chat events.
3. **Custom tools** — Register host-owned tools and dispatch tool results.
4. **Background execution** — On Android, a foreground service keeps the agent
   running while the app is backgrounded.
5. **Agent Provider** — Install and trigger provider app actions.

### Key Integration Points

| File | What it demonstrates |
|------|---------------------|
| `lib/main.dart` | App entry point, theme, routing |
| `lib/services/napaxi_engine_service.dart` | Engine lifecycle, config, tool registration |
| `lib/pages/chat_page.dart` | Chat UI, streaming event rendering |
| `lib/pages/settings_page.dart` | LLM config editing |
| `android/app/src/main/` | Android foreground service, notification permission |

### Running

```sh
cd examples/flutter
flutter run
```

### Validation

```sh
flutter analyze
flutter test
dart run tool/check_a2a_user_contract.dart
```

## Integration Tests (`integration/`)

Platform-specific smoke tests used by `tools/scripts/build.sh` to verify that
the native library loads and the engine starts on real devices.

- `integration/android/` — Android Instrumentation test that loads
  `libnapaxi_api_bridge.so`, creates an engine, and verifies workspace I/O.
- `integration/ios/` — iOS app that links the Swift Package, creates an
  engine, and verifies the iSH rootfs is available.

These are functional smoke tests, not pedagogical examples. They are run by:

```sh
./tools/scripts/build.sh check-android-integration-device
./tools/scripts/build.sh check-ios-app-device
```

## Provider App Examples (`provider_app/`)

Sample apps that implement the **provider** side of the Agent Provider protocol,
demonstrating how to expose actions to an Napaxi host:

| App | Platform | What it demonstrates |
|-----|----------|---------------------|
| `android_smart_desk` | Android | Simple desk height control with install validation |
| `android_smart_home` | Android | Multi-action smart home with background triggers |
| `android_virtual_wallet` | Android | Wallet balance queries with HMAC signing |
| `ios_virtual_wallet` | iOS | Wallet balance queries with `AgentProvider.validateProposal` |

### Integration Flow

1. Host app calls `engine.agentProviderInstall.discoverProviders()`.
2. User selects a provider; host calls `requestInstall()`.
3. Provider app receives the install intent, validates it, and returns a
   signed package.
4. Host registers the package; actions become available through the tool loop.
5. Provider can also trigger actions via background AIDL (Android) or URL
   scheme (iOS).

See `docs/agent-provider-protocol.md` for the full protocol specification.

## Adding Your Own Integration

To embed Napaxi in your own app:

1. Add `napaxi_flutter` (Flutter), the Napaxi SDK Gradle dependency (Android),
   or the Swift Package (iOS) to your project.
2. Build the native library: `./tools/scripts/build.sh fast android` or
   `fast ios`.
   On Windows, run direct `build.sh` commands from Git Bash. Android Gradle
   builds auto-detect Git Bash for this script; if detection fails, set
   `NAPAXI_BASH` to the full path of your Git Bash `bash.exe`.
3. Create an engine with your LLM config and a workspace directory.
4. Open a chat session and stream events.
5. Optionally register custom tools and handle tool dispatch callbacks.

See the per-package READMEs for platform-specific details:

- [`packages/flutter/README.md`](../../packages/flutter/README.md)
- [`packages/android/README.md`](../../packages/android/README.md)
- [`packages/ios/README.md`](../../packages/ios/README.md)
