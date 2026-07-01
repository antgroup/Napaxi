import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/browser_controller.dart';

void main() {
  test('browser tools reuse the same loaded session', () async {
    final backend = _FakeBrowserBackend();
    final controller = NapaxiBrowserController(backend: backend);

    final firstOpen = jsonDecode(
      await controller.executeTool(
        'browser_open',
        jsonEncode({'url': 'https://example.test/dashboard'}),
      ),
    ) as Map<String, dynamic>;
    expect(firstOpen['success'], true);
    expect(firstOpen['browser_mode'], 'mobile');
    expect(backend.loadCount, 1);
    expect(backend.userAgent, isNull);

    await controller.executeTool(
      'browser_click',
      jsonEncode({'index': 0}),
    );
    await controller.executeTool(
      'browser_type',
      jsonEncode({'index': 1, 'text': 'hello'}),
    );

    final secondOpen = jsonDecode(
      await controller.executeTool(
        'browser_open',
        jsonEncode({'url': 'https://example.test/dashboard'}),
      ),
    ) as Map<String, dynamic>;

    expect(secondOpen['success'], true);
    expect(backend.loadCount, 1);
    expect(backend.clickCount, 1);
    expect(backend.typedText, 'hello');
  });

  test('browser open defaults to mobile and desktop mode applies desktop UA',
      () async {
    final backend = _FakeBrowserBackend();
    final controller = NapaxiBrowserController(backend: backend);

    final mobile = jsonDecode(
      await controller.executeTool(
        'browser_open',
        jsonEncode({'url': 'https://example.test/product'}),
      ),
    ) as Map<String, dynamic>;

    expect(mobile['browser_mode'], 'mobile');
    expect(mobile.containsKey('user_agent'), false);
    expect(backend.userAgent, isNull);
    expect(backend.userAgentCalls, [null]);

    final desktop = jsonDecode(
      await controller.executeTool(
        'browser_open',
        jsonEncode({
          'url': 'https://example.test/product',
          'mode': 'desktop',
        }),
      ),
    ) as Map<String, dynamic>;

    expect(desktop['browser_mode'], 'desktop');
    expect(desktop['user_agent'], napaxiDesktopUserAgent);
    expect(backend.userAgent, napaxiDesktopUserAgent);
    expect(backend.userAgentCalls, [null, napaxiDesktopUserAgent]);
    expect(backend.loadCount, 2);
  });

  test('clear session removes visible state without disposing backend',
      () async {
    final backend = _FakeBrowserBackend();
    final controller = NapaxiBrowserController(backend: backend);

    await controller.executeTool(
      'browser_open',
      jsonEncode({'url': 'https://example.test'}),
    );
    expect(controller.hasPage, true);

    await controller.clearSession();

    expect(controller.hasPage, false);
    expect(backend.clearCacheCount, 1);
    expect(backend.clearLocalStorageCount, 1);
    expect(backend.disposed, false);
  });

  test('snapshot returns structured page state with stable element ids',
      () async {
    final backend = _FakeBrowserBackend();
    final controller = NapaxiBrowserController(backend: backend);

    final result = jsonDecode(
      await controller.executeTool(
        'browser_open',
        jsonEncode({'url': 'https://example.test/product'}),
      ),
    ) as Map<String, dynamic>;

    final pageState = result['page_state'] as Map<String, dynamic>;
    final elements = pageState['elements'] as List<dynamic>;
    expect(result['browser_mode'], 'mobile');
    expect(result.containsKey('user_agent'), false);
    expect(pageState['browser_mode'], 'mobile');
    expect(pageState['user_agent'], isNull);
    expect(result['elements'], elements);
    expect(pageState['viewport'], isA<Map<String, dynamic>>());
    expect(result['viewport_map'], isA<Map<String, dynamic>>());
    expect(result['page_change_token'], isA<String>());
    expect(result['backend_capabilities'], isA<Map<String, dynamic>>());
    expect(result['screenshot_available'], false);
    expect(elements.first, containsPair('element_id', 'e_buy'));
    expect(elements.first, containsPair('risk_hint', 'buy'));
    expect(elements.first, containsPair('interaction_source', 'js_listener'));
    expect(elements.first, containsPair('action_hint', '加入购物车'));
    expect(elements.first['clickable_reason'], contains('js_listener'));
    expect(elements.first, containsPair('clickable_score', 120));
    expect(elements.first['clickable_point'], isA<Map<String, dynamic>>());
  });

  test('click by element id includes latest element fingerprint', () async {
    final backend = _FakeBrowserBackend();
    final controller = NapaxiBrowserController(backend: backend);

    await controller.executeTool(
      'browser_open',
      jsonEncode({'url': 'https://example.test/product'}),
    );
    await controller.executeTool(
      'browser_click',
      jsonEncode({'element_id': 'e_buy'}),
    );

    expect(backend.clickCount, 1);
    expect(backend.lastTargetJavaScript, contains('target_fingerprint'));
    expect(backend.lastTargetJavaScript, contains('立即购买'));
  });

  test('click reports no effect after one recovery retry', () async {
    final backend = _FakeBrowserBackend(simulateNoClickEffect: true);
    final controller = NapaxiBrowserController(backend: backend);

    await controller.executeTool(
      'browser_open',
      jsonEncode({'url': 'https://example.test/product'}),
    );
    final result = jsonDecode(
      await controller.executeTool(
        'browser_click',
        jsonEncode({'element_id': 'e_buy'}),
      ),
    ) as Map<String, dynamic>;

    expect(result['success'], false);
    expect(result['failure_code'], 'no_effect_after_click');
    expect(result['last_action_effect'], isA<Map<String, dynamic>>());
    expect(backend.clickCount, 2);
  });

  test('snapshot can include optional screenshot metadata', () async {
    final backend = _FakeBrowserBackend(
      screenshot: const NapaxiBrowserScreenshot(
        sandboxPath: '/workspace/browser/screenshots/browser.png',
        width: 390,
        height: 720,
      ),
    );
    final controller = NapaxiBrowserController(backend: backend);

    await controller.executeTool(
      'browser_open',
      jsonEncode({'url': 'https://example.test/product'}),
    );
    final result = jsonDecode(
      await controller.executeTool(
        'browser_snapshot',
        jsonEncode({'screenshot_mode': 'always'}),
      ),
    ) as Map<String, dynamic>;

    expect(result['screenshot_available'], true);
    expect(result['screenshot'], isA<Map<String, dynamic>>());
    expect(result['screenshot']['sandbox_path'], startsWith('/workspace/'));
    expect(backend.screenshotCaptureCount, 1);
  });

  test('browser keys and find text dispatch fixed internal scripts', () async {
    final backend = _FakeBrowserBackend();
    final controller = NapaxiBrowserController(backend: backend);

    await controller.executeTool(
      'browser_open',
      jsonEncode({'url': 'https://example.test/product'}),
    );
    final keys = jsonDecode(
      await controller.executeTool(
        'browser_keys',
        jsonEncode({'keys': 'Enter'}),
      ),
    ) as Map<String, dynamic>;
    final find = jsonDecode(
      await controller.executeTool(
        'browser_find_text',
        jsonEncode({'text': '立即购买'}),
      ),
    ) as Map<String, dynamic>;

    expect(keys['success'], true);
    expect(find['success'], true);
    expect(backend.keysCount, 1);
    expect(backend.findTextCount, 1);
  });

  test('browser open rejects local file targets with structured errors',
      () async {
    final controller = NapaxiBrowserController(backend: _FakeBrowserBackend());

    for (final url in [
      'file:///workspace/a.html',
      '/workspace/a.html',
      'workspace/a.html',
      './a.html',
      '../a.html',
      'a.html',
    ]) {
      final result = jsonDecode(
        await controller.executeTool(
          'browser_open',
          jsonEncode({'url': url}),
        ),
      ) as Map<String, dynamic>;

      expect(result['success'], false, reason: url);
      expect(result['failure_code'], 'local_file_not_supported', reason: url);
      expect(
        result['blocked_or_approval_reason'],
        contains('file reading tools'),
        reason: url,
      );
    }
  });

  test('browser open reports unsupported schemes separately', () async {
    final controller = NapaxiBrowserController(backend: _FakeBrowserBackend());

    final result = jsonDecode(
      await controller.executeTool(
        'browser_open',
        jsonEncode({'url': 'ftp://example.test/file'}),
      ),
    ) as Map<String, dynamic>;

    expect(result['success'], false);
    expect(result['failure_code'], 'unsupported_scheme');
  });
}

