# Napaxi

This directory contains the first Napaxi app.

The current app is a thin chat UI over `package:napaxi_flutter`. It lets users enter
LLM configuration values, creates SDK-backed chat sessions, and renders Napaxi
chat events in the conversation.

On Android, SDK chat runs are wrapped in a foreground service so the agent can
continue while the demo is backgrounded. Android 13+ prompts for notification
permission the first time background execution starts.

Run it with:

```sh
flutter run
```

Umeng analytics is enabled for the demo with the debug channel by default.
Override the app keys or channel for a specific build with:

```sh
flutter run \
  --dart-define=NAPA_UMENG_ANDROID_APP_KEY=android_app_key \
  --dart-define=NAPA_UMENG_IOS_APP_KEY=ios_app_key \
  --dart-define=NAPA_UMENG_CHANNEL=debug
```

Disable Umeng for local runs with:

```sh
flutter run --dart-define=NAPA_UMENG_ENABLED=false
```

Release Android builds should pass the update and contact-service defines:

```sh
flutter build apk --release \
  --dart-define=PGYER_API_KEY=your_pgyer_api_key \
  --dart-define=PGYER_APP_KEY=your_pgyer_app_key \
  --dart-define=GITHUB_RELEASES_URL=https://github.com/antgroup/Napaxi/releases \
  --dart-define=CONTACT_URL=your_contact_config_url
```

`CONTACT_URL` should be supplied by the release environment, the same way as the
Pgyer keys, so packaged configuration is easy to audit without hard-coding
deployment URLs in source.

`GITHUB_RELEASES_URL` is optional. When Pgyer is unavailable for a self-built
package, the About page can fall back to this releases page and let users
download the latest build manually.

Validate it with:

```sh
flutter analyze --no-fatal-infos
flutter test
dart run tool/check_a2a_user_contract.dart
```
