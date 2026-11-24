// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi/main.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart' as sdk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'test_support.dart';

/// A minimal `NapaxiApp` configuration mirroring the headless setup used by
/// `widget_test.dart`'s `_testApp()` helper. The default store has no agents
/// configured → `_ChatTopBar` renders the `engine_selector_button` branch and
/// `dk.chat.engineEntry` is visible in the semantic tree. This helper is
/// reproduced here because the original `_testApp()` is file-private to
/// `widget_test.dart` and is not exported (per plan.md「widget test 方案」).
Widget _testApp() => NapaxiApp(
      initialLanguage: AppLanguage.english,
      chatClientFactory: () async => FakeNapaxiChatClient(),
      configStore: sdk.NapaxiConfigStore.memory(),
      preferencesStore: MemoryDemoPreferencesStore(),
    );

/// Minimal fake `WebViewPlatform` so that any lazy `WebViewController`
/// construction inside the demo chat client / a2a subscription path (which
/// `widget_test.dart`'s `setUp` installs globally) does not assert under this
/// test file.
class _DkFakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _DkFakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _DkFakePlatformWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _DkFakePlatformWebViewWidget(params);
  }
}

class _DkFakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  _DkFakePlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) : super.implementation(params);

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    onProgress(100);
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}
}

class _DkFakePlatformWebViewController extends PlatformWebViewController {
  _DkFakePlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) : super.implementation(params);

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> loadFile(String absoluteFilePath) async {}
}

class _DkFakePlatformWebViewWidget extends PlatformWebViewWidget {
  _DkFakePlatformWebViewWidget(PlatformWebViewWidgetCreationParams params)
      : super.implementation(params);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFFFFFFF),
      child: Center(child: Text('Web preview')),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebViewPlatform.instance = _DkFakeWebViewPlatform();
  });

  testWidgets('chat shell exposes dk.* semantics labels', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 验收 B 三个必命中点
    expect(find.bySemanticsLabel('dk.chat.composer'), findsOneWidget);
    expect(find.bySemanticsLabel('dk.chat.sendButton'), findsOneWidget);
    expect(find.bySemanticsLabel('dk.chat.engineEntry'), findsOneWidget);

    // 兼顾 session 入口（主链路之一）
    expect(find.bySemanticsLabel('dk.session.listButton'), findsOneWidget);
  });
}