class _FakeBrowserBackend implements NapaxiBrowserBackend {
  _FakeBrowserBackend({this.simulateNoClickEffect = false, this.screenshot});

  final bool simulateNoClickEffect;
  final NapaxiBrowserScreenshot? screenshot;
  int loadCount = 0;
  int clickCount = 0;
  int keysCount = 0;
  int findTextCount = 0;
  int screenshotCaptureCount = 0;
  int clearCacheCount = 0;
  int clearLocalStorageCount = 0;
  String typedText = '';
  String lastJavaScript = '';
  String lastTargetJavaScript = '';
  String? url;
  String? userAgent;
  final List<String?> userAgentCalls = [];
  bool disposed = false;

  @override
  String? get blockedNavigation => null;

  @override
  BrowserBackendCapabilities get capabilities =>
      BrowserBackendCapabilities(supportsScreenshot: screenshot != null);

  @override
  bool get loading => false;

  @override
  int get progress => 0;

  @override
  Widget buildWidget() => const SizedBox();

  @override
  Future<bool> canGoBack() async => false;

  @override
  Future<void> clearCache() async {
    clearCacheCount += 1;
  }

  @override
  Future<void> clearLocalStorage() async {
    clearLocalStorageCount += 1;
  }

  @override
  Future<NapaxiBrowserScreenshot?> captureScreenshot(
    BrowserScreenshotMode mode,
  ) async {
    screenshotCaptureCount += 1;
    return screenshot;
  }

