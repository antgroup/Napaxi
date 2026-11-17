// Integration test smoke — migration target replacing
// examples/flutter/.maestro/smoke_chat_launch.yaml for the on-device
// UI regression layer (DIMA 2026111700120700121).
//
// Why integration_test (Flutter official, in-process driver) instead of
// Maestro: Maestro re-implements iOS device discovery and cannot parse
// Xcode 26.6 DeviceCtl `connectionProperties` (tunnelIPAddress / transport /
// localHostnames), so it reports every device as not-connected. Flutter's
// own `flutter test integration_test/ -d <udid>` reuses the project's
// already-working xcodebuild auto-signing pipeline (build / install /
// launch / VM-service) and never re-implements device discovery — no
// third-party driver, no lag behind Apple tooling.
//
// Run on a real device after a debug build:
//   cd examples/flutter
//   flutter test integration_test/smoke_test.dart -d 00008110-000241423E44801E
// (one suite, no platform branches — verified cross-platform on iOS and
// Android with the same file, per DIMA acceptance criterion 2).
//
// Strings are text-based (Flutter does not expose widget Keys through the
// accessibility tree); they mirror the demo's default Chinese UI defined in
// lib/app/strings.dart (appTitle 'Napaxi', messageHint '给 napaxi 发消息',
// '稍后'), matching the manual selectors in the retired Maestro flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napaxi/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('smoke_chat_launch', (tester) async {
    // 1. Launch the demo app (real main entry: signing/materials/credentials
    //    stay out of files; the same auto-signing chain as the device build).
    app.main();

    // 2. Wait for the chat surface to render (Maestro used extendedWaitUntil
    //    'Napaxi' timeout 30000; pumpAndSettle with the same ceiling).
    await tester.pumpAndSettle(const Duration(seconds: 30));

    // 3. App title visible.
    expect(find.text('Napaxi'), findsAtLeastNWidgets(1));

    // 4. Dismiss the optional in-app update dialog if present (Maestro: tapOn
    //    text '稍后', optional: true).
    final later = find.text('稍后');
    if (later.evaluate().isNotEmpty) {
      await tester.tap(later);
      await tester.pumpAndSettle();
    }

    // 5. Composer hint visible — matches Maestro assertVisible.
    expect(find.text('给 napaxi 发消息'), findsOneWidget);

    // 6. Open the engine-selector popup (tap the title) and assert a known
    //    engine entry, then dismiss the popup (Maestro: back).
    await tester.tap(find.text('Napaxi').first);
    await tester.pumpAndSettle();
    expect(find.text('Codex(beta)'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Hint restored after the popup closes.
    expect(find.text('给 napaxi 发消息'), findsOneWidget);

    // 7. Type into the composer and assert the echo (Maestro: tapOn hint,
    //    inputText '冒烟测试 hello', assertVisible '冒烟测试 hello').
    final composer = find.byType(TextField).first;
    await tester.tap(composer);
    await tester.pumpAndSettle();
    await tester.enterText(composer, '冒烟测试 hello');
    await tester.pump();
    expect(find.text('冒烟测试 hello'), findsOneWidget);

    // Failure-scenario note (DIMA acceptance criterion 4): to prove the gate
    // is real, change any `findsOneWidget` above to `findsNothing` (or alter
    // an expected string) and rerun — the suite fails with the failing
    // matcher + the dart:core stack trace, and `--machine` emits a JSON
    // result with the failure path; `flutter test integration_test/` exits
    // non-zero so the layer-3 verdict is FAIL, not a tool-incompatibility
    // false negative.
  });
}