  @override
  Future<String?> currentUrl() async => url;

  @override
  Future<void> goBack() async {}

  @override
  Future<void> loadUrl(String url) async {
    loadCount += 1;
    this.url = url;
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    this.userAgent = userAgent;
    userAgentCalls.add(userAgent);
  }

  @override
  Future<void> reload() async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<Object?> runJavaScriptReturningResult(String javaScript) async {
    lastJavaScript = javaScript;
    if (javaScript.contains('document.readyState')) {
      return jsonEncode({
        'ready': 'complete',
        'url': url,
        'title': 'Dashboard',
      });
    }
    if ((javaScript.contains("const action = 'click'") ||
            javaScript.contains('const action = "click"')) &&
        javaScript.contains('window.__napaxiBrowser.runTarget')) {
      clickCount += 1;
      lastTargetJavaScript = javaScript;
      return jsonEncode({'success': true});
    }
    if ((javaScript.contains("const action = 'type'") ||
            javaScript.contains('const action = "type"')) &&
        javaScript.contains('window.__napaxiBrowser.runTarget')) {
      final match = RegExp(r'const text = "([^"]*)"').firstMatch(javaScript);
      typedText = match?.group(1) ?? '';
      return jsonEncode({'success': true});
    }
    if (javaScript.contains('window.__napaxiBrowser.sendKeys(keys)')) {
      keysCount += 1;
      return jsonEncode({
        'success': true,
        'keys': ['Enter']
      });
    }
    if (javaScript.contains('window.__napaxiBrowser.findText(text)')) {
      findTextCount += 1;
      return jsonEncode({'success': true, 'text': '立即购买'});
    }
    final clickedSuffix =
        clickCount > 0 && !simulateNoClickEffect ? ' 已加入购物车' : '';
    final pageToken = simulateNoClickEffect
        ? 'token_static'
        : 'token_$clickCount$clickedSuffix';
    return jsonEncode({
      'url': url,
      'title': 'Product',
      'text': 'Signed in dashboard 立即购买$clickedSuffix',
      'elements': [
        {
          'index': 0,
          'element_id': 'e_buy',
          'kind': 'button',
          'role': 'button',
          'tag': 'button',
          'text': '立即购买',
          'label': '',
          'risk_hint': 'buy',
          'interaction_source': 'js_listener',
          'action_hint': '加入购物车',
          'clickable_reason': 'js_listener,action_text:加入购物车',
          'clickable_score': 120,
          'clickable_point': {'x': 120, 'y': 640},
          'fingerprint': {
            'tag': 'button',
            'role': 'button',
            'kind': 'button',
            'text': '立即购买',
          },
        },
        {
          'index': 1,
          'element_id': 'e_search',
          'kind': 'text',
          'role': 'textbox',
          'tag': 'input',
          'label': 'Search',
          'fingerprint': {
            'tag': 'input',
            'role': 'textbox',
            'kind': 'text',
            'label': 'Search',
          },
        },
      ],
      'page_state': {
        'url': url,
        'title': 'Product',
        'viewport': {'width': 390, 'height': 720},
        'scroll': {'x': 0, 'y': 0, 'max_y': 1400},
        'text': 'Signed in dashboard 立即购买$clickedSuffix',
        'page_change_token': pageToken,
        'viewport_map': {
          'width': 390,
          'height': 720,
          'visible_text_blocks': [
            {
              'text': '立即购买',
              'bbox': {'x': 80, 'y': 620, 'width': 120, 'height': 40},
              'center': {'x': 140, 'y': 640},
              'near_action': '加入购物车',
            }
          ],
          'visible_clickable_elements': [
            {
              'element_id': 'e_buy',
              'text': '立即购买',
              'center': {'x': 120, 'y': 640},
              'action_hint': '加入购物车',
            }
          ],
          'overlays': [],
          'diagnostics': [],
        },
        'elements': [
          {
            'index': 0,
            'element_id': 'e_buy',
            'kind': 'button',
            'role': 'button',
            'tag': 'button',
            'text': '立即购买',
            'label': '',
            'risk_hint': 'buy',
            'interaction_source': 'js_listener',
            'action_hint': '加入购物车',
            'clickable_reason': 'js_listener,action_text:加入购物车',
            'clickable_score': 120,
            'clickable_point': {'x': 120, 'y': 640},
            'fingerprint': {
              'tag': 'button',
              'role': 'button',
              'kind': 'button',
              'text': '立即购买',
            },
          },
        ],
      },
    });
  }

  @override
  Future<String?> title() async => 'Product';
}
